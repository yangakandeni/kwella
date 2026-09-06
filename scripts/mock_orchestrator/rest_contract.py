"""Wire-compatible re-implementation of the REST/HTTP backend surface.

Companion to `contract.py` (which mirrors the WebSocket bidding engine): this
module mirrors everything a real app talks to over plain HTTP so a rider or
driver app can run fully offline against this mock, with no AWS dependency.

Three of the four areas here are verified field-for-field against a real,
checked-in contract (confirmed by reading the actual handler/client code on
2026-09-06):

  - **Auth/OTP**: the Cognito `CUSTOM_AUTH` passwordless phone flow the apps
    call directly against a Cognito regional endpoint (`InitiateAuth`,
    `SignUp`, `RespondToAuthChallenge`, dispatched by the `X-Amz-Target`
    header) — see `kwella_core/lib/src/auth/auth_notifier.dart`. The fixed
    OTP code mirrors `kwella-backend/src/lambdas/create_auth_challenge/
    handler.py`'s testing-phase default of `"123456"`.
  - **Identity/profile**: `kwella-backend/src/lambdas/identity_service/
    handler.py`'s four actions (`UPSERT_PROFILE`, `REGISTER_VEHICLE`,
    `GET_PROFILE`, `PRESIGN_DOCUMENT_UPLOAD`), field names and validation
    copied verbatim (including the `USR#`/`VEH#` key prefixes and
    uppercase-normalisation of `cata_sticker`/`license_plate`).
  - **Auth token shape**: a 3-part `header.payload.signature` JWT carrying
    `sub`/`phone_number`/`cognito:groups` claims — the real
    `auth_authorizer/handler.py` never checks the signature, only decodes
    the payload, so this is wire-compatible without any signing key.

The other two are **invented** — no real backend contract exists to mirror:

  - **Payment** (`add_card`/`get_balance`/`create_payment_intent`/...): no
    card/wallet/payment-intent/receipt gateway exists anywhere in this
    codebase yet (`payment_method_screen.dart` ships with only "Cash"
    selectable). This is a plausible, self-consistent invented contract for
    local testing of a future payment UI, not a mirror of anything real.
  - **Maps** (`directions`/`place_autocomplete`/`place_details`): the real
    rider app calls Google's Directions/Places APIs directly
    (`maps.googleapis.com`, hardcoded host) — there is no Kwella-owned REST
    contract to mirror. These mock Google's *response shape* for local
    testing, but wiring the app to them requires changing that hardcoded
    host, which is an app-side change out of scope for this server (see
    README's "Known constraints").
"""

from __future__ import annotations

import base64
import json
import logging
import time
import uuid
from typing import Any

from contract import _haversine_m
from state import AuthChallenge, DocumentRecord, OrchestratorState, PaymentCard, PaymentIntent, UserAccount, Vehicle

logger = logging.getLogger("mock_orchestrator.rest")

_OTP_TEST_CODE = "123456"
_MAX_OTP_ATTEMPTS = 3
_ALLOWED_DOC_TYPES = frozenset(
    {"DRIVERS_LICENCE", "PRDP", "VEHICLE_REGISTRATION", "CATA_STICKER_PHOTO", "SELFIE_VERIFICATION"}
)
_CARD_BRANDS = {"4": "VISA", "5": "MASTERCARD", "3": "AMEX"}
_CAPE_TOWN_CBD = (-33.9249, 18.4241)

Response = tuple[int, dict[str, Any]]


def _bad_request(detail: str) -> Response:
    return 400, {"error": "ValidationError", "detail": detail}


def _not_found(detail: str) -> Response:
    return 404, {"error": "NotFound", "detail": detail}


def _iso_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


# ---------------------------------------------------------------------------
# JWT — unsigned, "alg": "none". Wire-compatible because nothing in this
# stack ever checks the signature (see module docstring).
# ---------------------------------------------------------------------------


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _make_jwt(claims: dict[str, Any]) -> str:
    header = _b64url(json.dumps({"alg": "none", "typ": "JWT"}).encode())
    payload = _b64url(json.dumps(claims).encode())
    return f"{header}.{payload}.mock-signature"


def decode_jwt_payload(token: str | None) -> dict[str, Any] | None:
    if not token:
        return None
    parts = token.split(".")
    if len(parts) != 3:
        return None
    padded = parts[1] + "=" * (-len(parts[1]) % 4)
    try:
        return json.loads(base64.urlsafe_b64decode(padded))
    except Exception:
        return None


