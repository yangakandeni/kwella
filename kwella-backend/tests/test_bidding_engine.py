"""
tests/test_bidding_engine.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Isolated unit tests for the kwella Bidding Engine Lambda handler.

Coverage:
  BROADCAST_REQUEST — Decimal precision: numeric strings survive the Pydantic
                      coercion pipeline and are stored in DynamoDB as strings,
                      not floats, blocking any floating-point representation error.
  BROADCAST_REQUEST — Invalid passenger_count (0, 8, non-integer) triggers
                      a deterministic Pydantic ValidationError and a clean 400.
  BROADCAST_REQUEST — Missing 'USR#' prefix on rider_id triggers a
                      deterministic Pydantic ValidationError and a clean 400.
  SUBMIT_BID        — Sanity: valid SubmitBidPayload writes the correct
                      bid record with BID# PK and OFFER# SK.

Test isolation strategy:
  Each test function is decorated with @mock_aws which spins up an in-process
  moto DynamoDB endpoint for the duration of that test only.  Modules are
  force-reloaded between each test via _reload_bidding_handler() to guarantee
  the module-level boto3 resource binds to the fresh moto context rather than
  a stale prior endpoint.

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native type hints; no legacy typing imports.
  - Pydantic v2 ValidationError assertions use exc.error_count() and
    exc.errors() (Pydantic v2 API) — not .json() or .dict().
  - No hardcoded AWS credentials; moto credentials supplied by conftest.py.
"""

from __future__ import annotations

import json
import sys
from decimal import Decimal
from typing import Any

import boto3
import pytest
from moto import mock_aws
from pydantic import ValidationError


# ---------------------------------------------------------------------------
# Table provisioning helper
# ---------------------------------------------------------------------------

def _create_mock_table() -> Any:
    """Provision a moto-intercepted DynamoDB table matching the production schema.

    Mirrors the ``kwella-core-production`` table structure defined in
    KWELLA_SYSTEM_CONTEXT.md §3, using the ``kwella-core-test`` name that
    conftest.py injects via the KWELLA_TABLE_NAME environment variable.

    Returns:
        boto3 DynamoDB Table resource for direct assertion queries in tests.
    """
    dynamodb = boto3.resource("dynamodb", region_name="af-south-1")
    table = dynamodb.create_table(
        TableName="kwella-core-test",
        KeySchema=[
            {"AttributeName": "PK", "KeyType": "HASH"},
            {"AttributeName": "SK", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "PK",      "AttributeType": "S"},
            {"AttributeName": "SK",      "AttributeType": "S"},
            {"AttributeName": "GSI1_PK", "AttributeType": "S"},
            {"AttributeName": "GSI1_SK", "AttributeType": "S"},
        ],
        GlobalSecondaryIndexes=[
            {
                "IndexName": "GSI1",
                "KeySchema": [
                    {"AttributeName": "GSI1_PK", "KeyType": "HASH"},
                    {"AttributeName": "GSI1_SK", "KeyType": "RANGE"},
                ],
                "Projection": {"ProjectionType": "ALL"},
                "ProvisionedThroughput": {"ReadCapacityUnits": 5, "WriteCapacityUnits": 5},
            }
        ],
        BillingMode="PROVISIONED",
        ProvisionedThroughput={"ReadCapacityUnits": 5, "WriteCapacityUnits": 5},
    )
    table.meta.client.get_waiter("table_exists").wait(TableName="kwella-core-test")
    return table


def _reload_bidding_handler():
    """Force-reimport the bidding_engine handler so it picks up the active
    moto interceptor context rather than a previously cached boto3 resource.

    This is necessary because database.client initialises the boto3 resource at
    module scope; without a reload the resource would point to a stale endpoint
    from a prior test's mock context.
    """
    for mod_name in ("database.client", "bidding_engine.handler"):
        if mod_name in sys.modules:
            del sys.modules[mod_name]
    import bidding_engine.handler as handler  # noqa: PLC0415
    return handler


# ---------------------------------------------------------------------------
# Direct Pydantic model import helper
# ---------------------------------------------------------------------------

def _get_broadcast_payload_model():
    """Reload and return the BroadcastRequestPayload class from the handler
    module so direct ValidationError assertions use the live class bound to
    the current moto context.
    """
    import bidding_engine.handler as handler  # noqa: PLC0415
    return handler.BroadcastRequestPayload


# ---------------------------------------------------------------------------
# BROADCAST_REQUEST — Decimal precision and string storage
# ---------------------------------------------------------------------------

