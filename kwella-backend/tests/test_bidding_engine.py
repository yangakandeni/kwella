"""
tests/test_bidding_engine.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Isolated unit tests for the kwella Bidding Engine Lambda handler.

Covers:
  - $connect: Writes connection tracking session row to DynamoDB (with and without auth token).
  - $disconnect: Deletes connection tracking session row from DynamoDB.
  - sendBid: Parses body, extracts bid particulars, and returns placeholder success block.
  - updateLocation: Persists driver telematics telemetry to DynamoDB and validates error paths.
  - Error conditions: malformed JSON, unsupported route key, and DynamoDB ClientError.
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any

import boto3
import os
import pytest
from botocore.exceptions import ClientError
from moto import mock_aws
from unittest.mock import Mock, patch


# ---------------------------------------------------------------------------
# Table provisioning helper
# ---------------------------------------------------------------------------

def _create_mock_table() -> Any:
    """Provision a moto-intercepted DynamoDB table matching the schema.

    Uses KWELLA_TABLE_NAME from the environment (defaulting to kwella-core-test).
    """
    dynamodb = boto3.resource("dynamodb", region_name="af-south-1")
    table_name = os.environ.get("KWELLA_TABLE_NAME", "kwella-core-test")
    table = dynamodb.create_table(
        TableName=table_name,
        KeySchema=[
            {"AttributeName": "PK", "KeyType": "HASH"},
            {"AttributeName": "SK", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "PK", "AttributeType": "S"},
            {"AttributeName": "SK", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )
    table.meta.client.get_waiter("table_exists").wait(TableName=table_name)
    return table


def _reload_bidding_handler():
    """Force-reimport the bidding_engine handler to bind to the active mock context."""
    for mod_name in ("bidding_engine.handler",):
        if mod_name in sys.modules:
            del sys.modules[mod_name]
    import bidding_engine.handler as handler  # noqa: PLC0415
    return handler


# ---------------------------------------------------------------------------
# Route: $connect Tests
# ---------------------------------------------------------------------------

@mock_aws
def test_connect_without_auth_token_writes_session_row():
    """Verify that $connect route successfully registers connection without token."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    event = {
        "requestContext": {
            "routeKey": "$connect",
            "connectionId": "conn-test-123",
        }
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    assert response["body"] == "Connected"

    # Verify the session is recorded in DynamoDB
    res = table.get_item(Key={"PK": "CONN#conn-test-123", "SK": "METADATA"})
    item = res.get("Item")
    assert item is not None
    assert item["PK"] == "CONN#conn-test-123"
    assert item["SK"] == "METADATA"
    assert "connected_at" in item
    assert "auth_token" not in item


@mock_aws
def test_connect_with_query_string_auth_token_writes_session_row():
    """Verify that $connect route extracts token from query string parameter."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    event = {
        "requestContext": {
            "routeKey": "$connect",
            "connectionId": "conn-test-456",
        },
        "queryStringParameters": {
            "token": "query-token-abc"
        }
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200

    res = table.get_item(Key={"PK": "CONN#conn-test-456", "SK": "METADATA"})
    item = res.get("Item")
    assert item is not None
    assert item["auth_token"] == "query-token-abc"


@mock_aws
def test_connect_with_header_auth_token_writes_session_row():
    """Verify that $connect route extracts token from Authorization header."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    event = {
        "requestContext": {
            "routeKey": "$connect",
            "connectionId": "conn-test-789",
        },
        "headers": {
            "Authorization": "Bearer header-token-xyz"
        }
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200

    res = table.get_item(Key={"PK": "CONN#conn-test-789", "SK": "METADATA"})
    item = res.get("Item")
    assert item is not None
    assert item["auth_token"] == "Bearer header-token-xyz"


# ---------------------------------------------------------------------------
# Route: $disconnect Tests
# ---------------------------------------------------------------------------

@mock_aws
def test_disconnect_deletes_session_row():
    """Verify that $disconnect route cleans up connection session row."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    # Pre-populate connection metadata
    table.put_item(
        Item={
            "PK": "CONN#conn-to-disconnect",
            "SK": "METADATA",
            "connected_at": "2026-06-21T01:00:00Z"
        }
    )

    # Assert connection exists initially
    assert "Item" in table.get_item(Key={"PK": "CONN#conn-to-disconnect", "SK": "METADATA"})

    event = {
        "requestContext": {
            "routeKey": "$disconnect",
            "connectionId": "conn-to-disconnect",
        }
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    assert response["body"] == "Disconnected"

    # Verify session is deleted
    res = table.get_item(Key={"PK": "CONN#conn-to-disconnect", "SK": "METADATA"})
    assert "Item" not in res


# ---------------------------------------------------------------------------
# Route: sendBid Tests
# ---------------------------------------------------------------------------

@mock_aws
def test_send_bid_parses_and_returns_placeholder_success():
    """Verify sendBid parses payload and returns a placeholder success block."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    body_payload = {
        "driver_id": "USR#drv-1",
        "rider_id": "USR#rider-1",
        "counter_fare": "55.00",
        "estimated_pickup": "7 minutes",
        "broadcast_pk": "BID#broadcast-1"
    }

    event = {
        "requestContext": {
            "routeKey": "sendBid",
            "connectionId": "conn-driver-1",
        },
        "body": json.dumps(body_payload)
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "Success"
    
    particulars = body["bid_particulars"]
    assert particulars["driver_id"] == "USR#drv-1"
    assert particulars["rider_id"] == "USR#rider-1"
    assert particulars["amount"] == "55.00"
    assert particulars["estimated_pickup"] == "7 minutes"
    assert particulars["broadcast_pk"] == "BID#broadcast-1"
    assert particulars["connection_id"] == "conn-driver-1"


@mock_aws
def test_send_bid_with_malformed_json_returns_400():
    """Verify sendBid route fails gracefully on invalid JSON body."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    event = {
        "requestContext": {
            "routeKey": "sendBid",
            "connectionId": "conn-driver-1",
        },
        "body": "invalid-json-content-string"
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "JSON" in body["detail"]


# ---------------------------------------------------------------------------
# Error and Invalid Request Paths
# ---------------------------------------------------------------------------

@mock_aws
def test_missing_context_parameters_returns_400():
    """Verify that requests missing routeKey or connectionId return 400."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    event = {
        "requestContext": {
            "connectionId": "conn-id-without-route"
        }
    }

    response = handler.lambda_handler(event, context=None)
    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"


