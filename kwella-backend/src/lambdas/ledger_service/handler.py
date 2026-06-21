"""
kwella — Cancellation & Platform Fee Ledger Service Lambda Handler
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Handles all billing-plane transactions, cancellation penalties, and platform
fee holidays for 7-seater vehicles.

Supported actions (dispatched via the ``action_type`` field on the event):

  PROCESS_CANCELLATION — Atomically applies a cash-cancellation penalty to a Rider
                        (sets 'cancellation_debt' and 'is_suspended' = True)
                        and grants the equivalent platform-fee holiday to the
                        Driver (increases 'fee_holiday_balance'). Uses a DynamoDB
                        transact_write_items call.

  APPLY_TRIP_FEE      — Processes the 10% platform fee for a completed trip.
                        If the Driver has a non-zero fee holiday balance, waives
                        the fee by decrementing the balance instead of charging
                        the Driver.

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native typing syntax.
  - Connection pooling: get_table() and boto3 clients are scoped outside the handler.
  - Explicit client error catching (botocore.exceptions.ClientError).
  - Pydantic v2 only: model_dump(), model_dump_json(), ValidationError.
  - Financial math: strictly Decimal. No floats.
"""

from __future__ import annotations

import json
import logging
import os
from decimal import Decimal
from typing import Any

import boto3
import botocore.exceptions
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

# Shared-layer imports
from database.client import get_table

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Connection pooled client for transaction execution. Uses direct client to avoid double-serialization
# issues associated with resource clients (KWELLA_CODE_GOVERNANCE.md §2).
_dynamodb_client = boto3.client(
    "dynamodb",
    region_name=os.environ.get("AWS_REGION", "af-south-1"),
)


# ---------------------------------------------------------------------------
# Pydantic v2 request models
# ---------------------------------------------------------------------------

class ProcessCancellationPayload(BaseModel):
    """Payload validation model for PROCESS_CANCELLATION."""

    model_config = ConfigDict(
        extra="forbid",
        strict=False,
    )

    rider_id: str = Field(..., min_length=1, description="Bare or USR# prefixed Rider ID.")
    driver_id: str = Field(..., min_length=1, description="Bare or USR# prefixed Driver ID.")
    penalty_amount: Decimal = Field(
        ...,
        gt=Decimal("0.00"),
        le=Decimal("30.00"),
        description="Cancellation penalty amount in ZAR (max R30).",
    )

    @field_validator("rider_id", "driver_id")
    @classmethod
    def strip_prefix(cls, value: str) -> str:
        """Strip 'USR#' prefix if present to normalize user IDs."""
        if value.startswith("USR#"):
            return value[4:]
        return value


class ApplyTripFeePayload(BaseModel):
    """Payload validation model for APPLY_TRIP_FEE."""

    model_config = ConfigDict(
        extra="forbid",
        strict=False,
    )

    driver_id: str = Field(..., min_length=1, description="Bare or USR# prefixed Driver ID.")
    fare_amount: Decimal = Field(
        ...,
        gt=Decimal("0.00"),
        description="Completed trip fare in ZAR.",
    )

    @field_validator("driver_id")
    @classmethod
    def strip_prefix(cls, value: str) -> str:
        """Strip 'USR#' prefix if present to normalize Driver ID."""
        if value.startswith("USR#"):
            return value[4:]
        return value


# ---------------------------------------------------------------------------
# Serialization & response helpers
# ---------------------------------------------------------------------------

class _DecimalEncoder(json.JSONEncoder):
    """Serializes Decimal values as JSON numbers for downstream client parsing."""

    def default(self, obj: Any) -> Any:
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def _ok(body: dict[str, Any]) -> dict[str, Any]:
    """Return a 200 OK API Gateway response."""
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, cls=_DecimalEncoder),
    }


def _bad_request(message: str) -> dict[str, Any]:
    """Return a 400 Bad Request API Gateway response."""
    return {
        "statusCode": 400,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": "ValidationError", "detail": message}),
    }


def _server_error(message: str) -> dict[str, Any]:
    """Return a 500 Internal Server Error API Gateway response."""
    return {
        "statusCode": 500,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": "InfrastructureError", "detail": message}),
    }


# ---------------------------------------------------------------------------
# Core logic actions
# ---------------------------------------------------------------------------