def _issue_tokens(user_id: str, phone: str, role: str, *, include_refresh: bool = True) -> dict[str, Any]:
    claims = {"sub": user_id, "phone_number": phone, "cognito:groups": [role]}
    result: dict[str, Any] = {
        "IdToken": _make_jwt({**claims, "token_use": "id"}),
        "AccessToken": _make_jwt({**claims, "token_use": "access"}),
        "TokenType": "Bearer",
        "ExpiresIn": 3600,
    }
    if include_refresh:
        result["RefreshToken"] = _make_jwt({**claims, "token_use": "refresh"})
    return result


# ---------------------------------------------------------------------------
# Cognito CUSTOM_AUTH contract — single POST endpoint, dispatched by the
# X-Amz-Target header exactly like the real Cognito regional endpoint.
# ---------------------------------------------------------------------------


def cognito_dispatch(state: OrchestratorState, target: str, body: dict[str, Any]) -> Response:
    if target.endswith("InitiateAuth"):
        return _initiate_auth(state, body)
    if target.endswith("SignUp"):
        return _sign_up(state, body)
    if target.endswith("RespondToAuthChallenge"):
        return _respond_to_auth_challenge(state, body)
    return 400, {"__type": "UnrecognizedClientException", "message": f"Unsupported X-Amz-Target '{target}'."}


def _initiate_auth(state: OrchestratorState, body: dict[str, Any]) -> Response:
    auth_flow = body.get("AuthFlow")
    params = body.get("AuthParameters") or {}

    if auth_flow == "CUSTOM_AUTH":
        phone = params.get("USERNAME")
        if not phone:
            return 400, {"__type": "InvalidParameterException", "message": "USERNAME is required."}
        if phone not in state.users:
            return 400, {"__type": "UserNotFoundException", "message": "User does not exist."}

        session = f"sess_{uuid.uuid4()}"
        state.auth_challenges[session] = AuthChallenge(phone_number=phone, code=_OTP_TEST_CODE)
        logger.info("OTP for %s: %s (session=%s)", phone, _OTP_TEST_CODE, session)
        return 200, {"ChallengeName": "CUSTOM_CHALLENGE", "Session": session, "ChallengeParameters": {"USERNAME": phone}}

    if auth_flow == "REFRESH_TOKEN_AUTH":
        claims = decode_jwt_payload(params.get("REFRESH_TOKEN"))
        if not claims or "sub" not in claims:
            return 400, {"__type": "NotAuthorizedException", "message": "Invalid Refresh Token."}
        groups = claims.get("cognito:groups") or [state.role]
        tokens = _issue_tokens(claims["sub"], claims.get("phone_number", ""), groups[0], include_refresh=False)
        return 200, {"AuthenticationResult": tokens}

    return 400, {"__type": "InvalidParameterException", "message": f"Unsupported AuthFlow '{auth_flow}'."}


def _sign_up(state: OrchestratorState, body: dict[str, Any]) -> Response:
    phone = body.get("Username")
    if not phone:
        return 400, {"__type": "InvalidParameterException", "message": "Username is required."}

    if phone not in state.users:
        user_id = f"usr-{uuid.uuid4()}"
        state.users[phone] = UserAccount(user_id=user_id, phone_number=phone, role=state.role)
        logger.info("Self-provisioned Cognito user for %s -> %s", phone, user_id)

    user = state.users[phone]
    return 200, {"UserConfirmed": True, "UserSub": user.user_id, "CodeDeliveryDetails": {}}


def _respond_to_auth_challenge(state: OrchestratorState, body: dict[str, Any]) -> Response:
    session = body.get("Session")
    responses = body.get("ChallengeResponses") or {}
    phone = responses.get("USERNAME")
    answer = responses.get("ANSWER")

    challenge = state.auth_challenges.get(session)
    if challenge is None or challenge.phone_number != phone:
        return 400, {"__type": "NotAuthorizedException", "message": "Invalid session for the user."}

    if answer == challenge.code:
        del state.auth_challenges[session]
        user = state.users.get(phone)
        if user is None:
            return 400, {"__type": "UserNotFoundException", "message": "User does not exist."}
        tokens = _issue_tokens(user.user_id, phone, user.role)
        return 200, {"ChallengeName": "CUSTOM_CHALLENGE", "AuthenticationResult": tokens}

    challenge.attempts += 1
    del state.auth_challenges[session]
    if challenge.attempts >= _MAX_OTP_ATTEMPTS:
        return 400, {"__type": "NotAuthorizedException", "message": "Incorrect username or password."}

    new_session = f"sess_{uuid.uuid4()}"
    state.auth_challenges[new_session] = challenge
    return 200, {"ChallengeName": "CUSTOM_CHALLENGE", "Session": new_session, "ChallengeParameters": {"USERNAME": phone}}