@mock_aws
def test_unsupported_route_key_returns_400():
    """Verify that unsupported route keys return 400."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    event = {
        "requestContext": {
            "routeKey": "invalidAction",
            "connectionId": "conn-123"
        }
    }

    response = handler.lambda_handler(event, context=None)
    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"


@mock_aws
def test_database_client_error_returns_500(monkeypatch):
    """Verify that a DynamoDB client error triggers a clean 500 response."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    # Mock put_item to raise a ClientError
    def mock_put_item(*args, **kwargs):
        raise ClientError(
            {"Error": {"Code": "ProvisionedThroughputExceededException", "Message": "Throughput exceeded"}},
            "PutItem"
        )

    # Locate the table reference in the handler to mock it
    table = handler.get_table()
    monkeypatch.setattr(table, "put_item", mock_put_item)

    event = {
        "requestContext": {
            "routeKey": "$connect",
            "connectionId": "conn-test-error",
        }
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 500
    body = json.loads(response["body"])
    assert body["error"] == "InfrastructureError"
    assert "ProvisionedThroughputExceededException" in body["detail"]


# ---------------------------------------------------------------------------
# Route: updateLocation Tests
# ---------------------------------------------------------------------------

_LOCATION_EVENT_BASE = {
    "requestContext": {
        "routeKey": "updateLocation",
        "connectionId": "conn-driver-telemetry",
    },
}

_VALID_TELEMETRY_PAYLOAD = {
    "action": "updateLocation",
    "driverId": "USR#drv-12345",
    "latitude": -33.9249,
    "longitude": 18.4241,
    "heading": 180.0,
    "speed": 11.5,
}


@mock_aws
def test_update_location_persists_telemetry_to_dynamodb():
    """Verify updateLocation route writes all telematics fields to DRIVER#<id>/TELEMETRY."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    event = {
        **_LOCATION_EVENT_BASE,
        "body": json.dumps(_VALID_TELEMETRY_PAYLOAD),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "Telemetry Latched"

    # Verify DynamoDB record was written under the canonical key scheme
    res = table.get_item(Key={"PK": "DRIVER#USR#drv-12345", "SK": "TELEMETRY"})
    item = res.get("Item")
    assert item is not None, "TELEMETRY row must exist after updateLocation"
    assert item["PK"] == "DRIVER#USR#drv-12345"
    assert item["SK"] == "TELEMETRY"
    assert float(item["last_latitude"]) == pytest.approx(-33.9249)
    assert float(item["last_longitude"]) == pytest.approx(18.4241)
    assert float(item["heading"]) == pytest.approx(180.0)
    assert float(item["speed"]) == pytest.approx(11.5)
    assert "updated_at" in item


@mock_aws
def test_update_location_flat_event_payload():
    """Verify updateLocation handles flat event invocation (no body wrapper)."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    # Flat event: telematics fields embedded directly at root level (no body key)
    event = {
        "requestContext": {
            "routeKey": "updateLocation",
            "connectionId": "conn-flat-event",
        },
        **_VALID_TELEMETRY_PAYLOAD,
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "Telemetry Latched"

    res = table.get_item(Key={"PK": "DRIVER#USR#drv-12345", "SK": "TELEMETRY"})
    assert res.get("Item") is not None


@mock_aws
def test_update_location_overwrites_stale_telemetry():
    """Verify successive updateLocation calls overwrite the TELEMETRY record in place."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    first_payload = {**_VALID_TELEMETRY_PAYLOAD, "latitude": -33.9100, "longitude": 18.4000}
    second_payload = {**_VALID_TELEMETRY_PAYLOAD, "latitude": -33.9249, "longitude": 18.4241}

    handler.lambda_handler(
        {**_LOCATION_EVENT_BASE, "body": json.dumps(first_payload)},
        context=None,
    )
    handler.lambda_handler(
        {**_LOCATION_EVENT_BASE, "body": json.dumps(second_payload)},
        context=None,
    )

    res = table.get_item(Key={"PK": "DRIVER#USR#drv-12345", "SK": "TELEMETRY"})
    item = res["Item"]
    # Only the second write's coordinates should be stored
    assert float(item["last_latitude"]) == pytest.approx(-33.9249)
    assert float(item["last_longitude"]) == pytest.approx(18.4241)


@mock_aws
def test_update_location_without_optional_heading_and_speed():
    """Verify updateLocation succeeds when optional heading and speed are omitted."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    payload = {
        "action": "updateLocation",
        "driverId": "USR#drv-no-heading",
        "latitude": -26.2041,
        "longitude": 28.0473,
    }

    event = {**_LOCATION_EVENT_BASE, "body": json.dumps(payload)}
    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    res = table.get_item(Key={"PK": "DRIVER#USR#drv-no-heading", "SK": "TELEMETRY"})
    item = res.get("Item")
    assert item is not None
    assert float(item["last_latitude"]) == pytest.approx(-26.2041)
    assert float(item["last_longitude"]) == pytest.approx(28.0473)
    # Optional fields must not be present when not supplied
    assert "heading" not in item
    assert "speed" not in item


@mock_aws
def test_update_location_missing_driver_id_returns_400():
    """Verify updateLocation returns 400 when driverId is absent."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    payload = {
        "action": "updateLocation",
        "latitude": -33.9249,
        "longitude": 18.4241,
    }

    event = {**_LOCATION_EVENT_BASE, "body": json.dumps(payload)}
    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "driverId" in body["detail"]


@mock_aws
def test_update_location_missing_latitude_returns_400():
    """Verify updateLocation returns 400 when latitude is absent."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    payload = {
        "action": "updateLocation",
        "driverId": "USR#drv-12345",
        "longitude": 18.4241,
    }

    event = {**_LOCATION_EVENT_BASE, "body": json.dumps(payload)}
    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "latitude" in body["detail"]


