"""HTTP REST mock server — auth/OTP, identity/profile, payment, maps.

Runs alongside the two WebSocket servers in `server.py`, sharing the same
`Engine`/`OrchestratorState` so, for example, `GET /payment/balance` reads
the same driver wallet the WS bidding engine settles into on `confirmArrival`,
and the receipt that action creates is instantly visible at
`GET /payment/receipts/{tripId}`. See `rest_contract.py`'s module docstring
for which routes mirror a real, verified contract vs. which are invented.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

from aiohttp import web

import rest_contract as rc
from engine import Engine

logger = logging.getLogger("mock_orchestrator.rest_server")


def _json_response(status: int, body: dict[str, Any]) -> web.Response:
    return web.Response(status=status, text=json.dumps(body), content_type="application/json")


async def _read_json(request: web.Request) -> dict[str, Any]:
    try:
        return await request.json()
    except json.JSONDecodeError:
        return {}


def _latlng_from_location(location: Any) -> tuple[float, float] | None:
    """Reads a Routes API `{"location": {"latLng": {"latitude", "longitude"}}}` node."""
    if not isinstance(location, dict):
        return None
    lat_lng = location.get("location", {}).get("latLng") if isinstance(location.get("location"), dict) else None
    if not isinstance(lat_lng, dict):
        return None
    try:
        return float(lat_lng["latitude"]), float(lat_lng["longitude"])
    except (KeyError, TypeError, ValueError):
        return None


def _latlng_from_circle_bias(location_bias: Any) -> tuple[float, float] | None:
    """Reads a Places API (New) `{"circle": {"center": {"latitude", "longitude"}}}` node."""
    if not isinstance(location_bias, dict):
        return None
    circle = location_bias.get("circle")
    center = circle.get("center") if isinstance(circle, dict) else None
    if not isinstance(center, dict):
        return None
    try:
        return float(center["latitude"]), float(center["longitude"])
    except (KeyError, TypeError, ValueError):
        return None


def build_app(engine: Engine, base_url: str) -> web.Application:
    state = engine.state
    app = web.Application()

    # -- Cognito-compatible auth (single POST "/", dispatched by X-Amz-Target)
    async def cognito_root(request: web.Request) -> web.Response:
        target = request.headers.get("X-Amz-Target", "")
        body = await _read_json(request)
        status, resp = rc.cognito_dispatch(state, target, body)
        engine.log_event("auth", f"[cognito] {target.rsplit('.', 1)[-1] or '(no target)'} -> {status}", target=target)
        return _json_response(status, resp)

    app.router.add_post("/", cognito_root)

    # -- Friendly OTP aliases (plain JSON, for curl/dashboard testing) -------
    async def send_otp(request: web.Request) -> web.Response:
        body = await _read_json(request)
        status, resp = rc.send_otp(state, body)
        engine.log_event("auth", f"[REST] send-otp {body.get('phoneNumber') or body.get('phone')} -> {status}")
        return _json_response(status, resp)

    async def verify_otp(request: web.Request) -> web.Response:
        body = await _read_json(request)
        status, resp = rc.verify_otp(state, body)
        engine.log_event("auth", f"[REST] verify-otp {body.get('phoneNumber') or body.get('phone')} -> {status}")
        return _json_response(status, resp)

    app.router.add_post("/auth/send-otp", send_otp)
    app.router.add_post("/auth/verify-otp", verify_otp)

    # -- Identity/profile -----------------------------------------------------
    async def identity_upsert(request: web.Request) -> web.Response:
        body = await _read_json(request)
        status, resp = rc.upsert_profile(state, body)
        engine.log_event("identity", f"[REST] upsert profile {body.get('user_id')} -> {status}")
        return _json_response(status, resp)

    async def identity_vehicle(request: web.Request) -> web.Response:
        body = await _read_json(request)
        status, resp = rc.register_vehicle(state, body)
        engine.log_event("identity", f"[REST] register vehicle {body.get('cata_sticker')} -> {status}")
        return _json_response(status, resp)

    async def identity_profile_get(request: web.Request) -> web.Response:
        status, resp = rc.get_profile(state, request.query.get("PK"), request.query.get("SK"))
        return _json_response(status, resp)

    async def identity_documents_presign(request: web.Request) -> web.Response:
        body = await _read_json(request)
        status, resp = rc.presign_document_upload(state, body, base_url)
        engine.log_event("identity", f"[REST] presign {body.get('doc_type')} for {body.get('user_id')} -> {status}")
        return _json_response(status, resp)

    app.router.add_post("/identity/upsert", identity_upsert)
    app.router.add_post("/identity/vehicle", identity_vehicle)
    app.router.add_get("/identity/profile", identity_profile_get)
    app.router.add_post("/identity/documents/presign", identity_documents_presign)

    # `/user/profile` alias (the objective's literal naming) over the same
    # USR#<id>/PROFILE item `/identity/profile` reads.
    async def user_profile_get(request: web.Request) -> web.Response:
        user_id = request.query.get("userId") or request.query.get("user_id")
        pk = f"USR#{user_id}" if user_id else None
        status, resp = rc.get_profile(state, pk, "PROFILE")
        return _json_response(status, resp)

    app.router.add_get("/user/profile", user_profile_get)

    # -- Mock S3 (presigned upload target) -------------------------------------
    async def mock_s3_put(request: web.Request) -> web.Response:
        key = request.match_info["key"]
        await request.read()  # drain the body; bytes are discarded, this is a mock
        verified = rc.complete_mock_upload(state, key)
        engine.log_event("document", f"[REST] mock-s3 PUT {key} -> {'VERIFIED' if verified else 'unknown key'}")
        return web.Response(status=200)

    app.router.add_put("/mock-s3/{key:.*}", mock_s3_put)

    # -- Payment (invented — see rest_contract.py's module docstring) ---------
    async def payment_add_card(request: web.Request) -> web.Response:
        body = await _read_json(request)
        status, resp = rc.add_card(state, body)
        engine.log_event("payment", f"[REST] add card for {body.get('userId')} -> {status}")
        return _json_response(status, resp)

    async def payment_list_cards(request: web.Request) -> web.Response:
        status, resp = rc.list_cards(state, request.query.get("userId"))
        return _json_response(status, resp)

    async def payment_balance(request: web.Request) -> web.Response:
        status, resp = rc.get_balance(state, request.query.get("userId"))
        return _json_response(status, resp)

    async def payment_create_intent(request: web.Request) -> web.Response:
        body = await _read_json(request)
        status, resp = rc.create_payment_intent(state, body)
        engine.log_event(
            "payment", f"[REST] payment intent for {body.get('userId')} amount={body.get('amount')} -> {status}"
        )
        return _json_response(status, resp)

    async def payment_confirm_intent(request: web.Request) -> web.Response:
        intent_id = request.match_info["intent_id"]
        body = await _read_json(request)
        status, resp = rc.confirm_payment_intent(state, intent_id, body)
        engine.log_event("payment", f"[REST] confirm intent {intent_id} -> {resp.get('status', status)}")
        return _json_response(status, resp)

    async def payment_get_receipt(request: web.Request) -> web.Response:
        status, resp = rc.get_receipt(state, request.match_info["trip_id"])
        return _json_response(status, resp)

    app.router.add_post("/payment/cards", payment_add_card)
    app.router.add_get("/payment/cards", payment_list_cards)
    app.router.add_get("/payment/balance", payment_balance)
    app.router.add_post("/payment/intents", payment_create_intent)
    app.router.add_post("/payment/intents/{intent_id}/confirm", payment_confirm_intent)
    app.router.add_get("/payment/receipts/{trip_id}", payment_get_receipt)

    # -- Location/routing (optional) --------------------------------------------
    async def maps_directions(request: web.Request) -> web.Response:
        body = await _read_json(request)
        origin = _latlng_from_location(body.get("origin"))
        destination = _latlng_from_location(body.get("destination"))
        if origin is None or destination is None:
            return _json_response(
                400,
                {"error": {"code": 400, "message": "Invalid origin/destination.", "status": "INVALID_ARGUMENT"}},
            )
        status, resp = rc.directions(origin, destination)
        return _json_response(status, resp)

    async def maps_autocomplete(request: web.Request) -> web.Response:
        body = await _read_json(request)
        location = _latlng_from_circle_bias(body.get("locationBias"))
        status, resp = rc.place_autocomplete(body.get("input", ""), location)
        return _json_response(status, resp)

    async def maps_place_details(request: web.Request) -> web.Response:
        status, resp = rc.place_details(request.query.get("place_id", ""))
        return _json_response(status, resp)

    app.router.add_post("/maps/directions", maps_directions)
    app.router.add_post("/maps/place/autocomplete", maps_autocomplete)
    app.router.add_get("/maps/place/details", maps_place_details)

    return app


async def run_rest_server(engine: Engine, host: str, port: int) -> None:
    display_host = "localhost" if host == "0.0.0.0" else host
    base_url = f"http://{display_host}:{port}"
    app = build_app(engine, base_url)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, host, port)
    await site.start()
    logger.info("REST mock server listening on %s", base_url)
    await asyncio.Event().wait()
