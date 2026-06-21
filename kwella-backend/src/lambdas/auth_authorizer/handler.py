"""
kwella — API Gateway Custom Token/Request Authorizer Lambda
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Authenticates and authorizes requests at the API Gateway level.

Key behaviors:
  1. Extracts JWT Bearer token from Token or Request authorizer formats.
  2. Decodes JWT payload (mock decode using base64 url-safe decoding of claims).
  3. Queries DynamoDB using PK = "USR#<user_id>", SK = "PROFILE".
  4. If user is suspended (is_suspended = True), returns a Deny Policy.
  5. Otherwise, returns an Allow Policy mapping to the request's methodArn.

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native syntax throughout.
  - Connection pooled boto3 table client retrieved outside execution loop via get_table().
  - All DynamoDB fetches wrapped in try-except block catching botocore.exceptions.ClientError.
  - No hardcoded secrets.
"""

from __future__ import annotations

import base64
import json
import logging
from typing import Any

import botocore.exceptions

# Shared layer import
from database.client import get_table

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


def _extract_token(event: dict[str, Any]) -> str:
    """Extract standard bearer token from custom API Gateway authorizer payloads.

    Supports:
      - TOKEN format: event['authorizationToken']
      - REQUEST format: event['headers']['authorization'] (case-insensitive)
    """
    raw_token: str | None = event.get("authorizationToken")

    if not raw_token:
        headers = event.get("headers") or {}
        for key, val in headers.items():
            if key.lower() == "authorization":
                raw_token = val
                break

    if not raw_token:
        logger.warning("No Authorization token found in event headers or authorizationToken field.")
        raise Exception("Unauthorized")

    raw_token_str = str(raw_token).strip()

    if raw_token_str.lower().startswith("bearer "):
        raw_token_str = raw_token_str[7:].strip()

    if not raw_token_str:
        logger.warning("Authorization token is empty after stripping prefix.")
        raise Exception("Unauthorized")

    return raw_token_str


def _decode_jwt_payload_mock(token: str) -> dict[str, Any]:
    """Perform a mock base64url decode of the JWT payload segment to extract claims.

    JWT structure: header.payload.signature
    """
    try:
        parts = token.split(".")
        if len(parts) != 3:
            raise ValueError("JWT token must consist of three dot-separated segments.")

        payload_b64 = parts[1]
        # Pad if length is not a multiple of 4
        payload_b64 += "=" * ((4 - len(payload_b64) % 4) % 4)
        
        payload_bytes = base64.urlsafe_b64decode(payload_b64)
        return json.loads(payload_bytes.decode("utf-8"))
    except Exception as exc:
        logger.warning("Failed to decode token payload: %s", exc)
        raise Exception("Unauthorized")


def _simple_response(is_authorized: bool, principal_id: str) -> dict[str, Any]:
    """Generate an API Gateway v2 simple authorizer response.

    When the authorizer is configured with:
      authorizer_payload_format_version = "2.0"
      enable_simple_responses           = true

    API Gateway expects a response of the form::

        {"isAuthorized": true | false, "context": {...}}

    Returning a full IAM policy document in this mode is treated as a
    malformed authorizer response and causes a 500 Internal Server Error
    before the backend Lambda is ever invoked.
    """
    return {
        "isAuthorized": is_authorized,
        "context": {
            "user_id": principal_id,
        },
    }


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Primary handler for the kwella API Gateway v2 simple-response authorizer.

    Configured in Terraform with:
      authorizer_payload_format_version = "2.0"
      enable_simple_responses           = true

    This mode requires the response to be::

        {"isAuthorized": true | false, "context": {"user_id": "..."}}

    Args:
        event: Inbound REQUEST authorizer payload (API GW v2 format 2.0).
        context: Lambda execution context.

    Returns:
        Simple response dict with ``isAuthorized`` and optional ``context``.
    """
    logger.info("Authorizer lambda invoked.")

    # Extract authorization header/token
    token = _extract_token(event)

    # Decode mock claims
    claims = _decode_jwt_payload_mock(token)

    # Extract user identity
    user_id = claims.get("user_id") or claims.get("sub")
    if not user_id:
        logger.warning("Token claims missing 'user_id' and 'sub'.")
        raise Exception("Unauthorized")

    is_suspended = False

    pk = f"USR#{user_id}"
    sk = "PROFILE"

    table = get_table()
    try:
        response = table.get_item(Key={"PK": pk, "SK": sk})
        item = response.get("Item")
        if item:
            is_suspended = item.get("is_suspended") is True
    except botocore.exceptions.ClientError as exc:
        error_code = exc.response.get("Error", {}).get("Code", "Unknown")
        logger.error("DynamoDB ClientError [%s] during profile retrieval for %s: %s", error_code, pk, exc)
        # Secure default: deny access if the DB check fails (fail-closed).
        is_suspended = True

    is_authorized = not is_suspended
    logger.info(
        "Auth decision: isAuthorized=%s for user %s",
        is_authorized,
        user_id,
    )

    return _simple_response(is_authorized, user_id)