@mock_aws
def test_update_location_missing_longitude_returns_400():
    """Verify updateLocation returns 400 when longitude is absent."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    payload = {
        "action": "updateLocation",
        "driverId": "USR#drv-12345",
        "latitude": -33.9249,
    }

    event = {**_LOCATION_EVENT_BASE, "body": json.dumps(payload)}
    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "longitude" in body["detail"]


@mock_aws
def test_update_location_malformed_json_body_returns_400():
    """Verify updateLocation fails gracefully when body is not valid JSON."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    event = {**_LOCATION_EVENT_BASE, "body": "not-valid-json{{{"}
    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "JSON" in body["detail"]


@mock_aws
def test_update_location_non_numeric_latitude_returns_400():
    """Verify updateLocation returns 400 when latitude is a string instead of a float."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    payload = {
        "action": "updateLocation",
        "driverId": "USR#drv-12345",
        "latitude": "not-a-number",
        "longitude": 18.4241,
    }

    event = {**_LOCATION_EVENT_BASE, "body": json.dumps(payload)}
    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "latitude" in body["detail"]


@mock_aws
def test_update_location_non_numeric_longitude_returns_400():
    """Verify updateLocation returns 400 when longitude is a string instead of a float."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    payload = {
        "action": "updateLocation",
        "driverId": "USR#drv-12345",
        "latitude": -33.9249,
        "longitude": "cape-town",
    }

    event = {**_LOCATION_EVENT_BASE, "body": json.dumps(payload)}
    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "longitude" in body["detail"]


@mock_aws
def test_update_location_non_numeric_heading_returns_400():
    """Verify updateLocation returns 400 when heading is a non-numeric string."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    payload = {
        **_VALID_TELEMETRY_PAYLOAD,
        "heading": "north",
    }

    event = {**_LOCATION_EVENT_BASE, "body": json.dumps(payload)}
    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "heading" in body["detail"]


@mock_aws
def test_update_location_non_numeric_speed_returns_400():
    """Verify updateLocation returns 400 when speed is a non-numeric string."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    payload = {
        **_VALID_TELEMETRY_PAYLOAD,
        "speed": "fast",
    }

    event = {**_LOCATION_EVENT_BASE, "body": json.dumps(payload)}
    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "speed" in body["detail"]


@mock_aws
def test_update_location_dynamodb_client_error_returns_500(monkeypatch):
    """Verify a DynamoDB ClientError during telematics write returns a clean 500."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    def mock_update_item(*args, **kwargs):
        raise ClientError(
            {"Error": {"Code": "ServiceUnavailable", "Message": "Service is unavailable"}},
            "UpdateItem",
        )

    table = handler.get_table()
    monkeypatch.setattr(table, "update_item", mock_update_item)

    event = {**_LOCATION_EVENT_BASE, "body": json.dumps(_VALID_TELEMETRY_PAYLOAD)}
    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 500
    body = json.loads(response["body"])
    assert body["error"] == "InfrastructureError"
    assert "ServiceUnavailable" in body["detail"]


# ---------------------------------------------------------------------------
# Geofencing Integration Tests
# ---------------------------------------------------------------------------

@mock_aws
def test_update_location_geofence_arrived_with_trip_lookup():
    """Verify updateLocation detects ARRIVED status when near the destination of the loaded trip."""
    from decimal import Decimal
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    # Pre-populate a trip with destination coordinates
    table.put_item(
        Item={
            "PK": "TRIP#trip-arrived-123",
            "SK": "METADATA",
            "destination_latitude": Decimal("-33.9165"),
            "destination_longitude": Decimal("18.4274"),
        }
    )

    payload = {
        "action": "updateLocation",
        "driverId": "USR#drv-12345",
        "latitude": -33.9165,
        "longitude": 18.4274,
        "tripId": "trip-arrived-123",
    }

    event = {
        **_LOCATION_EVENT_BASE,
        "body": json.dumps(payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "Telemetry Latched"
    assert "flags" in body
    assert body["flags"]["geofence_status"] == "ARRIVED"


@mock_aws
def test_update_location_geofence_not_arrived_with_trip_lookup():
    """Verify updateLocation does not include ARRIVED status when far from the destination of the loaded trip."""
    from decimal import Decimal
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    table.put_item(
        Item={
            "PK": "TRIP#trip-not-arrived-123",
            "SK": "METADATA",
            "destination_latitude": Decimal("-33.9165"),
            "destination_longitude": Decimal("18.4274"),
        }
    )

    payload = {
        "action": "updateLocation",
        "driverId": "USR#drv-12345",
        "latitude": -33.9036,
        "longitude": 18.3989,  # ~2.8 km away
        "tripId": "trip-not-arrived-123",
    }

    event = {
        **_LOCATION_EVENT_BASE,
        "body": json.dumps(payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "Telemetry Latched"
    assert "flags" not in body


@mock_aws
def test_update_location_geofence_fallback_arrived():
    """Verify updateLocation detects ARRIVED status using fallback coordinates (Green Point) when tripId is missing."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    # Fallback default coordinates: -33.9036, 18.3989
    payload = {
        "action": "updateLocation",
        "driverId": "USR#drv-12345",
        "latitude": -33.9036,
        "longitude": 18.3989,
    }

    event = {
        **_LOCATION_EVENT_BASE,
        "body": json.dumps(payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "Telemetry Latched"
    assert "flags" in body
    assert body["flags"]["geofence_status"] == "ARRIVED"


@mock_aws
def test_update_location_geofence_fallback_not_arrived():
    """Verify updateLocation does not include ARRIVED status when far from the fallback coordinates."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    # Fallback default coordinates: -33.9036, 18.3989 (Foreshore: -33.9165, 18.4274 is ~2.8 km away)
    payload = {
        "action": "updateLocation",
        "driverId": "USR#drv-12345",
        "latitude": -33.9165,
        "longitude": 18.4274,
    }

    event = {
        **_LOCATION_EVENT_BASE,
        "body": json.dumps(payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "Telemetry Latched"
    assert "flags" not in body


# ---------------------------------------------------------------------------
# Route: requestTrip Tests  (Phase 14 — Marketplace Matching Engine)
# ---------------------------------------------------------------------------

#: Rider pickup location: Cape Town CBD, South Africa
_RIDER_PICKUP_LAT: float = -33.9249
_RIDER_PICKUP_LON: float = 18.4241

#: Driver A — ~2,000 m from pickup (De Waal Park area).  Must be INCLUDED.
#  Approx displacement: ~0.018° lat north ≈ 2,000 m
_DRIVER_NEAR_ID = "USR#drv-near-2000m"
_DRIVER_NEAR_LAT: float = -33.9069   # ~2,000 m north of pickup
_DRIVER_NEAR_LON: float = 18.4241

#: Driver B — ~7,000 m from pickup (Camps Bay direction).  Must be EXCLUDED.
#  Approx displacement: ~0.063° lat north ≈ 7,000 m
_DRIVER_FAR_ID = "USR#drv-far-7000m"
_DRIVER_FAR_LAT: float = -33.8620   # ~7,000 m north of pickup
_DRIVER_FAR_LON: float = 18.4241

_REQUEST_TRIP_EVENT_BASE: dict[str, Any] = {
    "requestContext": {
        "routeKey": "requestTrip",
        "connectionId": "conn-rider-trip-req",
    },
}

_REQUEST_TRIP_PAYLOAD: dict[str, Any] = {
    "action": "requestTrip",
    "riderId": "USR#rdr-99887",
    "pickup_latitude": _RIDER_PICKUP_LAT,
    "pickup_longitude": _RIDER_PICKUP_LON,
    "dropoff_latitude": -33.9712,
    "dropoff_longitude": 18.4649,
    "suggested_base_fare": 120.0,
}


@mock_aws
def test_request_trip_includes_near_driver_and_excludes_far_driver():
    """Verify requestTrip spatial filter includes 2 km driver and excludes 7 km driver.

    Seeds two TELEMETRY records:
      - DRIVER_NEAR  (~2,000 m) — within the 5,000 m radius — must be matched.
      - DRIVER_FAR   (~7,000 m) — outside the 5,000 m radius — must be excluded.

    Asserts that only DRIVER_NEAR appears in the matched_drivers list.
    """
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    # Seed the near driver telemetry record.
    table.put_item(
        Item={
            "PK": f"DRIVER#{_DRIVER_NEAR_ID}",
            "SK": "TELEMETRY",
            "last_latitude": str(_DRIVER_NEAR_LAT),
            "last_longitude": str(_DRIVER_NEAR_LON),
            "updated_at": "2026-06-21T06:00:00Z",
        }
    )

    # Seed the far driver telemetry record.
    table.put_item(
        Item={
            "PK": f"DRIVER#{_DRIVER_FAR_ID}",
            "SK": "TELEMETRY",
            "last_latitude": str(_DRIVER_FAR_LAT),
            "last_longitude": str(_DRIVER_FAR_LON),
            "updated_at": "2026-06-21T06:00:00Z",
        }
    )

    event = {
        **_REQUEST_TRIP_EVENT_BASE,
        "body": json.dumps(_REQUEST_TRIP_PAYLOAD),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])

    assert body["status"] == "TripBroadcast"
    assert "tripId" in body
    assert body["tripId"].startswith("TRP#")

    matched = body["matched_drivers"]
    assert isinstance(matched, list)

    # The near driver (2,000 m) must be in the matched set.
    assert _DRIVER_NEAR_ID in matched, (
        f"Expected near driver {_DRIVER_NEAR_ID!r} to be matched but got: {matched}"
    )

    # The far driver (7,000 m) must be excluded.
    assert _DRIVER_FAR_ID not in matched, (
        f"Far driver {_DRIVER_FAR_ID!r} should not be matched but appeared in: {matched}"
    )


@mock_aws
def test_request_trip_offline_driver_triggers_sns_fallback_push():
    """Verify stale WebSocket dispatch triggers SNS fallback push with the correct payload."""
    table = _create_mock_table()

    env_backup = {
        "KWELLA_SNS_PLATFORM_APPLICATION_ARN": os.environ.get("KWELLA_SNS_PLATFORM_APPLICATION_ARN"),
        "KWELLA_APIGW_ENDPOINT": os.environ.get("KWELLA_APIGW_ENDPOINT"),
    }
    os.environ["KWELLA_SNS_PLATFORM_APPLICATION_ARN"] = "arn:aws:sns:af-south-1:123456789012:app/GCM/kwella"
    os.environ["KWELLA_APIGW_ENDPOINT"] = "https://example.execute-api.af-south-1.amazonaws.com/prod"

    try:
        handler = _reload_bidding_handler()

        table.put_item(
            Item={
                "PK": f"DRIVER#{_DRIVER_NEAR_ID}",
                "SK": "TELEMETRY",
                "last_latitude": str(_DRIVER_NEAR_LAT),
                "last_longitude": str(_DRIVER_NEAR_LON),
                "connection_id": "conn-driver-stale",
                "updated_at": "2026-06-21T06:00:00Z",
            }
        )

        table.put_item(
            Item={
                "PK": f"DRIVER#{_DRIVER_NEAR_ID}",
                "SK": "PROFILE",
                "fcm_token": "fcm-token-abc123",
            }
        )

        apigw_mock = Mock()
        sns_mock = Mock()

        error_response = {"Error": {"Code": "GoneException", "Message": "Stale connection"}}
        apigw_mock.post_to_connection.side_effect = ClientError(error_response, "PostToConnection")
        sns_mock.create_platform_endpoint.return_value = {"EndpointArn": "arn:aws:sns:af-south-1:123456789012:endpoint/GCM/kwella/fcm-token-abc123"}
        sns_mock.publish.return_value = {"MessageId": "msg-123"}

        def client_factory(service_name, region_name=None, endpoint_url=None, **kwargs):
            if service_name == "apigatewaymanagementapi":
                return apigw_mock
            if service_name == "sns":
                return sns_mock
            raise RuntimeError(f"Unexpected boto3 client request: {service_name}")

        with patch.object(handler, "boto3") as boto3_mock:
            boto3_mock.client.side_effect = client_factory
            boto3_mock.resource = boto3.resource

            event = {
                **_REQUEST_TRIP_EVENT_BASE,
                "body": json.dumps(_REQUEST_TRIP_PAYLOAD),
            }

            response = handler.lambda_handler(event, context=None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["status"] == "TripBroadcast"
        assert _DRIVER_NEAR_ID in body["matched_drivers"]

        sns_mock.create_platform_endpoint.assert_called_once_with(
            PlatformApplicationArn="arn:aws:sns:af-south-1:123456789012:app/GCM/kwella",
            Token="fcm-token-abc123",
        )

        assert sns_mock.publish.call_count == 1
        publish_kwargs = sns_mock.publish.call_args.kwargs
        assert publish_kwargs["TargetArn"] == "arn:aws:sns:af-south-1:123456789012:endpoint/GCM/kwella/fcm-token-abc123"
        assert publish_kwargs["MessageStructure"] == "json"

        message = json.loads(publish_kwargs["Message"])
        assert "GCM" in message

        gcm_message = json.loads(message["GCM"])
        assert gcm_message["priority"] == "high"
        assert gcm_message["data"]["action"] == "rideOfferAvailable"
        assert gcm_message["data"]["tripId"] == body["tripId"]
        assert gcm_message["data"]["base_fare"] == str(_REQUEST_TRIP_PAYLOAD["suggested_base_fare"])
        assert gcm_message["data"]["click_action"] == "FLUTTER_NOTIFICATION_CLICK"
    finally:
        for key, value in env_backup.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


@mock_aws
def test_request_trip_missing_required_fields_returns_400():
    """Verify requestTrip returns 400 ValidationError when pickup coordinates are absent."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    # Omit pickup_longitude to trigger validation error.
    incomplete_payload = {
        "action": "requestTrip",
        "riderId": "USR#rdr-99887",
        "pickup_latitude": _RIDER_PICKUP_LAT,
        # pickup_longitude intentionally missing
        "dropoff_latitude": -33.9712,
        "dropoff_longitude": 18.4649,
        "suggested_base_fare": 120.0,
    }

    event = {
        **_REQUEST_TRIP_EVENT_BASE,
        "body": json.dumps(incomplete_payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "pickup_longitude" in body["detail"]


@mock_aws
def test_request_trip_with_no_active_drivers_returns_empty_matched_list():
    """Verify requestTrip returns a clean 200 with an empty matched_drivers list when no TELEMETRY records exist."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    # No TELEMETRY records are seeded — the scan should return zero results.
    event = {
        **_REQUEST_TRIP_EVENT_BASE,
        "body": json.dumps(_REQUEST_TRIP_PAYLOAD),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "TripBroadcast"
    assert body["matched_drivers"] == []


# ---------------------------------------------------------------------------
# Route: confirmArrival Tests (Phase 15 — Secure Payout Settlement)
# ---------------------------------------------------------------------------

_CONFIRM_ARRIVAL_EVENT_BASE = {
    "requestContext": {
        "routeKey": "confirmArrival",
        "connectionId": "conn-driver-confirm-arrival",
    },
}


@mock_aws
def test_confirm_arrival_settles_in_progress_trip_successfully():
    """Verify confirmArrival calculates net payout, executes transact_write_items, updates trip to COMPLETED, and updates driver wallet."""
    from decimal import Decimal
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    # Pre-populate trip record in IN_PROGRESS state
    table.put_item(
        Item={
            "PK": "TRIP#trip-accepted-123",
            "SK": "METADATA",
            "status": "IN_PROGRESS",
        }
    )

    payload = {
        "action": "confirmArrival",
        "driverId": "USR#drv-12345",
        "tripId": "trip-accepted-123",
        "final_bid_amount": 150.0,
    }

    event = {
        **_CONFIRM_ARRIVAL_EVENT_BASE,
        "body": json.dumps(payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "WalletSettled"
    assert body["tripId"] == "trip-accepted-123"
    assert body["net_earnings"] == pytest.approx(127.50)
    assert body["currency"] == "ZAR"
    assert body["updated_daily_total"] == pytest.approx(127.50)

    # Verify database updates
    trip_res = table.get_item(Key={"PK": "TRIP#trip-accepted-123", "SK": "METADATA"})
    assert trip_res["Item"]["status"] == "COMPLETED"

    wallet_res = table.get_item(Key={"PK": "DRIVER#USR#drv-12345", "SK": "WALLET"})
    wallet_item = wallet_res["Item"]
    assert wallet_item["balance"] == Decimal("127.50")
    assert wallet_item["daily_total"] == Decimal("127.50")


@mock_aws
def test_confirm_arrival_increments_existing_wallet_balance():
    """Verify confirmArrival increments pre-existing wallet balances for an in-progress trip."""
    from decimal import Decimal
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    # Pre-populate trip record in IN_PROGRESS state
    table.put_item(
        Item={
            "PK": "TRIP#trip-arrived-456",
            "SK": "METADATA",
            "status": "IN_PROGRESS",
        }
    )

    # Pre-populate driver wallet
    table.put_item(
        Item={
            "PK": "DRIVER#USR#drv-12345",
            "SK": "WALLET",
            "balance": Decimal("1000.00"),
            "daily_total": Decimal("1000.00"),
        }
    )

    payload = {
        "action": "confirmArrival",
        "driverId": "USR#drv-12345",
        "tripId": "trip-arrived-456",
        "final_bid_amount": 200.0,  # 85% of 200 is 170
    }

    event = {
        **_CONFIRM_ARRIVAL_EVENT_BASE,
        "body": json.dumps(payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "WalletSettled"
    assert body["tripId"] == "trip-arrived-456"
    assert body["net_earnings"] == pytest.approx(170.00)
    assert body["updated_daily_total"] == pytest.approx(1170.00)

    # Verify database updates
    trip_res = table.get_item(Key={"PK": "TRIP#trip-arrived-456", "SK": "METADATA"})
    assert trip_res["Item"]["status"] == "COMPLETED"

    wallet_res = table.get_item(Key={"PK": "DRIVER#USR#drv-12345", "SK": "WALLET"})
    wallet_item = wallet_res["Item"]
    assert wallet_item["balance"] == Decimal("1170.00")
    assert wallet_item["daily_total"] == Decimal("1170.00")


@mock_aws
def test_confirm_arrival_fails_on_already_completed_trip():
    """Verify that trying to settle an already 'COMPLETED' trip fails with a clean transactional conditional check error."""
    from decimal import Decimal
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    # Pre-populate trip in COMPLETED state
    table.put_item(
        Item={
            "PK": "TRIP#trip-completed-789",
            "SK": "METADATA",
            "status": "COMPLETED",
        }
    )

    # Pre-populate driver wallet
    table.put_item(
        Item={
            "PK": "DRIVER#USR#drv-12345",
            "SK": "WALLET",
            "balance": Decimal("500.00"),
            "daily_total": Decimal("500.00"),
        }
    )

    payload = {
        "action": "confirmArrival",
        "driverId": "USR#drv-12345",
        "tripId": "trip-completed-789",
        "final_bid_amount": 150.0,
    }

    event = {
        **_CONFIRM_ARRIVAL_EVENT_BASE,
        "body": json.dumps(payload),
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "status must be IN_PROGRESS" in body["detail"]

    # Verify database remains unmodified
    trip_res = table.get_item(Key={"PK": "TRIP#trip-completed-789", "SK": "METADATA"})
    assert trip_res["Item"]["status"] == "COMPLETED"

    wallet_res = table.get_item(Key={"PK": "DRIVER#USR#drv-12345", "SK": "WALLET"})
    wallet_item = wallet_res["Item"]
    assert wallet_item["balance"] == Decimal("500.00")
    assert wallet_item["daily_total"] == Decimal("500.00")


@mock_aws
def test_confirm_arrival_validation_failures():
    """Verify confirmArrival validates required inputs and their data types."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    # Case 1: Missing driverId
    payload = {
        "action": "confirmArrival",
        "tripId": "trip-123",
        "final_bid_amount": 150.0,
    }
    response = handler.lambda_handler({**_CONFIRM_ARRIVAL_EVENT_BASE, "body": json.dumps(payload)}, context=None)
    assert response["statusCode"] == 400
    assert "driverId" in json.loads(response["body"])["detail"]

    # Case 2: Missing tripId
    payload = {
        "action": "confirmArrival",
        "driverId": "USR#drv-123",
        "final_bid_amount": 150.0,
    }
    response = handler.lambda_handler({**_CONFIRM_ARRIVAL_EVENT_BASE, "body": json.dumps(payload)}, context=None)
    assert response["statusCode"] == 400
    assert "tripId" in json.loads(response["body"])["detail"]

    # Case 3: Missing final_bid_amount
    payload = {
        "action": "confirmArrival",
        "driverId": "USR#drv-123",
        "tripId": "trip-123",
    }
    response = handler.lambda_handler({**_CONFIRM_ARRIVAL_EVENT_BASE, "body": json.dumps(payload)}, context=None)
    assert response["statusCode"] == 400
    assert "final_bid_amount" in json.loads(response["body"])["detail"]

    # Case 4: Non-numeric final_bid_amount
    payload = {
        "action": "confirmArrival",
        "driverId": "USR#drv-123",
        "tripId": "trip-123",
        "final_bid_amount": "one-hundred-fifty",
    }
    response = handler.lambda_handler({**_CONFIRM_ARRIVAL_EVENT_BASE, "body": json.dumps(payload)}, context=None)
    assert response["statusCode"] == 400
    assert "final_bid_amount" in json.loads(response["body"])["detail"]


# ---------------------------------------------------------------------------
# Route: selectBid Tests
# ---------------------------------------------------------------------------

_SELECT_BID_EVENT_BASE = {
    "requestContext": {
        "routeKey": "selectBid",
        "connectionId": "conn-rider-select-bid",
    },
}


@mock_aws
def test_select_bid_transitions_trip_to_accepted_and_notifies_driver():
    """Verify selectBid updates trip status to ACCEPTED and records the selected driver."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    table.put_item(
        Item={
            "PK": "TRIP#trip-select-1",
            "SK": "METADATA",
            "status": "REQUESTED",
            "rider_id": "USR#rdr-1",
        }
    )
    table.put_item(
        Item={
            "PK": "BID#trip-select-1",
            "SK": "DRIVER#USR#drv-1",
            "driver_connection_id": "conn-driver-winner",
        }
    )

    payload = {
        "action": "selectBid",
        "tripId": "trip-select-1",
        "driverId": "USR#drv-1",
    }

    response = handler.lambda_handler(
        {**_SELECT_BID_EVENT_BASE, "body": json.dumps(payload)}, context=None
    )

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "BidSelected"
    assert body["tripId"] == "trip-select-1"
    assert body["driverId"] == "USR#drv-1"
    assert body["riderId"] == "USR#rdr-1"

    trip_res = table.get_item(Key={"PK": "TRIP#trip-select-1", "SK": "METADATA"})
    trip_item = trip_res["Item"]
    assert trip_item["status"] == "ACCEPTED"
    assert trip_item["selected_driver_id"] == "USR#drv-1"


@mock_aws
def test_select_bid_missing_trip_returns_400():
    """Verify selectBid returns 400 ValidationError when the trip does not exist."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    payload = {
        "action": "selectBid",
        "tripId": "trip-does-not-exist",
        "driverId": "USR#drv-1",
    }

    response = handler.lambda_handler(
        {**_SELECT_BID_EVENT_BASE, "body": json.dumps(payload)}, context=None
    )

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "does not exist" in body["detail"]


@mock_aws
def test_select_bid_missing_driver_id_returns_400():
    """Verify selectBid returns 400 ValidationError when driverId is absent."""
    _create_mock_table()
    handler = _reload_bidding_handler()

    payload = {
        "action": "selectBid",
        "tripId": "trip-select-2",
    }

    response = handler.lambda_handler(
        {**_SELECT_BID_EVENT_BASE, "body": json.dumps(payload)}, context=None
    )

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "driverId" in body["detail"]


# ---------------------------------------------------------------------------
# Route: driverArrived Tests
# ---------------------------------------------------------------------------

_DRIVER_ARRIVED_EVENT_BASE = {
    "requestContext": {
        "routeKey": "driverArrived",
        "connectionId": "conn-driver-arrived",
    },
}


@mock_aws
def test_driver_arrived_transitions_accepted_to_arrived_and_notifies_rider():
    """Verify driverArrived transitions an ACCEPTED trip to ARRIVED and pushes driverArrived to the rider."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    table.put_item(
        Item={
            "PK": "TRIP#trip-arrived-1",
            "SK": "METADATA",
            "status": "ACCEPTED",
            "rider_connection_id": "conn-rider-1",
        }
    )

    payload = {
        "action": "driverArrived",
        "tripId": "trip-arrived-1",
    }

    response = handler.lambda_handler(
        {**_DRIVER_ARRIVED_EVENT_BASE, "body": json.dumps(payload)}, context=None
    )

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "DriverArrived"
    assert body["tripId"] == "trip-arrived-1"

    trip_res = table.get_item(Key={"PK": "TRIP#trip-arrived-1", "SK": "METADATA"})
    assert trip_res["Item"]["status"] == "ARRIVED"


@mock_aws
def test_driver_arrived_rejects_when_not_accepted():
    """Verify driverArrived returns 400 ValidationError when the trip is not in ACCEPTED state."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    table.put_item(
        Item={
            "PK": "TRIP#trip-arrived-2",
            "SK": "METADATA",
            "status": "REQUESTED",
        }
    )

    payload = {
        "action": "driverArrived",
        "tripId": "trip-arrived-2",
    }

    response = handler.lambda_handler(
        {**_DRIVER_ARRIVED_EVENT_BASE, "body": json.dumps(payload)}, context=None
    )

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "ACCEPTED" in body["detail"]

    trip_res = table.get_item(Key={"PK": "TRIP#trip-arrived-2", "SK": "METADATA"})
    assert trip_res["Item"]["status"] == "REQUESTED"


# ---------------------------------------------------------------------------
# Route: startTrip Tests
# ---------------------------------------------------------------------------

_START_TRIP_EVENT_BASE = {
    "requestContext": {
        "routeKey": "startTrip",
        "connectionId": "conn-driver-start-trip",
    },
}


@mock_aws
def test_start_trip_transitions_arrived_to_in_progress_and_notifies_rider():
    """Verify startTrip transitions an ARRIVED trip to IN_PROGRESS and pushes tripStarted to the rider."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    table.put_item(
        Item={
            "PK": "TRIP#trip-start-1",
            "SK": "METADATA",
            "status": "ARRIVED",
            "rider_connection_id": "conn-rider-1",
        }
    )

    payload = {
        "action": "startTrip",
        "tripId": "trip-start-1",
        "driverId": "USR#drv-1",
    }

    response = handler.lambda_handler(
        {**_START_TRIP_EVENT_BASE, "body": json.dumps(payload)}, context=None
    )

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "TripStarted"
    assert body["tripId"] == "trip-start-1"

    trip_res = table.get_item(Key={"PK": "TRIP#trip-start-1", "SK": "METADATA"})
    assert trip_res["Item"]["status"] == "IN_PROGRESS"


@mock_aws
def test_start_trip_rejects_when_not_arrived():
    """Verify startTrip returns 400 ValidationError when the trip is not in ARRIVED state."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    table.put_item(
        Item={
            "PK": "TRIP#trip-start-2",
            "SK": "METADATA",
            "status": "ACCEPTED",
        }
    )

    payload = {
        "action": "startTrip",
        "tripId": "trip-start-2",
        "driverId": "USR#drv-1",
    }

    response = handler.lambda_handler(
        {**_START_TRIP_EVENT_BASE, "body": json.dumps(payload)}, context=None
    )

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "ARRIVED" in body["detail"]

    trip_res = table.get_item(Key={"PK": "TRIP#trip-start-2", "SK": "METADATA"})
    assert trip_res["Item"]["status"] == "ACCEPTED"


# ---------------------------------------------------------------------------
# Route: submitRating Tests
# ---------------------------------------------------------------------------

_SUBMIT_RATING_EVENT_BASE = {
    "requestContext": {
        "routeKey": "submitRating",
        "connectionId": "conn-driver-submit-rating",
    },
}


@mock_aws
def test_submit_rating_persists_against_driver_profile():
    """Verify submitRating stores the rating against the trip's selected driver profile."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    table.put_item(
        Item={
            "PK": "TRIP#trip-rating-1",
            "SK": "METADATA",
            "rider_id": "USR#rdr-1",
            "selected_driver_id": "USR#drv-1",
        }
    )

    payload = {
        "action": "submitRating",
        "riderId": "USR#rdr-1",
        "tripId": "trip-rating-1",
        "rating": 5,
        "target": "DRIVER",
    }

    response = handler.lambda_handler(
        {**_SUBMIT_RATING_EVENT_BASE, "body": json.dumps(payload)}, context=None
    )

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["status"] == "RatingSubmitted"
    assert body["target"] == "DRIVER"
    assert body["average_rating"] == pytest.approx(5.0)

    profile_res = table.get_item(Key={"PK": "DRIVER#USR#drv-1", "SK": "PROFILE"})
    profile_item = profile_res["Item"]
    assert profile_item["rating_count"] == 1
    assert profile_item["rating_sum"] == 5


@mock_aws
def test_submit_rating_averages_across_multiple_submissions():
    """Verify submitRating computes a running average across successive ratings."""
    from decimal import Decimal
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    table.put_item(
        Item={
            "PK": "TRIP#trip-rating-2",
            "SK": "METADATA",
            "rider_id": "USR#rdr-1",
            "selected_driver_id": "USR#drv-2",
        }
    )
    table.put_item(
        Item={
            "PK": "DRIVER#USR#drv-2",
            "SK": "PROFILE",
            "rating_count": Decimal("1"),
            "rating_sum": Decimal("4"),
        }
    )

    payload = {
        "action": "submitRating",
        "riderId": "USR#rdr-1",
        "tripId": "trip-rating-2",
        "rating": 2,
        "target": "DRIVER",
    }

    response = handler.lambda_handler(
        {**_SUBMIT_RATING_EVENT_BASE, "body": json.dumps(payload)}, context=None
    )

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["average_rating"] == pytest.approx(3.0)


@mock_aws
def test_submit_rating_invalid_target_returns_400():
    """Verify submitRating returns 400 ValidationError for an invalid target value."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    table.put_item(
        Item={
            "PK": "TRIP#trip-rating-3",
            "SK": "METADATA",
            "rider_id": "USR#rdr-1",
            "selected_driver_id": "USR#drv-1",
        }
    )

    payload = {
        "action": "submitRating",
        "tripId": "trip-rating-3",
        "rating": 5,
        "target": "VEHICLE",
    }

    response = handler.lambda_handler(
        {**_SUBMIT_RATING_EVENT_BASE, "body": json.dumps(payload)}, context=None
    )

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "target" in body["detail"]


@mock_aws
def test_submit_rating_out_of_range_returns_400():
    """Verify submitRating returns 400 ValidationError when rating is outside 1-5."""
    table = _create_mock_table()
    handler = _reload_bidding_handler()

    table.put_item(
        Item={
            "PK": "TRIP#trip-rating-4",
            "SK": "METADATA",
            "rider_id": "USR#rdr-1",
            "selected_driver_id": "USR#drv-1",
        }
    )

    payload = {
        "action": "submitRating",
        "tripId": "trip-rating-4",
        "rating": 7,
        "target": "DRIVER",
    }

    response = handler.lambda_handler(
        {**_SUBMIT_RATING_EVENT_BASE, "body": json.dumps(payload)}, context=None
    )

    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "rating" in body["detail"]