def _process_cancellation(payload: ProcessCancellationPayload) -> dict[str, Any]:
    """Atomically upsert the Rider's cancellation debt and toggle suspension,
    while appending the same penalty amount to the Driver's fee holiday balance.
    Uses transact_write_items to guarantee database atomicity.
    """
    table = get_table()
    table_name = table.name

    rider_pk = f"USR#{payload.rider_id}"
    driver_pk = f"USR#{payload.driver_id}"
    profile_sk = "PROFILE"

    try:
        # Atomically write updates across both profiles using clean client
        _dynamodb_client.transact_write_items(
            TransactItems=[
                {
                    "Update": {
                        "TableName": table_name,
                        "Key": {
                            "PK": {"S": rider_pk},
                            "SK": {"S": profile_sk},
                        },
                        "UpdateExpression": (
                            "SET cancellation_debt = if_not_exists(cancellation_debt, :zero) + :penalty, "
                            "is_suspended = :true"
                        ),
                        "ExpressionAttributeValues": {
                            ":penalty": {"N": str(payload.penalty_amount)},
                            ":zero": {"N": "0.00"},
                            ":true": {"BOOL": True},
                        },
                    }
                },
                {
                    "Update": {
                        "TableName": table_name,
                        "Key": {
                            "PK": {"S": driver_pk},
                            "SK": {"S": profile_sk},
                        },
                        "UpdateExpression": (
                            "SET fee_holiday_balance = if_not_exists(fee_holiday_balance, :zero) + :penalty"
                        ),
                        "ExpressionAttributeValues": {
                            ":penalty": {"N": str(payload.penalty_amount)},
                            ":zero": {"N": "0.00"},
                        },
                    }
                },
            ]
        )
        logger.info(
            "PROCESS_CANCELLATION completed: rider=%s (+%s ZAR debt, suspended), driver=%s (+%s ZAR fee holiday)",
            rider_pk,
            payload.penalty_amount,
            driver_pk,
            payload.penalty_amount,
        )
    except botocore.exceptions.ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error("Transaction failed with ClientError [%s]: %s", error_code, exc)
        return _server_error(f"DynamoDB transactional update failed: {exc.response['Error']['Message']}")

    return _ok({
        "message": "Cancellation debt and fee holiday applied successfully.",
        "rider_id": payload.rider_id,
        "driver_id": payload.driver_id,
        "applied_penalty": payload.penalty_amount,
    })


def _apply_trip_fee(payload: ApplyTripFeePayload) -> dict[str, Any]:
    """Process standard 10% platform fee. If Driver's fee_holiday_balance > 0,
    deduct the fee from that balance atomically using optimistic concurrency.
    """
    table = get_table()
    pk = f"USR#{payload.driver_id}"
    sk = "PROFILE"

    platform_fee = payload.fare_amount * Decimal("0.10")

    max_retries = 3
    for attempt in range(max_retries):
        try:
            # 1. Fetch current driver profile
            response = table.get_item(Key={"PK": pk, "SK": sk})
            item = response.get("Item")
            if not item:
                return _bad_request(f"Driver profile '{payload.driver_id}' not found.")

            # Safely fetch current fee_holiday_balance
            raw_balance = item.get("fee_holiday_balance", Decimal("0.00"))
            current_balance = Decimal(str(raw_balance)) if raw_balance is not None else Decimal("0.00")

            if current_balance > Decimal("0.00"):
                applied_fee = min(current_balance, platform_fee)
                actual_fee_charged = platform_fee - applied_fee
                new_balance = current_balance - applied_fee

                # 2. Conditional update to guarantee update is safe from race conditions
                table.update_item(
                    Key={"PK": pk, "SK": sk},
                    UpdateExpression="SET fee_holiday_balance = :new_balance",
                    ConditionExpression="fee_holiday_balance = :old_balance",
                    ExpressionAttributeValues={
                        ":new_balance": new_balance,
                        ":old_balance": current_balance,
                    },
                )
            else:
                applied_fee = Decimal("0.00")
                actual_fee_charged = platform_fee
                new_balance = Decimal("0.00")

            logger.info(
                "APPLY_TRIP_FEE completed: driver=%s, platform_fee=%s, waived=%s, charged=%s, remaining_holiday=%s",
                pk,
                platform_fee,
                applied_fee,
                actual_fee_charged,
                new_balance,
            )

            return _ok({
                "message": "Trip fee applied.",
                "platform_fee": platform_fee,
                "applied_fee_holiday": applied_fee,
                "actual_fee_charged": actual_fee_charged,
                "remaining_fee_holiday_balance": new_balance,
            })

        except botocore.exceptions.ClientError as exc:
            error_code = exc.response["Error"]["Code"]
            if error_code == "ConditionalCheckFailedException":
                if attempt < max_retries - 1:
                    logger.warning("Concurrency collision on fee_holiday_balance for driver %s, retrying...", pk)
                    continue
                else:
                    logger.error("Max retries exceeded for driver fee_holiday_balance update.")
                    return _server_error("Concurrency error: fee_holiday_balance was modified concurrently.")
            logger.error("DynamoDB error on APPLY_TRIP_FEE: %s", exc)
            return _server_error(f"DynamoDB error [{error_code}]: unable to apply platform fee.")


# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

_ROUTER = {
    "PROCESS_CANCELLATION": lambda payload: _process_cancellation(ProcessCancellationPayload(**payload)),
    "APPLY_TRIP_FEE": lambda payload: _apply_trip_fee(ApplyTripFeePayload(**payload)),
}

