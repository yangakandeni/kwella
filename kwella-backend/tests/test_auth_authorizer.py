"""
tests/test_auth_authorizer.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Isolated unit tests for the Custom API Gateway Token Authorizer Lambda handler.
"""

from __future__ import annotations

import base64
import json
import sys
from typing import Any

import boto3
import pytest
import botocore.exceptions
from moto import mock_aws


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _generate_mock_jwt(claims: dict[str, Any]) -> str:
    """Generate a mock un-signed JWT token string containing the provided claims."""
    # Header segment
    header = {"alg": "none", "typ": "JWT"}
    header_b64 = base64.urlsafe_b64encode(json.dumps(header).encode("utf-8")).decode("utf-8").rstrip("=")
    
    # Payload segment
    payload_b64 = base64.urlsafe_b64encode(json.dumps(claims).encode("utf-8")).decode("utf-8").rstrip("=")
    
    # Signature segment (empty for alg=none)
    signature_b64 = ""
    
    return f"{header_b64}.{payload_b64}.{signature_b64}"


def _create_mock_table() -> Any:
    """Provision a moto-intercepted DynamoDB table matching production schema."""
    dynamodb = boto3.resource("dynamodb", region_name="af-south-1")
    table = dynamodb.create_table(
        TableName="kwella-core-test",
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
    table.meta.client.get_waiter("table_exists").wait(TableName="kwella-core-test")
    return table


def _reload_auth_handler():
    """Reload database.client and auth_authorizer.handler modules to inject active mock contexts."""
    for mod_name in ("database.client", "auth_authorizer.handler"):
        if mod_name in sys.modules:
            del sys.modules[mod_name]
    import auth_authorizer.handler as handler  # noqa: PLC0415
    return handler


# ---------------------------------------------------------------------------
# Token Extraction Tests
# ---------------------------------------------------------------------------

@mock_aws
def test_extract_token_from_token_authorizer_format():
    """Verify bearer token is extracted from authorizationToken field."""
    handler = _reload_auth_handler()
    
    event = {
        "type": "TOKEN",
        "authorizationToken": "Bearer token123",
        "methodArn": "arn:aws:execute-api:region:account:api/stage/GET/resource"
    }
    
    token = handler._extract_token(event)
    assert token == "token123"


@mock_aws
def test_extract_token_from_request_authorizer_headers():
    """Verify bearer token is extracted case-insensitively from REQUEST headers."""
    handler = _reload_auth_handler()
    
    # Upper-case header
    event_upper = {
        "type": "REQUEST",
        "headers": {
            "Authorization": "Bearer token456"
        },
        "methodArn": "arn:aws:execute-api:region:account:api/stage/GET/resource"
    }
    assert handler._extract_token(event_upper) == "token456"
    
    # Lower-case header
    event_lower = {
        "type": "REQUEST",
        "headers": {
            "authorization": "Bearer token789"
        },
        "methodArn": "arn:aws:execute-api:region:account:api/stage/GET/resource"
    }
    assert handler._extract_token(event_lower) == "token789"


@mock_aws
def test_extract_token_strips_bearer_prefix_case_insensitively():
    """Verify the 'Bearer ' prefix is stripped case-insensitively and whitespace trimmed."""
    handler = _reload_auth_handler()
    
    event = {
        "type": "TOKEN",
        "authorizationToken": "bearer   token-with-spaces   ",
        "methodArn": "arn:aws:execute-api:region:account:api/stage/GET/resource"
    }
    assert handler._extract_token(event) == "token-with-spaces"


@mock_aws
def test_extract_token_missing_raises_unauthorized():
    """Verify that if token is missing or empty, Exception('Unauthorized') is raised."""
    handler = _reload_auth_handler()
    
    event_empty = {
        "type": "TOKEN",
        "authorizationToken": "",
        "methodArn": "arn:aws:execute-api:region:account:api/stage/GET/resource"
    }
    with pytest.raises(Exception, match="Unauthorized"):
        handler._extract_token(event_empty)

    event_missing = {
        "type": "REQUEST",
        "headers": {},
        "methodArn": "arn:aws:execute-api:region:account:api/stage/GET/resource"
    }
    with pytest.raises(Exception, match="Unauthorized"):
        handler._extract_token(event_missing)


# ---------------------------------------------------------------------------
# JWT Parsing Tests
# ---------------------------------------------------------------------------

@mock_aws
def test_decode_jwt_payload_mock_success():
    """Verify that JWT mock decoding extracts claims correctly."""
    handler = _reload_auth_handler()
    
    claims = {"user_id": "usr-1", "sub": "sub-1", "email": "usr-1@example.com"}
    token = _generate_mock_jwt(claims)
    
    decoded = handler._decode_jwt_payload_mock(token)
    assert decoded["user_id"] == "usr-1"
    assert decoded["sub"] == "sub-1"
    assert decoded["email"] == "usr-1@example.com"


@mock_aws
def test_decode_jwt_payload_mock_invalid_format_raises_unauthorized():
    """Verify that malformed JWT strings raise Exception('Unauthorized')."""
    handler = _reload_auth_handler()
    
    # 2 segments instead of 3
    token_bad = "header.payload"
    with pytest.raises(Exception, match="Unauthorized"):
        handler._decode_jwt_payload_mock(token_bad)


# ---------------------------------------------------------------------------
# Authorization Core Logic Tests
# ---------------------------------------------------------------------------

@mock_aws
def test_lambda_handler_allows_when_suspended_false():
    """Verify that user is Allowed if is_suspended = False."""
    table = _create_mock_table()
    handler = _reload_auth_handler()
    
    # Write Rider profile that is NOT suspended
    table.put_item(
        Item={
            "PK": "USR#user-allow-1",
            "SK": "PROFILE",
            "role": "RIDER",
            "is_suspended": False,
        }
    )
    
    token = _generate_mock_jwt({"user_id": "user-allow-1"})
    event = {
        "type": "TOKEN",
        "authorizationToken": f"Bearer {token}",
        "methodArn": "arn:aws:execute-api:af-south-1:123456789012:api123/prod/GET/trips"
    }
    
    policy = handler.lambda_handler(event, context=None)
    
    assert policy["principalId"] == "user-allow-1"
    assert policy["policyDocument"]["Statement"][0]["Effect"] == "Allow"
    assert policy["policyDocument"]["Statement"][0]["Resource"] == event["methodArn"]
    assert policy["context"]["user_id"] == "user-allow-1"


@mock_aws
def test_lambda_handler_allows_when_profile_does_not_exist():
    """Verify that user is Allowed if profile does not exist in DB yet (default safe state)."""
    _create_mock_table()
    handler = _reload_auth_handler()
    
    # User does not exist in DynamoDB
    token = _generate_mock_jwt({"user_id": "user-new-2"})
    event = {
        "type": "TOKEN",
        "authorizationToken": f"Bearer {token}",
        "methodArn": "arn:aws:execute-api:af-south-1:123456789012:api123/prod/GET/trips"
    }
    
    policy = handler.lambda_handler(event, context=None)
    
    assert policy["principalId"] == "user-new-2"
    assert policy["policyDocument"]["Statement"][0]["Effect"] == "Allow"


@mock_aws
def test_lambda_handler_denies_when_suspended_true():
    """Verify that user is Denied access if is_suspended = True."""
    table = _create_mock_table()
    handler = _reload_auth_handler()
    
    # Write Driver profile that IS suspended
    table.put_item(
        Item={
            "PK": "USR#user-deny-1",
            "SK": "PROFILE",
            "role": "DRIVER",
            "is_suspended": True,
        }
    )
    
    token = _generate_mock_jwt({"user_id": "user-deny-1"})
    event = {
        "type": "TOKEN",
        "authorizationToken": f"Bearer {token}",
        "methodArn": "arn:aws:execute-api:af-south-1:123456789012:api123/prod/GET/trips"
    }
    
    policy = handler.lambda_handler(event, context=None)
    
    assert policy["principalId"] == "user-deny-1"
    assert policy["policyDocument"]["Statement"][0]["Effect"] == "Deny"
    assert policy["policyDocument"]["Statement"][0]["Resource"] == event["methodArn"]


@mock_aws
def test_lambda_handler_denies_on_database_error_fail_closed():
    """Verify that if DynamoDB client errors out, we fail-closed (Deny policy generated)."""
    # Do NOT create mock table. This causes a ResourceNotFoundException from DynamoDB/moto.
    handler = _reload_auth_handler()
    
    token = _generate_mock_jwt({"user_id": "user-db-error"})
    event = {
        "type": "TOKEN",
        "authorizationToken": f"Bearer {token}",
        "methodArn": "arn:aws:execute-api:af-south-1:123456789012:api123/prod/GET/trips"
    }
    
    policy = handler.lambda_handler(event, context=None)
    
    assert policy["principalId"] == "user-db-error"
    assert policy["policyDocument"]["Statement"][0]["Effect"] == "Deny"