# ---------------------------------------------------------------------------
# Friendly aliases (`/auth/send-otp`, `/auth/verify-otp`) — plain JSON in/out
# for curl/dashboard testing convenience, sharing the same session store and
# self-provisioning the phone number on first use (skipping the two-call
# UserNotFoundException dance the real app does, since a test script has no
# reason to replicate that).
# ---------------------------------------------------------------------------


def send_otp(state: OrchestratorState, body: dict[str, Any]) -> Response:
    phone = body.get("phoneNumber") or body.get("phone")
    if not phone:
        return _bad_request("'phoneNumber' is required.")

    if phone not in state.users:
        _sign_up(state, {"Username": phone})

    status, resp = _initiate_auth(state, {"AuthFlow": "CUSTOM_AUTH", "AuthParameters": {"USERNAME": phone}})
    if status != 200:
        return status, resp
    return 200, {
        "session": resp["Session"],
        "otpCode": _OTP_TEST_CODE,
        "message": f"OTP sent to {phone} (also logged to server console).",
    }


def verify_otp(state: OrchestratorState, body: dict[str, Any]) -> Response:
    phone = body.get("phoneNumber") or body.get("phone")
    session = body.get("session")
    code = body.get("code") or body.get("otpCode")
    if not phone or not session or not code:
        return _bad_request("'phoneNumber', 'session', and 'code' are required.")

    status, resp = _respond_to_auth_challenge(
        state, {"Session": session, "ChallengeResponses": {"USERNAME": phone, "ANSWER": code}}
    )
    if status != 200:
        return status, resp

    auth_result = resp.get("AuthenticationResult")
    if auth_result is None:
        return 401, {"error": "IncorrectCode", "detail": "Incorrect code. Try again.", "session": resp["Session"]}

    user = state.users[phone]
    return 200, {
        "idToken": auth_result["IdToken"],
        "accessToken": auth_result["AccessToken"],
        "refreshToken": auth_result.get("RefreshToken"),
        "userId": user.user_id,
        "role": user.role,
    }


# ---------------------------------------------------------------------------
# Identity/profile — mirrors identity_service/handler.py's four actions.
# ---------------------------------------------------------------------------


def upsert_profile(state: OrchestratorState, body: dict[str, Any]) -> Response:
    user_id = body.get("user_id")
    role = (body.get("role") or "").upper()
    if not user_id:
        return _bad_request("'user_id' is required for UPSERT_PROFILE.")
    if role not in ("RIDER", "DRIVER"):
        return _bad_request("'role' must be either 'RIDER' or 'DRIVER'.")

    profile = {k: v for k, v in body.items() if k not in ("user_id", "role")}
    if not profile.get("phone"):
        return _bad_request("'phone' is required.")

    if role == "DRIVER":
        missing = [k for k in ("name", "assigned_cata_sticker") if not profile.get(k)]
        if missing:
            return _bad_request(f"Missing required DRIVER fields: {missing}")
        profile["assigned_cata_sticker"] = str(profile["assigned_cata_sticker"]).strip().upper()
        profile.setdefault("fee_holiday_balance", 0.0)
        profile.setdefault("is_online", False)
    else:
        profile.setdefault("cancellation_debt", 0.0)
        profile.setdefault("active_trip_id", None)

    profile.setdefault("rating", 5.0)
    profile["created_at"] = profile.get("created_at") or _iso_now()

    pk, sk = f"USR#{user_id}", "PROFILE"
    state.profiles[user_id] = {"PK": pk, "SK": sk, "role": role, **profile}
    return 200, {"message": "Profile upserted successfully.", "PK": pk, "SK": sk, "role": role}


