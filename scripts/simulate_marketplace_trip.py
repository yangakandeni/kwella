#!/usr/bin/env python3
"""Local marketplace WebSocket lifecycle simulator for kwella.

This script opens two concurrent WebSocket clients against a LocalStack or
API Gateway WebSocket endpoint and drives a mock rider/driver lifecycle in a
stateful progression.

Usage:
  export KWELLA_WS_URL="wss://..."
  export KWELLA_WS_TOKEN="Bearer ..."
  python3 scripts/simulate_marketplace_trip.py

Optional:
  export KWELLA_WS_INSECURE=1  # if the local WebSocket server uses a self-signed cert
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import json
import os
import random
import ssl
import struct
import sys
import urllib.parse
import uuid

try:
    import certifi  # type: ignore[import]
except ImportError:
    certifi = None

GREEN = "\033[0;32m"
YELLOW = "\033[0;33m"
RED = "\033[0;31m"
CYAN = "\033[0;36m"
NC = "\033[0m"
DEFAULT_TIMEOUT = 5.0


class WebSocketHandshakeError(RuntimeError):
    pass


class WebSocketProtocolError(RuntimeError):
    pass


class SimpleWebSocketClient:
    def __init__(self, endpoint: str, auth_token: str | None = None, timeout: float = DEFAULT_TIMEOUT, insecure: bool = False):
        self.endpoint = endpoint
        self.auth_token = auth_token
        self.timeout = timeout
        self.insecure = insecure
        self.reader: asyncio.StreamReader | None = None
        self.writer: asyncio.StreamWriter | None = None
        self.connected = False

    async def connect(self) -> None:
        parsed = urllib.parse.urlparse(self.endpoint)
        if parsed.scheme not in ("ws", "wss"):
            raise WebSocketHandshakeError(f"Unsupported WebSocket scheme: {parsed.scheme}")

        host = parsed.hostname or ""
        port = parsed.port or (443 if parsed.scheme == "wss" else 80)
        ssl_context = None
        if parsed.scheme == "wss":
            ssl_context = self._create_ssl_context()

        try:
            self.reader, self.writer = await asyncio.wait_for(
                asyncio.open_connection(host=host, port=port, ssl=ssl_context, server_hostname=host if ssl_context else None),
                timeout=self.timeout,
            )
        except ssl.SSLCertVerificationError as exc:
            if self.insecure:
                raise
            retry_context = self._create_system_root_ssl_context()
            self.reader, self.writer = await asyncio.wait_for(
                asyncio.open_connection(host=host, port=port, ssl=retry_context, server_hostname=host),
                timeout=self.timeout,
            )

        request_path = self._build_request_path(parsed)
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        headers = [
            f"GET {request_path} HTTP/1.1",
            f"Host: {host}:{port}" if port not in (80, 443) else f"Host: {host}",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Version: 13",
            f"Sec-WebSocket-Key: {key}",
            "User-Agent: kwella-marketplace-simulator/1.0",
        ]

        if self.auth_token:
            headers.append(f"Authorization: {self.auth_token}")
            headers.append("Sec-WebSocket-Protocol: kwella-integration")

        headers.append("\r\n")
        request_bytes = "\r\n".join(headers).encode("ascii")
        self.writer.write(request_bytes)
        await self.writer.drain()

        status_code, response_headers = await self._recv_http_response()
        if status_code != 101:
            raise WebSocketHandshakeError(f"WebSocket upgrade failed: HTTP {status_code}")

        accept_value = response_headers.get("sec-websocket-accept")
        expected = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()).decode("ascii")
        if accept_value != expected:
            raise WebSocketHandshakeError("WebSocket accept header mismatch")

        self.connected = True

    async def _recv_http_response(self) -> tuple[int, dict[str, str]]:
        assert self.reader is not None
        status_line = await asyncio.wait_for(self.reader.readline(), timeout=self.timeout)
        if not status_line:
            raise WebSocketHandshakeError("No response received from WebSocket server")

        decoded = status_line.decode("utf-8", "replace").strip()
        parts = decoded.split(" ", 2)
        if len(parts) < 2:
            raise WebSocketHandshakeError(f"Malformed HTTP status line: {decoded}")

        status_code = int(parts[1])
        headers: dict[str, str] = {}
        while True:
            line = await asyncio.wait_for(self.reader.readline(), timeout=self.timeout)
            if not line:
                raise WebSocketHandshakeError("WebSocket handshake truncated")
            raw = line.decode("utf-8", "replace").strip()
            if raw == "":
                break
            if ":" not in raw:
                continue
            name, value = raw.split(":", 1)
            headers[name.strip().lower()] = value.strip()

        return status_code, headers

    def _create_ssl_context(self) -> ssl.SSLContext:
        ssl_context = ssl.create_default_context()
        if self.insecure:
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
        return ssl_context

    def _create_system_root_ssl_context(self) -> ssl.SSLContext:
        if certifi is not None:
            return ssl.create_default_context(cafile=certifi.where())
        return ssl.create_default_context()

    def _build_request_path(self, parsed: urllib.parse.ParseResult) -> str:
        query = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
        has_auth = any(name.lower() == "authorization" for name, _ in query)
        if self.auth_token and not has_auth:
            query.append(("authorization", self.auth_token))

        path = parsed.path or "/"
        if query:
            path = f"{path}?{urllib.parse.urlencode(query)}"
        return path

    async def send_json(self, payload: dict[str, object]) -> None:
        await self.send_text(json.dumps(payload, separators=(",", ":")))

    async def send_text(self, text: str) -> None:
        if not self.connected or self.writer is None:
            raise WebSocketProtocolError("WebSocket is not connected")
        payload = text.encode("utf-8")
        frame = self._build_frame(opcode=0x1, payload=payload)
        self.writer.write(frame)
        await self.writer.drain()

    def _build_frame(self, opcode: int, payload: bytes) -> bytes:
        header = bytearray()
        header.append(0x80 | opcode)
        length = len(payload)
        mask_key = os.urandom(4)
        if length < 126:
            header.append(0x80 | length)
        elif length < 65536:
            header.append(0x80 | 126)
            header.extend(struct.pack(">H", length))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack(">Q", length))
        header.extend(mask_key)
        masked_payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
        return bytes(header) + masked_payload

    async def recv_text(self, timeout: float | None = None) -> str | None:
        payload = await self._recv_frame(timeout=timeout)
        if payload is None:
            return None
        return payload.decode("utf-8")

    async def recv_json(self, timeout: float | None = None) -> dict[str, object] | None:
        text = await self.recv_text(timeout=timeout)
        if text is None:
            return None
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            raise WebSocketProtocolError(f"Invalid JSON payload received: {exc}") from exc

    async def _recv_frame(self, timeout: float | None = None) -> bytes | None:
        if not self.connected or self.reader is None:
            raise WebSocketProtocolError("WebSocket is not connected")

        reader = self.reader
        raw = await asyncio.wait_for(reader.readexactly(2), timeout=timeout or self.timeout)
        first, second = raw[0], raw[1]
        opcode = first & 0x0F
        masked = bool(second & 0x80)
        length = second & 0x7F
        if length == 126:
            length = int.from_bytes(await reader.readexactly(2), "big")
        elif length == 127:
            length = int.from_bytes(await reader.readexactly(8), "big")

        mask_key = await reader.readexactly(4) if masked else None
        data = await reader.readexactly(length)
        if mask_key is not None:
            data = bytes(b ^ mask_key[i % 4] for i, b in enumerate(data))

        if opcode == 0x8:
            await self.close()
            return None
        if opcode == 0x9:
            await self._send_pong(data)
            return await self._recv_frame(timeout=timeout)
        if opcode == 0xA:
            return await self._recv_frame(timeout=timeout)
        if opcode == 0x1:
            return data
        if opcode == 0x2:
            return data

        raise WebSocketProtocolError(f"Unsupported WebSocket opcode: {opcode}")

    async def _send_pong(self, payload: bytes | None = None) -> None:
        if payload is None:
            payload = b""
        if self.writer is None:
            return
        self.writer.write(self._build_frame(opcode=0xA, payload=payload))
        await self.writer.drain()

    async def close(self) -> None:
        if not self.connected or self.writer is None:
            return
        try:
            self.writer.write(self._build_frame(opcode=0x8, payload=b""))
            await self.writer.drain()
        except Exception:
            pass
        self.writer.close()
        await self.writer.wait_closed()
        self.connected = False


def log_phase(phase: str) -> None:
    print(f"{CYAN}\n=== PHASE: {phase} ==={NC}")


def log_success(message: str) -> None:
    print(f"{GREEN}✓ {message}{NC}")


def log_error(message: str) -> None:
    print(f"{RED}✗ {message}{NC}")


def assert_state(condition: bool, message: str) -> None:
    if not condition:
        log_error(message)
        raise RuntimeError(message)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Simulate a marketplace trip lifecycle via WebSocket.")
    parser.add_argument(
        "--ws-url",
        default=os.environ.get("KWELLA_WS_URL", "ws://localhost:3001"),
        help="WebSocket endpoint URL",
    )
    parser.add_argument("--auth-token", default=os.environ.get("KWELLA_WS_TOKEN"), help="Bearer token for WebSocket authentication")
    parser.add_argument("--insecure", action="store_true", default=os.environ.get("KWELLA_WS_INSECURE", "0") == "1", help="Disable TLS certificate verification for local test endpoints")
    return parser.parse_args()


def normalize_token(token: str | None) -> str | None:
    if token is None:
        return None
    token = token.strip()
    if token and not token.lower().startswith("bearer "):
        return f"Bearer {token}"
    return token


def build_mock_ws_uri(base_ws_url: str, auth_token: str, user_id: str, sim_tag: str) -> str:
    parsed = urllib.parse.urlparse(base_ws_url)
    query_params = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
    query_params.append(("Authorization", auth_token))
    query_params.append(("userId", user_id))
    new_query = urllib.parse.urlencode(query_params)
    return urllib.parse.urlunparse(parsed._replace(query=new_query, fragment=sim_tag))


async def wait_for_action(client: SimpleWebSocketClient, expected_actions: set[str], timeout: float) -> dict[str, object]:
    deadline = asyncio.get_running_loop().time() + timeout
    while True:
        remaining = deadline - asyncio.get_running_loop().time()
        if remaining <= 0:
            raise TimeoutError(f"Did not receive expected server action in {timeout} seconds")
        payload = await client.recv_json(timeout=remaining)
        if payload is None:
            continue
        action = payload.get("action")
        status = payload.get("status")
        if action in expected_actions or status in expected_actions:
            return payload


async def mock_driver_client(endpoint: str, auth_token: str | None, shared: dict[str, object]) -> None:
    driver_id = shared["driver_id"]
    log_phase("2 - Driver Discovery & Bid")
    driver_endpoint = build_mock_ws_uri(endpoint, "MOCK_DRIVER_TOKEN_8765", "DRIVER", "sim-88")
    client = SimpleWebSocketClient(driver_endpoint, auth_token, insecure=shared["insecure"])
    await client.connect()
    log_success("Driver WebSocket connected")

    initial_lat = -33.9240
    initial_lon = 18.4238
    await client.send_json({
        "action": "updateLocation",
        "driverId": driver_id,
        "latitude": initial_lat,
        "longitude": initial_lon,
        "heading": 0,
        "speed": 0,
    })
    response = await client.recv_json(timeout=DEFAULT_TIMEOUT)
    assert_state(response is not None and response.get("status") == "Telemetry Latched", "Driver telemetry update failed")
    log_success("Driver initial telemetry latched")

    offer_payload = await wait_for_action(client, {"rideOfferAvailable"}, timeout=15.0)
    shared["offer_payload"] = offer_payload
    base_fare = float(offer_payload.get("base_fare", 0))
    trip_id = offer_payload.get("tripId")
    assert_state(isinstance(trip_id, str), "rideOfferAvailable missing tripId")
    shared["trip_id"] = trip_id
    log_success(f"Driver received rideOfferAvailable for trip {trip_id}")

    await asyncio.sleep(0.5)
    bid_amount = base_fare + 30.0
    shared["bid_amount"] = bid_amount
    await client.send_json({
        "action": "sendBid",
        "driverId": driver_id,
        "riderId": shared["rider_id"],
        "tripId": trip_id,
        "amount": bid_amount,
    })
    bid_response = await client.recv_json(timeout=DEFAULT_TIMEOUT)
    assert_state(bid_response is not None and bid_response.get("status") == "Success", "Driver sendBid route failed")
    log_success(f"Driver sent counter-bid: R{bid_amount:.2f}")
    shared["bid_sent"] = True

    await shared["rider_selected_event"].wait()
    selection = shared.get("selected_payload")
    assert_state(selection is not None and selection.get("action") == "selectBid", "Driver did not receive rider selection payload")
    log_success("Driver detected rider bid selection")

    await client.send_json({
        "action": "startTrip",
        "driverId": driver_id,
        "tripId": trip_id,
    })
    start_response = await client.recv_json(timeout=DEFAULT_TIMEOUT)
    assert_state(start_response is not None, "Driver startTrip did not receive a response")
    log_success("Driver started trip")

    route_points = [
        (-33.9244, 18.4236),
        (-33.9249, 18.4232),
        (-33.9254, 18.4230),
    ]
    arrival_confirmed = False
    for latitude, longitude in route_points:
        await asyncio.sleep(0.5)
        await client.send_json({
            "action": "updateLocation",
            "driverId": driver_id,
            "latitude": latitude,
            "longitude": longitude,
            "heading": 0,
            "speed": 10,
            "tripId": trip_id,
        })
        update_response = await client.recv_json(timeout=DEFAULT_TIMEOUT)
        assert_state(update_response is not None and update_response.get("status") == "Telemetry Latched", "Driver updateLocation failed")
        flags = update_response.get("flags")
        if isinstance(flags, dict) and flags.get("geofence_status") == "ARRIVED":
            arrival_confirmed = True
            log_success("Driver arrived within 50m geofence and received ARRIVED flag")
            break

    assert_state(arrival_confirmed, "Driver did not arrive within the expected geofence during route sync")
    await client.send_json({
        "action": "confirmArrival",
        "driverId": driver_id,
        "tripId": trip_id,
        "final_bid_amount": bid_amount,
    })
    arrival_response = await client.recv_json(timeout=DEFAULT_TIMEOUT)
    assert_state(arrival_response is not None and arrival_response.get("status") == "WalletSettled", "Driver confirmArrival failed to settle wallet")
    shared["wallet_settled_payload"] = arrival_response
    shared["wallet_settled_event"].set()
    log_success("Driver completed arrival and wallet settlement")

    await client.send_json({
        "action": "submitRating",
        "driverId": driver_id,
        "tripId": trip_id,
        "rating": 5,
        "target": "RIDER",
    })
    try:
        await client.recv_json(timeout=DEFAULT_TIMEOUT)
        log_success("Driver submitted 5-star rating")
    except TimeoutError:
        log_phase("Driver submitRating acknowledged locally (no server response)")

    shared["driver_idle"] = True
    await asyncio.sleep(0.5)
    await client.close()
    log_success("Driver connection returned to idle state")


async def mock_rider_client(endpoint: str, auth_token: str | None, shared: dict[str, object]) -> None:
    rider_id = shared["rider_id"]
    log_phase("1 - Rider Request")
    rider_endpoint = build_mock_ws_uri(endpoint, "MOCK_RIDER_TOKEN_4321", "RIDER", "sim-99")
    client = SimpleWebSocketClient(rider_endpoint, auth_token, insecure=shared["insecure"])
    await client.connect()
    log_success("Rider WebSocket connected")

    pickup = {"latitude": -33.9249, "longitude": 18.4241}
    dropoff = {"latitude": -33.9258, "longitude": 18.4231}
    await client.send_json({
        "action": "requestTrip",
        "riderId": rider_id,
        "pickup_latitude": pickup["latitude"],
        "pickup_longitude": pickup["longitude"],
        "dropoff_latitude": dropoff["latitude"],
        "dropoff_longitude": dropoff["longitude"],
        "passenger_count": 4,
        "suggested_base_fare": 120.0,
    })
    broadcast_response = await client.recv_json(timeout=DEFAULT_TIMEOUT)
    assert_state(broadcast_response is not None and broadcast_response.get("status") == "TripBroadcast", "Rider requestTrip did not receive TripBroadcast")
    trip_id = broadcast_response.get("tripId")
    shared["trip_id"] = trip_id
    log_success(f"Rider requested trip ID {trip_id}")

    bid_payload = await wait_for_action(client, {"driverBidReceived", "tripMatchConfirmed"}, timeout=15.0)
    log_success(f"Rider received bid lifecycle event: {bid_payload.get('action') or bid_payload.get('status')}")

    if bid_payload.get("action") == "driverBidReceived":
        bid_amount = bid_payload.get("amount") or bid_payload.get("bid_amount")
        assert_state(isinstance(bid_amount, (int, float)), "Received driverBidReceived without a numeric bid amount")
        log_success(f"Rider validated driver bid amount: R{float(bid_amount):.2f}")

    selected_driver_id = bid_payload.get("driver_id") or bid_payload.get("driverId") or shared["driver_id"]
    assert_state(isinstance(selected_driver_id, str), "Rider could not resolve driver ID from bid payload")
    select_payload = {
        "action": "selectBid",
        "tripId": trip_id,
        "driverId": selected_driver_id,
    }
    shared["selected_payload"] = select_payload
    await client.send_json(select_payload)
    shared["rider_selected_event"].set()
    log_success("Rider selected driver bid")

    live_updates = []
    while len(live_updates) < 3:
        payload = await wait_for_action(client, {"liveDriverLocation"}, timeout=15.0)
        live_updates.append(payload)
        log_success(f"Rider synced live location update #{len(live_updates)}")

    assert_state(len(live_updates) == 3, "Rider did not receive three liveDriverLocation updates")

    wallet_payload = await wait_for_action(client, {"WalletSettled"}, timeout=15.0)
    log_success("Rider received WalletSettled settlement notification")
    shared["wallet_settled_payload"] = wallet_payload
    shared["wallet_settled_event"].set()

    await client.send_json({
        "action": "submitRating",
        "riderId": rider_id,
        "tripId": trip_id,
        "rating": 5,
        "target": "DRIVER",
    })
    try:
        await client.recv_json(timeout=DEFAULT_TIMEOUT)
        log_success("Rider submitted 5-star rating")
    except TimeoutError:
        log_phase("Rider submitRating acknowledged locally (no server response)")

    shared["rider_idle"] = True
    await asyncio.sleep(0.5)
    await client.close()
    log_success("Rider connection returned to idle state")


async def run_simulation(endpoint: str, auth_token: str | None, insecure: bool) -> None:
    shared: dict[str, object] = {
        "driver_id": f"driver-{uuid.uuid4().hex[:8]}",
        "rider_id": f"rider-{uuid.uuid4().hex[:8]}",
        "insecure": insecure,
        "rider_selected_event": asyncio.Event(),
        "wallet_settled_event": asyncio.Event(),
    }

    log_phase("0 - Marketplace Integration Simulation Startup")
    log_success(f"Target WebSocket endpoint: {endpoint}")
    if insecure:
        log_success("TLS certificate verification is disabled for local testing")

    rider_task = asyncio.create_task(mock_rider_client(endpoint, auth_token, shared))
    driver_task = asyncio.create_task(mock_driver_client(endpoint, auth_token, shared))

    try:
        await asyncio.wait_for(asyncio.gather(rider_task, driver_task), timeout=120.0)
    except Exception as exc:
        rider_task.cancel()
        driver_task.cancel()
        await asyncio.gather(rider_task, driver_task, return_exceptions=True)
        raise

    assert_state(shared.get("rider_idle") is True and shared.get("driver_idle") is True, "One or both clients did not return to idle")
    log_phase("7 - Final Validation")
    log_success("Marketplace trip simulation completed successfully")


def main() -> int:
    args = parse_args()
    if not args.ws_url:
        log_error("KWELLA_WS_URL or --ws-url must be provided")
        return 1
    auth_token = normalize_token(args.auth_token)

    try:
        asyncio.run(run_simulation(args.ws_url, auth_token, args.insecure))
    except Exception as exc:
        log_error(f"Simulation failed: {exc}")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
