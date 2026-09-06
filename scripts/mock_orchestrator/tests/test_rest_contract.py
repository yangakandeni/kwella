"""Unit tests for rest_contract.py — the REST mock's pure logic layer.

Mirrors the style of kwella-backend/tests: plain pytest functions against
the contract functions directly, no HTTP transport involved (that's
rest_server.py's job, which is a thin aiohttp wrapper around this module).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest

import contract
import rest_contract as rc
from state import OrchestratorState


@pytest.fixture
def state() -> OrchestratorState:
    return OrchestratorState(role="rider")


# ---------------------------------------------------------------------------
# Auth/OTP
# ---------------------------------------------------------------------------


def test_initiate_auth_unknown_user_returns_user_not_found(state: OrchestratorState) -> None:
    status, body = rc._initiate_auth(state, {"AuthFlow": "CUSTOM_AUTH", "AuthParameters": {"USERNAME": "+27821234567"}})
    assert status == 400
    assert body["__type"] == "UserNotFoundException"


def test_send_otp_self_provisions_and_logs_fixed_code(state: OrchestratorState) -> None:
    status, body = rc.send_otp(state, {"phoneNumber": "+27821234567"})
    assert status == 200
    assert body["otpCode"] == "123456"
    assert "+27821234567" in state.users


def test_verify_otp_correct_code_issues_tokens(state: OrchestratorState) -> None:
    _, sent = rc.send_otp(state, {"phoneNumber": "+27821234567"})
    status, body = rc.verify_otp(
        state, {"phoneNumber": "+27821234567", "session": sent["session"], "code": "123456"}
    )
    assert status == 200
    assert body["idToken"] and body["accessToken"] and body["refreshToken"]
    claims = rc.decode_jwt_payload(body["idToken"])
    assert claims["sub"] == body["userId"]
    assert claims["cognito:groups"] == ["rider"]


def test_verify_otp_wrong_code_reissues_session_without_tokens(state: OrchestratorState) -> None:
    _, sent = rc.send_otp(state, {"phoneNumber": "+27821234567"})
    status, body = rc.verify_otp(
        state, {"phoneNumber": "+27821234567", "session": sent["session"], "code": "000000"}
    )
    assert status == 401
    assert body["error"] == "IncorrectCode"
    assert body["session"] != sent["session"]


def test_verify_otp_locks_out_after_max_attempts(state: OrchestratorState) -> None:
    _, sent = rc.send_otp(state, {"phoneNumber": "+27821234567"})
    session = sent["session"]
    for _ in range(rc._MAX_OTP_ATTEMPTS - 1):
        _, body = rc.verify_otp(state, {"phoneNumber": "+27821234567", "session": session, "code": "000000"})
        session = body["session"]

    status, body = rc.verify_otp(state, {"phoneNumber": "+27821234567", "session": session, "code": "000000"})
    assert status == 400
    assert body["__type"] == "NotAuthorizedException"


def test_sign_up_then_initiate_auth_succeeds_for_new_number(state: OrchestratorState) -> None:
    phone = "+27829999999"
    status, _ = rc._initiate_auth(state, {"AuthFlow": "CUSTOM_AUTH", "AuthParameters": {"USERNAME": phone}})
    assert status == 400  # not yet provisioned

    rc._sign_up(state, {"Username": phone})
    status, body = rc._initiate_auth(state, {"AuthFlow": "CUSTOM_AUTH", "AuthParameters": {"USERNAME": phone}})
    assert status == 200
    assert body["ChallengeName"] == "CUSTOM_CHALLENGE"


def test_refresh_token_auth_reissues_tokens_without_a_new_refresh_token(state: OrchestratorState) -> None:
    _, sent = rc.send_otp(state, {"phoneNumber": "+27821234567"})
    _, verified = rc.verify_otp(state, {"phoneNumber": "+27821234567", "session": sent["session"], "code": "123456"})

    status, body = rc._initiate_auth(
        state, {"AuthFlow": "REFRESH_TOKEN_AUTH", "AuthParameters": {"REFRESH_TOKEN": verified["refreshToken"]}}
    )
    assert status == 200
    assert "RefreshToken" not in body["AuthenticationResult"]
    assert body["AuthenticationResult"]["IdToken"]


# ---------------------------------------------------------------------------
# Identity/profile
# ---------------------------------------------------------------------------


def test_upsert_rider_profile_requires_phone(state: OrchestratorState) -> None:
    status, body = rc.upsert_profile(state, {"user_id": "abc-123", "role": "RIDER"})
    assert status == 400
    assert body["error"] == "ValidationError"


def test_upsert_driver_profile_round_trips_through_get_profile(state: OrchestratorState) -> None:
    status, _ = rc.upsert_profile(
        state,
        {
            "user_id": "drv-1",
            "role": "DRIVER",
            "phone": "+27821112222",
            "name": "Thabo",
            "assigned_cata_sticker": " ct-001 ",
        },
    )
    assert status == 200

    status, body = rc.get_profile(state, "USR#drv-1", "PROFILE")
    assert status == 200
    assert body["item"]["role"] == "DRIVER"
    assert body["item"]["assigned_cata_sticker"] == "CT-001"


def test_register_vehicle_normalises_and_rejects_duplicates(state: OrchestratorState) -> None:
    payload = {
        "cata_sticker": "ct-002",
        "make": "Toyota",
        "model": "HiAce",
        "color": "White",
        "license_plate": "ca 123-456",
        "owner_id": "USR#drv-1",
    }
    status, body = rc.register_vehicle(state, payload)
    assert status == 200
    assert body["PK"] == "VEH#CT-002"
    assert state.vehicles["CT-002"].license_plate == "CA 123-456"

    status, body = rc.register_vehicle(state, payload)
    assert status == 400
    assert "already registered" in body["detail"]


def test_register_vehicle_requires_usr_prefixed_owner(state: OrchestratorState) -> None:
    status, body = rc.register_vehicle(
        state,
        {
            "cata_sticker": "CT-003",
            "make": "Toyota",
            "model": "HiAce",
            "color": "White",
            "license_plate": "CA123456",
            "owner_id": "drv-1",  # missing USR# prefix
        },
    )
    assert status == 400
    assert "USR#" in body["detail"]


def test_presign_document_upload_then_mock_put_marks_verified(state: OrchestratorState) -> None:
    status, body = rc.presign_document_upload(
        state, {"user_id": "drv-1", "doc_type": "DRIVERS_LICENCE"}, "http://localhost:8790"
    )
    assert status == 200
    assert body["upload_url"] == f"http://localhost:8790/mock-s3/{body['s3_key']}"
    assert state.documents["drv-1:DRIVERS_LICENCE"].status == "PENDING_UPLOAD"

    assert rc.complete_mock_upload(state, body["s3_key"]) is True
    assert state.documents["drv-1:DRIVERS_LICENCE"].status == "VERIFIED"


def test_presign_document_upload_rejects_unknown_doc_type(state: OrchestratorState) -> None:
    status, body = rc.presign_document_upload(state, {"user_id": "drv-1", "doc_type": "PASSPORT"}, "http://x")
    assert status == 400
    assert body["error"] == "ValidationError"


# ---------------------------------------------------------------------------
# Payment
# ---------------------------------------------------------------------------


def test_add_card_detects_visa_brand_and_masks_number(state: OrchestratorState) -> None:
    status, body = rc.add_card(state, {"userId": "usr-1", "cardNumber": "4242424242424242", "cardholderName": "T"})
    assert status == 201
    assert body["brand"] == "VISA"
    assert body["last4"] == "4242"


def test_get_balance_reads_the_same_wallet_the_ws_engine_settles_into(state: OrchestratorState) -> None:
    state.wallets["drv-1"] = 123.45
    status, body = rc.get_balance(state, "drv-1")
    assert status == 200
    assert body["balance"] == 123.45
    assert body["currency"] == "ZAR"


def test_create_and_confirm_payment_intent(state: OrchestratorState) -> None:
    status, body = rc.create_payment_intent(state, {"userId": "usr-1", "amount": 50.0, "tripId": "TRP#1"})
    assert status == 201
    assert body["status"] == "REQUIRES_CONFIRMATION"

    status, body = rc.confirm_payment_intent(state, body["intentId"], {})
    assert status == 200
    assert body["status"] == "SUCCEEDED"


def test_confirm_payment_intent_can_simulate_failure(state: OrchestratorState) -> None:
    _, intent = rc.create_payment_intent(state, {"userId": "usr-1", "amount": 10.0})
    status, body = rc.confirm_payment_intent(state, intent["intentId"], {"simulateFailure": True})
    assert status == 200
    assert body["status"] == "FAILED"


def test_receipt_is_created_automatically_when_a_trip_completes(state: OrchestratorState) -> None:
    driver_state = OrchestratorState(role="driver")
    trip_response, _ = contract.request_trip(
        driver_state,
        {
            "riderId": "rider-1",
            "pickup_latitude": -33.9249,
            "pickup_longitude": 18.4241,
            "dropoff_latitude": -33.9258,
            "dropoff_longitude": 18.4231,
        },
        sender_id="rider-1",
    )
    trip_id = trip_response["tripId"]
    contract.select_bid(driver_state, {"tripId": trip_id, "driverId": "drv-1"}, sender_id=None)
    contract.driver_arrived(driver_state, {"tripId": trip_id}, sender_id="drv-1")
    contract.start_trip(driver_state, {"tripId": trip_id, "driverId": "drv-1"}, sender_id="drv-1")

    status, body = rc.get_receipt(driver_state, trip_id)
    assert status == 404

    contract.confirm_arrival(driver_state, {"tripId": trip_id, "driverId": "drv-1", "final_bid_amount": 100.0}, sender_id="drv-1")

    status, body = rc.get_receipt(driver_state, trip_id)
    assert status == 200
    assert body["fareAmount"] == 100.0
    assert body["netDriverEarnings"] == 85.0
    assert body["platformFee"] == 15.0


# ---------------------------------------------------------------------------
# Maps
# ---------------------------------------------------------------------------


def test_directions_returns_ok_with_positive_distance_and_duration() -> None:
    status, body = rc.directions((-33.9249, 18.4241), (-33.9258, 18.4231))
    assert status == 200
    assert body["status"] == "OK"
    leg = body["routes"][0]["legs"][0]
    assert leg["distance"]["value"] > 0
    assert leg["duration"]["value"] > 0
    assert body["routes"][0]["overview_polyline"]["points"]


def test_place_details_is_deterministic_for_the_same_place_id() -> None:
    _, first = rc.place_details("mock_place_1")
    _, second = rc.place_details("mock_place_1")
    assert first == second