def register_vehicle(state: OrchestratorState, body: dict[str, Any]) -> Response:
    required = ("cata_sticker", "make", "model", "color", "license_plate", "owner_id")
    missing = [k for k in required if not body.get(k)]
    if missing:
        return _bad_request(f"Missing required fields: {missing}")

    owner_id = str(body["owner_id"])
    if not owner_id.startswith("USR#"):
        return _bad_request(f"owner_id '{owner_id}' must carry the 'USR#' prefix (e.g. 'USR#abc-123').")

    sticker = str(body["cata_sticker"]).strip().upper()
    if sticker in state.vehicles:
        return _bad_request(
            f"Vehicle '{sticker}' is already registered. Use a dedicated update action to amend an existing record."
        )

    vehicle = Vehicle(
        cata_sticker=sticker,
        make=str(body["make"]),
        model=str(body["model"]),
        color=str(body["color"]),
        license_plate=str(body["license_plate"]).strip().upper(),
        owner_id=owner_id,
    )
    state.vehicles[sticker] = vehicle
    return 200, {
        "message": "Vehicle registered successfully.",
        "PK": f"VEH#{sticker}",
        "SK": "METADATA",
        "GSI1_PK": owner_id,
        "GSI1_SK": f"VEH#{sticker}",
    }


def get_profile(state: OrchestratorState, pk: str | None, sk: str | None) -> Response:
    if not pk or not sk:
        return _bad_request("Both 'PK' and 'SK' are required for GET_PROFILE.")

    if sk == "PROFILE" and pk.startswith("USR#"):
        item = state.profiles.get(pk.removeprefix("USR#"))
        if item is None:
            return _not_found("Requested item does not exist.")
        return 200, {"item": item}

    if sk == "METADATA" and pk.startswith("VEH#"):
        vehicle = state.vehicles.get(pk.removeprefix("VEH#"))
        if vehicle is None:
            return _not_found("Requested item does not exist.")
        return 200, {"item": {"PK": pk, "SK": sk, **vehicle.to_dict()}}

    return _not_found("Requested item does not exist.")


def presign_document_upload(state: OrchestratorState, body: dict[str, Any], base_url: str) -> Response:
    user_id = body.get("user_id")
    doc_type = body.get("doc_type")
    content_type = body.get("content_type") or "image/jpeg"

    if not user_id:
        return _bad_request("'user_id' is required for PRESIGN_DOCUMENT_UPLOAD.")
    if doc_type not in _ALLOWED_DOC_TYPES:
        supported = ", ".join(sorted(_ALLOWED_DOC_TYPES))
        return _bad_request(f"'doc_type' must be one of: {supported}.")

    extension = "jpg" if "jpeg" in content_type or "jpg" in content_type else content_type.rsplit("/", 1)[-1]
    s3_key = f"drivers/{user_id}/{doc_type}/{uuid.uuid4()}.{extension}"
    state.documents[f"{user_id}:{doc_type}"] = DocumentRecord(user_id=user_id, doc_type=doc_type, s3_key=s3_key)

    return 200, {"upload_url": f"{base_url}/mock-s3/{s3_key}", "s3_key": s3_key}


def complete_mock_upload(state: OrchestratorState, s3_key: str) -> bool:
    """Called when the app PUTs the raw file to the presigned mock URL.

    Instant success, per the objective's "return instant success states for
    document checks" — there's no human review step in this mock.
    """
    for record in state.documents.values():
        if record.s3_key == s3_key:
            record.status = "VERIFIED"
            return True
    return False


# ---------------------------------------------------------------------------
# Payment — invented (see module docstring: nothing real to mirror).
# ---------------------------------------------------------------------------


def add_card(state: OrchestratorState, body: dict[str, Any]) -> Response:
    user_id = body.get("userId")
    card_number = str(body.get("cardNumber") or "").replace(" ", "")
    if not user_id or len(card_number) < 12 or not card_number.isdigit():
        return _bad_request("'userId' and a valid 'cardNumber' are required.")

    card = PaymentCard(
        id=f"card_{uuid.uuid4().hex[:12]}",
        user_id=user_id,
        brand=_CARD_BRANDS.get(card_number[0], "CARD"),
        last4=card_number[-4:],
        cardholder_name=body.get("cardholderName") or "",
    )
    state.payment_cards[card.id] = card
    return 201, card.to_dict()


def list_cards(state: OrchestratorState, user_id: str | None) -> Response:
    cards = [c.to_dict() for c in state.payment_cards.values() if not user_id or c.user_id == user_id]
    return 200, {"cards": cards}


def get_balance(state: OrchestratorState, user_id: str | None) -> Response:
    if not user_id:
        return _bad_request("'userId' query parameter is required.")
    return 200, {"userId": user_id, "balance": round(state.wallets.get(user_id, 0.0), 2), "currency": "ZAR"}


