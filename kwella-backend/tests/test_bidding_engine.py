"""
tests/test_bidding_engine.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Isolated unit tests for the kwella Bidding Engine Lambda handler.

Covers:
  - $connect: Writes connection tracking session row to DynamoDB (with and without auth token).
  - $disconnect: Deletes connection tracking session row from DynamoDB.
  - sendBid: Parses body, extracts bid particulars, and returns placeholder success block.
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
