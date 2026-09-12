#!/usr/bin/env python3
"""Kwella mock marketplace orchestration server.

Stands in for the real AWS API Gateway WebSocket bidding engine
(`kwella-backend/src/lambdas/bidding_engine/handler.py`) so a single Flutter
app — rider OR driver — can be manually tested on an Android emulator
against realistic multi-entity background actors, with no second live app
instance and no AWS backend required.

Three servers run in this one process:
  - the "app" WebSocket server (default port 8788): the real Flutter app
    connects here exactly as it would to API Gateway. Speaks the same
    action/status JSON contract as the real Lambda (see contract.py).
  - the "control" server (default port 8789): serves the dashboard
    (dashboard.html) over plain HTTP at `/`, and a control WebSocket at
    `/control` that the dashboard's JS uses to push commands and receive
    live state + event-log updates.
  - the "REST" server (default port 8790, see rest_server.py): mocks the
    rest of the backend the two apps need to run fully standalone — Cognito
    OTP auth, identity/profile/vehicle/document upload, payment, and a
    Google Maps-shaped location/routing mock. See rest_contract.py's module
    docstring for exactly which routes mirror a real contract vs. are
    invented.

Usage:
  python3 server.py --role rider --scenario scenarios/rider_mode.json
  python3 server.py --role driver --scenario scenarios/driver_mode.json

Then point the app under test at ws://<this-machine-on-the-LAN-or-10.0.2.2>:8788
and open http://localhost:8789 for the dashboard. See README.md.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import urllib.parse
from pathlib import Path
from typing import Any

import websockets.asyncio.server as ws_server
from websockets.datastructures import Headers
from websockets.exceptions import ConnectionClosed
from websockets.http11 import Response

from engine import Engine
from rest_server import run_rest_server

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("mock_orchestrator")

DASHBOARD_HTML_PATH = Path(__file__).parent / "dashboard.html"


def load_scenario(path: str | None) -> dict[str, Any]:
    if not path:
        return {"personas": []}
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def _entity_id_from_payload(role: str, payload: dict[str, Any]) -> str | None:
    if role == "rider":
        return payload.get("riderId") or payload.get("rider_id")
    return payload.get("driverId") or payload.get("driver_id")


# ---------------------------------------------------------------------------
# App-facing WebSocket server — the real Flutter app connects here.
# ---------------------------------------------------------------------------


def _reject_non_websocket_request(connection: ws_server.ServerConnection, request) -> Response | None:
    """Diagnose and explain a `426 Upgrade Required` instead of the library's silent empty-body default.

    The real cause is always the same: something hit `ws://host:8788` with a plain
    HTTP request (a browser, curl without `-H "Upgrade: websocket"`, or a client
    mistakenly using `http://` instead of `ws://`) — the port only ever speaks the
    WebSocket handshake. Logging the actual headers here turns "426 Upgrade
    Required" (which gives no clue why) into an actionable message.
    """
    path = urllib.parse.urlparse(request.path).path
    headers = request.headers
    upgrade = headers.get("Upgrade", "")
    conn_header = headers.get("Connection", "")
    if upgrade.lower() == "websocket" and "upgrade" in conn_header.lower():
        return None  # proceed with the normal WS handshake

    logger.warning(
        "Rejecting non-WebSocket request on app port: method=%s path=%s Upgrade=%r Connection=%r "
        "Sec-WebSocket-Version=%r -- this port only accepts ws:// WebSocket connections, not http(s)://.",
        request.method,
        path,
        upgrade or None,
        conn_header or None,
        headers.get("Sec-WebSocket-Version"),
    )
    body = (
        b"This is a WebSocket-only endpoint (Kwella mock bidding engine).\n"
        b"Connect with ws:// (or wss://), not http(s)://, and make sure your client "
        b"sends the 'Upgrade: websocket' and 'Connection: Upgrade' handshake headers.\n"
        b"See scripts/mock_orchestrator/README.md for working websocat/wscat examples.\n"
    )
    response_headers = Headers()
    response_headers["Content-Type"] = "text/plain; charset=utf-8"
    response_headers["Content-Length"] = str(len(body))
    return Response(426, "Upgrade Required", response_headers, body)


async def run_app_server(engine: Engine, host: str, port: int) -> None:
    async def handler(connection: ws_server.ServerConnection) -> None:
        path = connection.request.path if connection.request else "/"
        query = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(path).query))
        user_id = query.get("userId") or query.get("userid")
        logger.info("App connection opened. path=%s userId=%s", path, user_id)

        async def send(payload: dict[str, Any]) -> None:
            await connection.send(json.dumps(payload))

        engine.register_real_connection(send)
        if user_id and engine.state.role == "driver":
            engine.note_real_entity_id(user_id)

        try:
            async for raw_message in connection:
                try:
                    payload = json.loads(raw_message)
                except (json.JSONDecodeError, TypeError):
                    await connection.send(json.dumps({"error": "ValidationError", "detail": "Body must be valid JSON."}))
                    continue

                action = payload.get("action")
                if not action:
                    await connection.send(json.dumps({"error": "ValidationError", "detail": "Missing 'action'."}))
                    continue

                sender_id = _entity_id_from_payload(engine.state.role, payload)
                if sender_id:
                    engine.note_real_entity_id(sender_id)

                response = await engine.handle_action(action, payload, engine.state.real_entity_id, source="real-app")
                await connection.send(json.dumps(response))
        except ConnectionClosed:
            pass
        finally:
            engine.unregister_real_connection()
            logger.info("App connection closed.")

    server = await ws_server.serve(handler, host, port, process_request=_reject_non_websocket_request)
    logger.info("App-facing WebSocket server listening on ws://%s:%s", host, port)
    async with server:
        await asyncio.get_running_loop().create_future()


# ---------------------------------------------------------------------------
# Control/dashboard server — serves dashboard.html over HTTP, and a control
# WebSocket at /control for live state + commands.
# ---------------------------------------------------------------------------


def _serve_dashboard_html() -> Response:
    body = DASHBOARD_HTML_PATH.read_bytes()
    headers = Headers()
    headers["Content-Type"] = "text/html; charset=utf-8"
    headers["Content-Length"] = str(len(body))
    return Response(200, "OK", headers, body)


async def run_control_server(engine: Engine, host: str, port: int) -> None:
    async def process_request(connection: ws_server.ServerConnection, request) -> Response | None:
        path = urllib.parse.urlparse(request.path).path
        if path in ("/", "/index.html") and request.headers.get("Upgrade", "").lower() != "websocket":
            return _serve_dashboard_html()
        return None  # proceed with the WS handshake (path == "/control")

    async def handler(connection: ws_server.ServerConnection) -> None:
        async def send(payload: dict[str, Any]) -> None:
            await connection.send(json.dumps(payload))

        engine.add_dashboard_subscriber(send)
        await send({"type": "state", "state": engine.state.snapshot()})
        for entry in engine.state.log[-100:]:
            await send({"type": "log", "entry": entry})

        try:
            async for raw_message in connection:
                try:
                    msg = json.loads(raw_message)
                except (json.JSONDecodeError, TypeError):
                    continue
                if msg.get("type") != "command":
                    continue
                await _handle_dashboard_command(engine, msg.get("cmd", ""), msg.get("params") or {})
        except ConnectionClosed:
            pass
        finally:
            engine.remove_dashboard_subscriber(send)

    server = await ws_server.serve(handler, host, port, process_request=process_request)
    logger.info("Dashboard available at http://%s:%s (control WS at /control)", host, port)
    async with server:
        await asyncio.get_running_loop().create_future()


async def _handle_dashboard_command(engine: Engine, cmd: str, params: dict[str, Any]) -> None:
    if cmd == "setNetwork":
        if "latencyMs" in params:
            engine.state.network.latency_ms = int(params["latencyMs"])
        if "dropRate" in params:
            engine.state.network.drop_rate = float(params["dropRate"])
        engine.broadcast_state()
        return

    if cmd == "addPersona":
        engine.add_persona(params)
        return

    if cmd == "removePersona":
        engine.remove_persona(params["personaId"])
        return

    if cmd == "setPersonaBehavior":
        engine.set_persona_behavior(params["personaId"], params["behavior"])
        return

    if cmd == "sendBid":
        await engine.handle_action(
            "sendBid",
            {
                "driverId": params["personaId"],
                "tripId": params["tripId"],
                "amount": params["amount"],
                "etaMinutes": params.get("etaMinutes", 5),
            },
            params["personaId"],
            source="dashboard",
        )
        return

    if cmd == "declineOffer":
        await engine.decline_offer(params["personaId"], params["tripId"])
        return

    if cmd == "selectBid":
        await engine.handle_action(
            "selectBid",
            {"tripId": params["tripId"], "driverId": params["driverId"]},
            None,
            source="dashboard",
        )
        return

    if cmd == "driverStep":
        await engine.driver_step(params["personaId"], params["step"], params)
        return

    if cmd == "triggerRequestTrip":
        await engine.handle_action(
            "requestTrip",
            {
                "riderId": params["personaId"],
                "pickup_latitude": params["pickupLat"],
                "pickup_longitude": params["pickupLon"],
                "dropoff_latitude": params["dropoffLat"],
                "dropoff_longitude": params["dropoffLon"],
                "passenger_count": params.get("passengerCount", 1),
                "payment_method": params.get("paymentMethod", "CASH"),
            },
            params["personaId"],
            source="dashboard",
        )
        return

    logger.warning("Unknown dashboard command: %s", cmd)


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--role", choices=["rider", "driver"], required=True, help="Which real app is under test.")
    parser.add_argument("--scenario", default=None, help="Path to a scenario JSON file (see scenarios/).")
    parser.add_argument("--host", default="0.0.0.0", help="Bind host for both servers.")
    parser.add_argument("--app-port", type=int, default=8788, help="Port the real app's WebSocket connects to.")
    parser.add_argument("--control-port", type=int, default=8789, help="Port for the dashboard HTTP + control WS.")
    parser.add_argument(
        "--rest-port", type=int, default=8790, help="Port for the REST mock (auth/identity/payment/maps)."
    )
    return parser.parse_args()


async def main_async() -> None:
    args = parse_args()
    scenario = load_scenario(args.scenario)
    engine = Engine(role=args.role, scenario=scenario)

    logger.info(
        "Starting mock orchestrator: role=%s personas=%d scenario=%s",
        args.role,
        len(engine.state.personas),
        args.scenario or "(none)",
    )

    await asyncio.gather(
        run_app_server(engine, args.host, args.app_port),
        run_control_server(engine, args.host, args.control_port),
        run_rest_server(engine, args.host, args.rest_port),
    )


def main() -> None:
    try:
        asyncio.run(main_async())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
