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
import pytest
from botocore.exceptions import ClientError
from moto import mock_aws


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

