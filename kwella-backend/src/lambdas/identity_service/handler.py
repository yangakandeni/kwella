"""
kwella — Identity & Profile Service Lambda Handler
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Primary compute worker for all identity-plane operations.

Supported actions (dispatched via the ``action_type`` field on the event):

  UPSERT_PROFILE    — Validate and write a Rider or Driver profile record.
                      PK = USR#<user_id>  |  SK = PROFILE
                      For Driver profiles, GSI1_PK and GSI1_SK are populated
                      to maintain the vehicle→driver relationship map.

  REGISTER_VEHICLE  — Validate and write a VehicleAsset record.
                      PK = VEH#<cata_sticker>  |  SK = METADATA
                      GSI1_PK = USR#<owner_id>  |  GSI1_SK = VEH#<cata_sticker>

  GET_PROFILE       — Read a single item by its composite key (PK + SK).

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native syntax throughout; no legacy typing imports.
  - boto3 client is consumed via the module-level get_table() helper
    (connection pooled outside the handler for warm-invocation reuse).
  - All DynamoDB I/O wrapped in explicit botocore.exceptions.ClientError
    try-except blocks.
  - No hardcoded secrets or table names; sourced from os.environ via client.py.
  - Pydantic v2 only: model_dump(), model_dump_json(), ValidationError — no .dict() or .json().
  - Responses are sanitised dicts; raw boto3 responses are never forwarded.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from decimal import Decimal
from typing import Any

import botocore.exceptions
from pydantic import ValidationError

# Shared-layer imports — resolved by the Lambda layer at runtime.
from database.client import get_table
from models.schemas import DriverProfile, RiderProfile, VehicleAsset

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


# ---------------------------------------------------------------------------
# Serialisation helper
# ---------------------------------------------------------------------------

class _DecimalEncoder(json.JSONEncoder):
    """Encode Decimal values as floats so financial ledger fields are
    serialised as JSON numbers (not strings), giving React/Flutter clients
    a consistent numeric type interface."""

    def default(self, obj: Any) -> Any:
        if isinstance(obj, Decimal):
            return float(obj)
        if isinstance(obj, datetime):
            return obj.isoformat()
        return super().default(obj)


def _serialise(payload: dict[str, Any]) -> dict[str, Any]:
    """Round-trip through JSON to coerce all Decimal fields to floats.

    DynamoDB returns Decimal for numeric types; this ensures downstream
    consumers (React, Flutter) receive native JSON numbers rather than
    un-serialisable Python objects or raw string representations.
    """
    return json.loads(json.dumps(payload, cls=_DecimalEncoder))


def _prepare_for_db(payload: dict[str, Any]) -> dict[str, Any]:
    """Prepare a profile dictionary for DynamoDB storage.

    Converts datetime objects to ISO strings, but preserves Decimals so they
    are written as native DynamoDB Numbers (not floats, which boto3 rejects).
    """
    out = {}
    for k, v in payload.items():
        if isinstance(v, datetime):
            out[k] = v.isoformat()
        elif isinstance(v, dict):
            out[k] = _prepare_for_db(v)
        elif isinstance(v, list):
            out[k] = [
                _prepare_for_db(x) if isinstance(x, dict)
                else (x.isoformat() if isinstance(x, datetime) else x)
                for x in v
            ]
        else:
            out[k] = v
    return out


# ---------------------------------------------------------------------------
# Response factory helpers
# ---------------------------------------------------------------------------

def _ok(body: dict[str, Any]) -> dict[str, Any]:
    """Return an API Gateway-compatible 200 OK response."""
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, cls=_DecimalEncoder),
    }


def _bad_request(message: str) -> dict[str, Any]:
    """Return an API Gateway-compatible 400 Bad Request response."""
    return {
        "statusCode": 400,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": "ValidationError", "detail": message}),
    }


def _server_error(message: str) -> dict[str, Any]:
    """Return an API Gateway-compatible 500 Internal Server Error response."""
    return {
        "statusCode": 500,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": "InfrastructureError", "detail": message}),
    }


def _not_found() -> dict[str, Any]:
    """Return an API Gateway-compatible 404 Not Found response."""
    return {
        "statusCode": 404,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": "NotFound", "detail": "Requested item does not exist."}),
    }


# ---------------------------------------------------------------------------
# Action handlers
# ---------------------------------------------------------------------------

def _upsert_profile(payload: dict[str, Any]) -> dict[str, Any]:
    """Validate and write a Rider or Driver profile to DynamoDB.

    Expected payload fields:
        user_id    (str)  — Bare user identifier (no USR# prefix required).
        role       (str)  — Either "RIDER" or "DRIVER".
        phone      (str)  — E.164-formatted mobile number.
        rating     (str | float, optional) — Star rating [0.0, 5.0].

        # RIDER-specific (optional)
        cancellation_debt (str | float, optional)
        active_trip_id    (str | None, optional)

        # DRIVER-specific (required when role == "DRIVER")
        assigned_cata_sticker (str)
        fee_holiday_balance   (str | float, optional)
        is_online             (bool, optional)

    Returns an API Gateway response dict.
    """
    user_id: str | None = payload.get("user_id")
    role: str | None = payload.get("role", "").upper()

    if not user_id:
        return _bad_request("'user_id' is required for UPSERT_PROFILE.")
    if role not in ("RIDER", "DRIVER"):
        return _bad_request("'role' must be either 'RIDER' or 'DRIVER'.")

    pk = f"USR#{user_id}"
    sk = "PROFILE"

    try:
        if role == "RIDER":
            profile = RiderProfile(**{k: v for k, v in payload.items() if k not in ("user_id", "role")})
            item: dict[str, Any] = {
                "PK": pk,
                "SK": sk,
                "role": "RIDER",
                **_prepare_for_db(profile.model_dump()),
            }
        else:
            # DRIVER — populate GSI1 to maintain vehicle→driver relationship map.
            profile = DriverProfile(**{k: v for k, v in payload.items() if k not in ("user_id", "role")})
            cata_sticker: str = profile.assigned_cata_sticker  # already normalised by validator
            item = {
                "PK": pk,
                "SK": sk,
                "role": "DRIVER",
                "GSI1_PK": f"VEH#{cata_sticker}",
                "GSI1_SK": "DRIVER",
                **_prepare_for_db(profile.model_dump()),
            }
    except ValidationError as exc:
        logger.warning("UPSERT_PROFILE validation failed for user_id=%s: %s", user_id, exc)
        return _bad_request(exc.json())

    table = get_table()
    try:
        table.put_item(Item=item)
        logger.info("UPSERT_PROFILE success: PK=%s SK=%s role=%s", pk, sk, role)
    except botocore.exceptions.ClientError as exc:
        error_code: str = exc.response["Error"]["Code"]
        logger.error("DynamoDB ClientError [%s] on UPSERT_PROFILE PK=%s: %s", error_code, pk, exc)
        return _server_error(f"DynamoDB error [{error_code}]: unable to write profile.")

    return _ok({"message": "Profile upserted successfully.", "PK": pk, "SK": sk, "role": role})


def _register_vehicle(payload: dict[str, Any]) -> dict[str, Any]:
    """Validate and write a VehicleAsset record to DynamoDB.

    Expected payload fields:
        cata_sticker (str) — Unique CATA regulatory sticker identifier.
        make         (str) — Vehicle manufacturer.
        model        (str) — Vehicle model name.
        owner_id     (str) — Must carry the 'USR#' prefix.

    The vehicle record is stored with:
        PK        = VEH#<cata_sticker>
        SK        = METADATA
        GSI1_PK   = USR#<owner_id>   ← enables owner → vehicle query
        GSI1_SK   = VEH#<cata_sticker>

    Returns an API Gateway response dict.
    """
    try:
        vehicle = VehicleAsset(**payload)
    except ValidationError as exc:
        logger.warning("REGISTER_VEHICLE validation failed: %s", exc)
        return _bad_request(exc.json())

    pk = f"VEH#{vehicle.cata_sticker}"
    sk = "METADATA"

    item: dict[str, Any] = {
        "PK": pk,
        "SK": sk,
        "GSI1_PK": vehicle.owner_id,           # already carries USR# prefix (validated)
        "GSI1_SK": f"VEH#{vehicle.cata_sticker}",
        **_prepare_for_db(vehicle.model_dump()),
    }

    table = get_table()
    try:
        # condition_expression prevents accidental overwrite of an existing registration.
        table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(PK)",
        )
        logger.info("REGISTER_VEHICLE success: PK=%s owner_id=%s", pk, vehicle.owner_id)
    except botocore.exceptions.ClientError as exc:
        error_code: str = exc.response["Error"]["Code"]
        if error_code == "ConditionalCheckFailedException":
            logger.warning("REGISTER_VEHICLE duplicate detected: PK=%s", pk)
            return _bad_request(
                f"Vehicle '{vehicle.cata_sticker}' is already registered. "
                "Use a dedicated update action to amend an existing record."
            )
        logger.error("DynamoDB ClientError [%s] on REGISTER_VEHICLE PK=%s: %s", error_code, pk, exc)
        return _server_error(f"DynamoDB error [{error_code}]: unable to register vehicle.")

    return _ok({
        "message": "Vehicle registered successfully.",
        "PK": pk,
        "SK": sk,
        "GSI1_PK": vehicle.owner_id,
        "GSI1_SK": f"VEH#{vehicle.cata_sticker}",
    })


def _get_profile(payload: dict[str, Any]) -> dict[str, Any]:
    """Retrieve a single DynamoDB item by its composite primary key.

    Expected payload fields:
        PK (str) — Partition key, e.g. 'USR#abc-123' or 'VEH#CT-001'.
        SK (str) — Sort key, e.g. 'PROFILE' or 'METADATA'.

    Returns an API Gateway response dict containing the sanitised item, or a
    404 response if the requested key combination does not exist.
    """
    pk: str | None = payload.get("PK")
    sk: str | None = payload.get("SK")

    if not pk or not sk:
        return _bad_request("Both 'PK' and 'SK' are required for GET_PROFILE.")

    table = get_table()
    try:
        response = table.get_item(Key={"PK": pk, "SK": sk})
        logger.info("GET_PROFILE executed: PK=%s SK=%s", pk, sk)
    except botocore.exceptions.ClientError as exc:
        error_code: str = exc.response["Error"]["Code"]
        logger.error("DynamoDB ClientError [%s] on GET_PROFILE PK=%s SK=%s: %s", error_code, pk, sk, exc)
        return _server_error(f"DynamoDB error [{error_code}]: unable to retrieve item.")

    item = response.get("Item")
    if item is None:
        logger.info("GET_PROFILE not found: PK=%s SK=%s", pk, sk)
        return _not_found()

    return _ok({"item": _serialise(item)})


# ---------------------------------------------------------------------------
# Action router
# ---------------------------------------------------------------------------

_ROUTER: dict[str, Any] = {
    "UPSERT_PROFILE": _upsert_profile,
    "REGISTER_VEHICLE": _register_vehicle,
    "GET_PROFILE": _get_profile,
}


# ---------------------------------------------------------------------------
# Lambda entrypoint
# ---------------------------------------------------------------------------

def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Primary Lambda entrypoint for the kwella Identity & Profile Service.

    Routes inbound events to the correct action handler based on the
    ``action_type`` field present on the event payload.

    Args:
        event:   The Lambda event dict. Must contain an ``action_type`` string
                 key and a ``payload`` dict with action-specific fields.
        context: The Lambda runtime context object (reserved for future use).

    Returns:
        An API Gateway-compatible response dict containing a ``statusCode``,
        ``headers``, and JSON-serialised ``body``.

    Event contract::

        {
            "action_type": "UPSERT_PROFILE" | "REGISTER_VEHICLE" | "GET_PROFILE",
            "payload": { ... }
        }

    Example — upsert a rider::

        {
            "action_type": "UPSERT_PROFILE",
            "payload": {
                "user_id": "abc-123",
                "role": "RIDER",
                "phone": "+27821234567"
            }
        }

    Example — register a vehicle::

        {
            "action_type": "REGISTER_VEHICLE",
            "payload": {
                "cata_sticker": "CT-7001",
                "make": "Toyota",
                "model": "HiAce",
                "owner_id": "USR#owner-456"
            }
        }

    Example — fetch a profile::

        {
            "action_type": "GET_PROFILE",
            "payload": {
                "PK": "USR#abc-123",
                "SK": "PROFILE"
            }
        }
    """
    action_type: str = event.get("action_type", "").upper()
    payload: dict[str, Any] = event.get("payload", {})

    logger.info("Identity service invoked: action_type=%s", action_type)

    handler_fn = _ROUTER.get(action_type)
    if handler_fn is None:
        supported = ", ".join(_ROUTER.keys())
        logger.warning("Unknown action_type received: '%s'", action_type)
        return _bad_request(
            f"Unknown action_type '{action_type}'. Supported actions: {supported}."
        )

    return handler_fn(payload)