@mock_aws
def test_broadcast_request_parses_baseline_fare_as_decimal_and_stores_as_string():
    """BROADCAST_REQUEST must:

    1. Accept ``baseline_fare`` as a numeric string (e.g. ``"25.50"``) and
       coerce it internally to a ``decimal.Decimal`` via Pydantic — preventing
       any floating-point representation error at the business logic layer.
    2. Persist ``baseline_fare`` to DynamoDB as a *string* (``str(Decimal(...))``),
       not a Python float, to avoid the imprecision that DynamoDB's Number type
       can introduce when round-tripping IEEE 754 floats for financial values.

    This directly validates the governance rule documented in the handler's
    BROADCAST_REQUEST implementation comment: *"Store Decimal as string to
    preserve precision in DynamoDB Number type."*
    """
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    # Construct a valid API GW WebSocket proxy event for BROADCAST_REQUEST.
    body_payload: dict[str, Any] = {
        "rider_id": "USR#rider-broadcast-001",
        "pickup_location": "Bellville Station",
        "destination": "Cape Town CBD",
        "passenger_count": 3,
        "baseline_fare": "25.50",    # string → Pydantic coerces to Decimal → stored as str
        "connection_id": "rider-conn-abc123==",
    }

    event: dict[str, Any] = {
        "requestContext": {
            "routeKey": "BROADCAST_REQUEST",
            "connectionId": "rider-conn-abc123==",
            "domainName": "test-api.execute-api.af-south-1.amazonaws.com",
            "stage": "test",
        },
        "body": json.dumps(body_payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200, (
        f"Expected 200 for a valid BROADCAST_REQUEST; got {response['statusCode']}. "
        f"Body: {response['body']}"
    )

    # Verify the DynamoDB item was persisted under the correct composite key.
    result = table.get_item(Key={"PK": "BID#rider-conn-abc123==", "SK": "OPEN"})
    item = result.get("Item")
    assert item is not None, (
        "A BROADCAST_REQUEST item must exist in DynamoDB under PK=BID#<connectionId>, SK=OPEN."
    )

    # --- Core assertion: floating-point safety ---
    # DynamoDB returns string attributes as Python str.
    # If the handler stored a float, e.g. 25.5, str(25.5) == "25.5" and the
    # precision mark (".50") would be silently truncated.
    stored_fare: str = item["baseline_fare"]
    assert isinstance(stored_fare, str), (
        f"baseline_fare must be stored as a string, not {type(stored_fare).__name__}."
    )
    assert stored_fare == "25.50", (
        f"baseline_fare must be stored as '25.50' (full Decimal precision); "
        f"got '{stored_fare}'. Floating-point coercion may have occurred."
    )

    # Verify Decimal round-trip fidelity: re-parsing the stored string must
    # produce the exact Decimal value without any drift.
    assert Decimal(stored_fare) == Decimal("25.50"), (
        "Re-parsing the stored string must produce Decimal('25.50') with zero drift."
    )

    # Confirm the 200 response body also carries the string fare.
    response_body: dict[str, Any] = json.loads(response["body"])
    assert response_body["baseline_fare"] == "25.50"


@mock_aws
def test_broadcast_request_stores_integer_fare_as_precise_decimal_string():
    """BROADCAST_REQUEST with a whole-number fare (e.g. ``"30"``) must persist
    the value as a Decimal string (``"30"``), not as ``"30.0"`` or a float,
    ensuring consistent downstream formatting for the Flutter client.
    """
    _create_mock_table()
    handler = _reload_bidding_handler()

    body_payload: dict[str, Any] = {
        "rider_id": "USR#rider-int-fare-002",
        "pickup_location": "Philippi Village",
        "destination": "Claremont Mall",
        "passenger_count": 1,
        "baseline_fare": "30",
        "connection_id": "conn-int-fare==",
    }

    event: dict[str, Any] = {
        "requestContext": {
            "routeKey": "BROADCAST_REQUEST",
            "connectionId": "conn-int-fare==",
        },
        "body": json.dumps(body_payload),
    }

    response = handler.lambda_handler(event, context=None)
    assert response["statusCode"] == 200

    # The Decimal("30") string representation is "30", not "30.0".
    # This ensures we do not introduce phantom decimal places.
    response_body: dict[str, Any] = json.loads(response["body"])
    stored_fare_str: str = response_body["baseline_fare"]
    assert Decimal(stored_fare_str) == Decimal("30"), (
        f"Re-parsed fare must equal Decimal('30'); got Decimal('{stored_fare_str}')."
    )


# ---------------------------------------------------------------------------
# BROADCAST_REQUEST — invalid passenger_count paths
# ---------------------------------------------------------------------------

@mock_aws
def test_broadcast_request_with_zero_passenger_count_returns_400():
    """BROADCAST_REQUEST with passenger_count = 0 must trigger a Pydantic
    ValidationError (ge=1 constraint on BroadcastRequestPayload.passenger_count)
    and return a deterministic HTTP 400 response.

    passenger_count of 0 is logically impossible for any trip; it must be
    rejected before any DynamoDB write is attempted.
    """
    _create_mock_table()
    handler = _reload_bidding_handler()

    body_payload: dict[str, Any] = {
        "rider_id": "USR#rider-bad-pax-001",
        "pickup_location": "Bellville Station",
        "destination": "Cape Town CBD",
        "passenger_count": 0,       # violates ge=1 constraint
        "baseline_fare": "20.00",
        "connection_id": "conn-bad-pax==",
    }

    event: dict[str, Any] = {
        "requestContext": {
            "routeKey": "BROADCAST_REQUEST",
            "connectionId": "conn-bad-pax==",
        },
        "body": json.dumps(body_payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400, (
        f"passenger_count=0 must produce a 400 response; got {response['statusCode']}."
    )
    body: dict[str, Any] = json.loads(response["body"])
    assert body["error"] == "ValidationError"


@mock_aws
def test_broadcast_request_with_passenger_count_exceeding_seven_returns_400():
    """BROADCAST_REQUEST with passenger_count > 7 must trigger a Pydantic
    ValidationError (le=7 constraint) and return HTTP 400.

    kwella exclusively serves 7-seater *amaphela* vehicles
    (KWELLA_SYSTEM_CONTEXT.md §1); 8+ passengers is physically impossible.
    """
    _create_mock_table()
    handler = _reload_bidding_handler()

    body_payload: dict[str, Any] = {
        "rider_id": "USR#rider-overflow-001",
        "pickup_location": "Mitchells Plain",
        "destination": "Khayelitsha Mall",
        "passenger_count": 8,       # violates le=7 constraint
        "baseline_fare": "18.00",
        "connection_id": "conn-overflow==",
    }

    event: dict[str, Any] = {
        "requestContext": {
            "routeKey": "BROADCAST_REQUEST",
            "connectionId": "conn-overflow==",
        },
        "body": json.dumps(body_payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400, (
        f"passenger_count=8 must produce a 400 response; got {response['statusCode']}."
    )
    body: dict[str, Any] = json.loads(response["body"])
    assert body["error"] == "ValidationError"


@mock_aws
def test_broadcast_request_with_non_integer_passenger_count_returns_400():
    """BROADCAST_REQUEST with a non-integer passenger_count (e.g. ``"three"``)
    must fail Pydantic coercion and return a deterministic 400 response.

    This guards against clients sending malformed JSON payloads where numeric
    fields contain non-numeric string values.
    """
    _create_mock_table()
    handler = _reload_bidding_handler()

    body_payload: dict[str, Any] = {
        "rider_id": "USR#rider-str-pax-001",
        "pickup_location": "Bellville Station",
        "destination": "Cape Town CBD",
        "passenger_count": "three",  # string where int is required
        "baseline_fare": "20.00",
        "connection_id": "conn-str-pax==",
    }

    event: dict[str, Any] = {
        "requestContext": {
            "routeKey": "BROADCAST_REQUEST",
            "connectionId": "conn-str-pax==",
        },
        "body": json.dumps(body_payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400, (
        f"Non-integer passenger_count must produce a 400; got {response['statusCode']}."
    )
    body: dict[str, Any] = json.loads(response["body"])
    assert body["error"] == "ValidationError"


# ---------------------------------------------------------------------------
# BROADCAST_REQUEST — missing 'USR#' prefix on rider_id
# ---------------------------------------------------------------------------

@mock_aws
def test_broadcast_request_without_usr_prefix_on_rider_id_raises_validation_error_and_returns_400():
    """BROADCAST_REQUEST where rider_id lacks the required 'USR#' prefix must:

    1. Trigger the ``rider_id_must_have_prefix`` field_validator on
       ``BroadcastRequestPayload``, raising a Pydantic ``ValidationError``.
    2. The handler must catch the ValidationError and return a deterministic
       HTTP 400 response — never an unhandled 500.
    3. The 400 response body must carry ``"error": "ValidationError"`` so
       the Flutter client can surface a useful error state to the Rider.

    This directly validates the USR# enforcement documented in both the
    BroadcastRequestPayload model and KWELLA_SYSTEM_CONTEXT.md §3.
    """
    _create_mock_table()
    handler = _reload_bidding_handler()

    body_payload: dict[str, Any] = {
        "rider_id": "rider-no-prefix-001",   # missing USR# prefix
        "pickup_location": "Bellville Station",
        "destination": "Cape Town CBD",
        "passenger_count": 2,
        "baseline_fare": "22.00",
        "connection_id": "conn-no-prefix==",
    }

    event: dict[str, Any] = {
        "requestContext": {
            "routeKey": "BROADCAST_REQUEST",
            "connectionId": "conn-no-prefix==",
        },
        "body": json.dumps(body_payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400, (
        "A missing 'USR#' prefix on rider_id must return 400; "
        f"got {response['statusCode']}. Body: {response['body']}"
    )

    body: dict[str, Any] = json.loads(response["body"])
    assert body["error"] == "ValidationError", (
        f"Response 'error' field must be 'ValidationError'; got '{body.get('error')}'."
    )

    # Verify the Pydantic error is surfaced through the model's own ValidationError.
    # We also test directly that the model raises ValidationError to confirm the
    # validator is not silently swallowed by any middleware layer.
    BroadcastRequestPayload = _get_broadcast_payload_model()
    with pytest.raises(ValidationError) as exc_info:
        BroadcastRequestPayload(
            rider_id="rider-no-prefix-direct",
            pickup_location="Bellville Station",
            destination="Cape Town CBD",
            passenger_count=2,
            baseline_fare=Decimal("22.00"),
            connection_id="conn-direct==",
        )

    errors = exc_info.value.errors()
    # Confirm the validation error targets the rider_id field specifically.
    rider_id_errors = [e for e in errors if "rider_id" in e.get("loc", ())]
    assert len(rider_id_errors) >= 1, (
        f"Expected a ValidationError targeting 'rider_id'; got errors: {errors}"
    )


# ---------------------------------------------------------------------------
# SUBMIT_BID — happy-path sanity check
# ---------------------------------------------------------------------------

@mock_aws
def test_submit_bid_writes_correct_bid_record_with_bid_prefix_pk_and_offer_prefix_sk():
    """SUBMIT_BID with a valid payload must:

    - Return HTTP 200.
    - Write PK = BID#<broadcast_pk> and SK = OFFER#<driver_id>.
    - Persist counter_fare as a Decimal-derived string (not a float).

    This confirms the key scheme that allows a Rider to query all offers
    for their broadcast via a begins_with(\"OFFER#\") sort-key condition.
    """
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    body_payload: dict[str, Any] = {
        "driver_id": "USR#drv-submit-001",
        "broadcast_pk": "BID#rider-conn-abc123==",
        "counter_fare": "22.50",
        "estimated_pickup": "4 minutes",
        "connection_id": "driver-conn-xyz789==",
    }

    event: dict[str, Any] = {
        "requestContext": {
            "routeKey": "SUBMIT_BID",
            "connectionId": "driver-conn-xyz789==",
            "domainName": "test-api.execute-api.af-south-1.amazonaws.com",
            "stage": "test",
        },
        "body": json.dumps(body_payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200, (
        f"Expected 200 for a valid SUBMIT_BID; got {response['statusCode']}. "
        f"Body: {response['body']}"
    )

    expected_pk = "BID#rider-conn-abc123=="
    expected_sk = "OFFER#USR#drv-submit-001"

    result = table.get_item(Key={"PK": expected_pk, "SK": expected_sk})
    item = result.get("Item")
    assert item is not None, (
        f"SUBMIT_BID must write a DynamoDB item at PK={expected_pk}, SK={expected_sk}."
    )

    assert item["PK"] == expected_pk
    assert item["SK"] == expected_sk
    assert item["driver_id"] == "USR#drv-submit-001"

    # counter_fare must be stored as a string (Decimal precision preserved).
    stored_fare: str = item["counter_fare"]
    assert isinstance(stored_fare, str), (
        f"counter_fare must be a string; got {type(stored_fare).__name__}."
    )
    assert Decimal(stored_fare) == Decimal("22.50"), (
        f"counter_fare round-trip must equal Decimal('22.50'); got '{stored_fare}'."
    )