def create_payment_intent(state: OrchestratorState, body: dict[str, Any]) -> Response:
    user_id = body.get("userId")
    amount = body.get("amount")
    if not user_id or not isinstance(amount, (int, float)) or isinstance(amount, bool) or amount <= 0:
        return _bad_request("'userId' and a positive numeric 'amount' are required.")

    intent = PaymentIntent(
        id=f"pi_{uuid.uuid4().hex[:16]}",
        user_id=user_id,
        trip_id=body.get("tripId"),
        amount=float(amount),
        currency=body.get("currency") or "ZAR",
        client_secret=f"secret_{uuid.uuid4().hex}",
    )
    if body.get("autoConfirm"):
        intent.status = "SUCCEEDED"
    state.payment_intents[intent.id] = intent
    return 201, intent.to_dict()


def confirm_payment_intent(state: OrchestratorState, intent_id: str, body: dict[str, Any]) -> Response:
    intent = state.payment_intents.get(intent_id)
    if intent is None:
        return _not_found(f"Payment intent '{intent_id}' does not exist.")
    intent.status = "FAILED" if body.get("simulateFailure") else "SUCCEEDED"
    return 200, intent.to_dict()


def get_receipt(state: OrchestratorState, trip_id: str) -> Response:
    receipt = state.receipts.get(trip_id)
    if receipt is None:
        return _not_found(f"No receipt for trip '{trip_id}'.")
    return 200, receipt.to_dict()


# ---------------------------------------------------------------------------
# Location/routing (optional) — mocks Google Directions/Places *response
# shape* for local testing. See module docstring: the rider app calls Google
# directly today, so wiring this in requires an app-side base-URL change.
# ---------------------------------------------------------------------------


def _encode_polyline(points: list[tuple[float, float]]) -> str:
    """Google's polyline algorithm (https://developers.google.com/maps/
    documentation/utilities/polylinealgorithm) — the same encoding
    `flutter_polyline_points` decodes on the client."""
    result: list[str] = []
    prev_lat = prev_lon = 0
    for lat, lon in points:
        lat_i, lon_i = round(lat * 1e5), round(lon * 1e5)
        for value, prev in ((lat_i, prev_lat), (lon_i, prev_lon)):
            delta = value - prev
            delta = ~(delta << 1) if delta < 0 else (delta << 1)
            while delta >= 0x20:
                result.append(chr((0x20 | (delta & 0x1F)) + 63))
                delta >>= 5
            result.append(chr(delta + 63))
        prev_lat, prev_lon = lat_i, lon_i
    return "".join(result)


def directions(origin: tuple[float, float], destination: tuple[float, float]) -> Response:
    distance_m = _haversine_m(*origin, *destination) * 1.3  # straight-line -> rough road-distance fudge factor
    duration_s = distance_m / 8.33  # ~30 km/h average urban speed
    body = {
        "status": "OK",
        "routes": [
            {
                "overview_polyline": {"points": _encode_polyline([origin, destination])},
                "legs": [
                    {
                        "distance": {"value": int(distance_m), "text": f"{distance_m / 1000:.1f} km"},
                        "duration": {"value": int(duration_s), "text": f"{max(1, round(duration_s / 60))} mins"},
                    }
                ],
            }
        ],
    }
    return 200, body


def place_autocomplete(query: str, location: tuple[float, float] | None) -> Response:
    origin = location or _CAPE_TOWN_CBD
    predictions = []
    for i, suffix in enumerate(("Street", "Avenue", "Road"), start=1):
        predictions.append(
            {
                "place_id": f"mock_place_{abs(hash((query, i))) % 100_000}",
                "description": f"{query or 'Mock'} {suffix}, Cape Town, South Africa",
                "structured_formatting": {
                    "main_text": f"{query or 'Mock'} {suffix}",
                    "secondary_text": "Cape Town, South Africa",
                },
                "distance_meters": int(_haversine_m(*origin, origin[0] + i * 0.003, origin[1] + i * 0.003)),
            }
        )
    return 200, {"status": "OK", "predictions": predictions}


def place_details(place_id: str) -> Response:
    seed = abs(hash(place_id))
    lat = _CAPE_TOWN_CBD[0] + ((seed % 100) - 50) * 0.0005
    lon = _CAPE_TOWN_CBD[1] + ((seed // 100 % 100) - 50) * 0.0005
    return 200, {"status": "OK", "result": {"geometry": {"location": {"lat": lat, "lng": lon}}}}