# ---------------------------------------------------------------------------
# Route key → action_type mapping (API Gateway v2 HTTP proxy integration)
# ---------------------------------------------------------------------------
# When invoked via API Gateway v2 (payload_format_version = "2.0") the raw
# HTTP body arrives in event["body"] and the matched route is in
# event["routeKey"]. Direct-invocation callers (tests, other Lambdas) may
# still supply action_type + payload at the top level — both are supported.

_ROUTE_KEY_MAP: dict[str, str] = {
    "POST /ledger/cancellation": "PROCESS_CANCELLATION",
    "POST /ledger/trip-fee": "APPLY_TRIP_FEE",
}


def _normalise_trip_fee_payload(raw: dict[str, Any]) -> dict[str, Any]:
    """Translate the HTTP client payload to the fields expected by
    ApplyTripFeePayload, dropping any extra keys that the model's
    ``extra="forbid"`` policy would reject.

    HTTP contract fields accepted::

        driverId          → driver_id   (required)
        amount            → fare_amount (required)
        tripId            → dropped (informational only)
        paymentMethod     → dropped
        isPlatformHoliday → dropped

    Direct-invocation payloads using snake_case keys pass through unchanged.
    """
    driver_id = raw.get("driver_id") or raw.get("driverId")
    fare_amount = raw.get("fare_amount") or raw.get("amount")
    out: dict[str, Any] = {}
    if driver_id is not None:
        out["driver_id"] = driver_id
    if fare_amount is not None:
        out["fare_amount"] = fare_amount
    return out


def _normalise_cancellation_payload(raw: dict[str, Any]) -> dict[str, Any]:
    """Translate camelCase HTTP client keys to the snake_case keys expected by
    ProcessCancellationPayload.

    Mapping::

        riderId       → rider_id
        driverId      → driver_id
        penaltyAmount → penalty_amount
    """
    out = dict(raw)
    if "riderId" in out and "rider_id" not in out:
        out["rider_id"] = out.pop("riderId")
    if "driverId" in out and "driver_id" not in out:
        out["driver_id"] = out.pop("driverId")
    if "penaltyAmount" in out and "penalty_amount" not in out:
        out["penalty_amount"] = out.pop("penaltyAmount")
    return out


# ---------------------------------------------------------------------------
# Lambda entrypoint
# ---------------------------------------------------------------------------

def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Primary entrypoint for the Cancellation & Fee Ledger Service.

    Supports two invocation styles:

    1. **API Gateway v2 HTTP proxy** (``payload_format_version = "2.0"``):
       Unwraps ``event["body"]`` as the payload and derives ``action_type``
       from ``event["routeKey"]`` via ``_ROUTE_KEY_MAP``.

    2. **Direct invocation** (CI tests, internal Lambda-to-Lambda calls):
       Reads ``action_type`` and ``payload`` as top-level event keys.
    """
    try:
        # ------------------------------------------------------------------
        # Step 1: Detect invocation style and extract (action_type, payload)
        # ------------------------------------------------------------------
        is_apigw_proxy = "routeKey" in event or "requestContext" in event

        if is_apigw_proxy:
            route_key: str = event.get("routeKey", "")
            action_type: str = _ROUTE_KEY_MAP.get(route_key, "").upper()

            raw_body: str = event.get("body") or "{}"
            try:
                raw_payload: dict[str, Any] = json.loads(raw_body)
            except json.JSONDecodeError as exc:
                logger.warning("Malformed JSON body on route '%s': %s", route_key, exc)
                return _bad_request(f"Request body is not valid JSON: {exc}")

            # Normalise camelCase HTTP client keys → snake_case model keys.
            if action_type == "APPLY_TRIP_FEE":
                payload: dict[str, Any] = _normalise_trip_fee_payload(raw_payload)
            elif action_type == "PROCESS_CANCELLATION":
                payload = _normalise_cancellation_payload(raw_payload)
            else:
                payload = raw_payload

            logger.info(
                "Ledger service invoked via API GW proxy: routeKey=%s → action_type=%s",
                route_key,
                action_type,
            )
        else:
            # Direct invocation — action_type and payload are top-level keys.
            action_type = event.get("action_type", "").upper()
            payload = event.get("payload", {})

            logger.info("Ledger service invoked directly: action_type=%s", action_type)

        # ------------------------------------------------------------------
        # Step 2: Route to the correct action handler
        # ------------------------------------------------------------------
        handler_fn = _ROUTER.get(action_type)
        if not handler_fn:
            supported = ", ".join(_ROUTER.keys())
            return _bad_request(f"Unknown action_type '{action_type}'. Supported actions: {supported}")

        return handler_fn(payload)

    except ValidationError as exc:
        logger.warning("Validation failed for action_type %s: %s", action_type, exc)
        return _bad_request(exc.json())
    except Exception as exc:  # pylint: disable=broad-except
        logger.error("Unexpected error in ledger service: %s", exc, exc_info=True)
        return _server_error(f"Unexpected error: {type(exc).__name__}")
