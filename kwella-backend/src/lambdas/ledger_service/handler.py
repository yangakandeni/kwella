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
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

import boto3
import botocore.exceptions
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

# Shared-layer imports
from database.client import get_table
from cancellation_handler import (
    CancellationLedgerPayload,
    DebtSettlementPayload,
    RiderDebtNotFoundError,
    process_cancellation,
    settle_rider_debt,
)

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


def _route_key_to_action(route_key: str) -> str:
    if not route_key:
        return ""
    if route_key in _ROUTE_KEY_MAP:
        return _ROUTE_KEY_MAP[route_key]
    return _ROUTE_KEY_MAP.get(route_key.lower(), "")


def _parse_iso_timestamp(value: str) -> datetime:
    if not isinstance(value, str):
        raise ValueError("Timestamp must be an ISO-8601 string.")
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value)


def _missing_cancellation_transaction_markers(payload: dict[str, Any]) -> bool:
    if payload.get("driver_in_transit_seconds") is not None:
        return False
    if payload.get("driver_en_route_at") is not None and payload.get("cancelled_at") is not None:
        return False
    return True


def _ensure_cancellation_transit_seconds(payload: dict[str, Any]) -> dict[str, Any]:
    payload = dict(payload)
    if payload.get("driver_in_transit_seconds") is None:
        driver_en_route_at = payload.get("driver_en_route_at")
        cancelled_at = payload.get("cancelled_at")
        if driver_en_route_at is not None and cancelled_at is not None:
            try:
                if isinstance(driver_en_route_at, str):
                    driver_en_route_at = _parse_iso_timestamp(driver_en_route_at)
                if isinstance(cancelled_at, str):
                    cancelled_at = _parse_iso_timestamp(cancelled_at)
                if driver_en_route_at.tzinfo is None:
                    driver_en_route_at = driver_en_route_at.replace(tzinfo=timezone.utc)
                if cancelled_at.tzinfo is None:
                    cancelled_at = cancelled_at.replace(tzinfo=timezone.utc)
                payload["driver_in_transit_seconds"] = max(
                    int((cancelled_at - driver_en_route_at).total_seconds()),
                    0,
                )
            except (TypeError, ValueError):
                pass
    return payload


# ---------------------------------------------------------------------------
# Core logic actions
# ---------------------------------------------------------------------------

def _process_cancellation(payload: CancellationLedgerPayload) -> dict[str, Any]:
    """Delegate the hybrid payment late-cancellation transaction to the dedicated module."""
    try:
        return _ok(process_cancellation(payload))
    except botocore.exceptions.ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        return _server_error(f"DynamoDB transactional update failed: {error_code}")


def _settle_rider_debt(payload: DebtSettlementPayload) -> dict[str, Any]:
    """Delegate rider cancellation-debt settlement to the dedicated module."""
    try:
        return _ok(settle_rider_debt(payload))
    except RiderDebtNotFoundError as exc:
        return _bad_request(str(exc))
    except botocore.exceptions.ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        if error_code == "TransactionCanceledException":
            return _bad_request("Debt settlement failed: debt already settled or amount mismatch.")
        return _server_error(f"DynamoDB transactional update failed: {error_code}")


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
    "PROCESS_CANCELLATION": lambda payload: _process_cancellation(CancellationLedgerPayload(**payload)),
    "APPLY_TRIP_FEE": lambda payload: _apply_trip_fee(ApplyTripFeePayload(**payload)),
    "SETTLE_RIDER_DEBT": lambda payload: _settle_rider_debt(DebtSettlementPayload(**payload)),
}

# ---------------------------------------------------------------------------
# Route key → action_type mapping (API Gateway v2 HTTP proxy integration)
# ---------------------------------------------------------------------------
# When invoked via API Gateway v2 (payload_format_version = "2.0") the raw
# HTTP body arrives in event["body"] and the matched route is in
# event["routeKey"]. Direct-invocation callers (tests, other Lambdas) may
# still supply action_type + payload at the top level — both are supported.

_ROUTE_KEY_MAP: dict[str, str] = {
    "post /ledger/cancellation": "PROCESS_CANCELLATION",
    "post /ledger/trip-fee": "APPLY_TRIP_FEE",
    "post /ledger/debt/settle": "SETTLE_RIDER_DEBT",
    "ledger_cancellation": "PROCESS_CANCELLATION",
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
        tripId        → trip_id
        penaltyAmount → amount
        amount        → amount
        timestamp     → timestamp
        driverEnRouteAt → driver_en_route_at
        cancelledAt   → cancelled_at
        driverInTransitSeconds → driver_in_transit_seconds
    """
    out = dict(raw)
    if "riderId" in out and "rider_id" not in out:
        out["rider_id"] = out.pop("riderId")
    if "driverId" in out and "driver_id" not in out:
        out["driver_id"] = out.pop("driverId")
    if "tripId" in out and "trip_id" not in out:
        out["trip_id"] = out.pop("tripId")
    if "penaltyAmount" in out and "amount" not in out:
        out["amount"] = out.pop("penaltyAmount")
    if "driverEnRouteAt" in out and "driver_en_route_at" not in out:
        out["driver_en_route_at"] = out.pop("driverEnRouteAt")
    if "cancelledAt" in out and "cancelled_at" not in out:
        out["cancelled_at"] = out.pop("cancelledAt")
    if "driverInTransitSeconds" in out and "driver_in_transit_seconds" not in out:
        out["driver_in_transit_seconds"] = out.pop("driverInTransitSeconds")
    return out


def _normalise_debt_settlement_payload(raw: dict[str, Any]) -> dict[str, Any]:
    """Translate camelCase HTTP client keys to the snake_case keys expected by
    DebtSettlementPayload.

    Mapping::

        riderId → rider_id
        tripId  → trip_id
    """
    out = dict(raw)
    if "riderId" in out and "rider_id" not in out:
        out["rider_id"] = out.pop("riderId")
    if "tripId" in out and "trip_id" not in out:
        out["trip_id"] = out.pop("tripId")
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
            request_context = event.get("requestContext") or {}
            route_key: str = event.get("routeKey") or request_context.get("routeKey") or ""
            action_type: str = _route_key_to_action(route_key).upper()

            raw_body: str = event.get("body") or request_context.get("body") or "{}"
            try:
                raw_payload: dict[str, Any] = json.loads(raw_body)
            except json.JSONDecodeError as exc:
                logger.warning("Malformed JSON body on route '%s': %s", route_key, exc)
                return _bad_request(f"Request body is not valid JSON: {exc}")

            if not action_type:
                action_hint = raw_payload.get("action") if isinstance(raw_payload, dict) else None
                if action_hint:
                    action_type = _route_key_to_action(str(action_hint)).upper()

            # Normalise camelCase HTTP client keys → snake_case model keys.
            if action_type == "APPLY_TRIP_FEE":
                payload: dict[str, Any] = _normalise_trip_fee_payload(raw_payload)
            elif action_type == "PROCESS_CANCELLATION":
                payload = _ensure_cancellation_transit_seconds(_normalise_cancellation_payload(raw_payload))
                if _missing_cancellation_transaction_markers(payload):
                    return {
                        "statusCode": 400,
                        "headers": {"Content-Type": "application/json"},
                        "body": "Missing mandatory transaction markers",
                    }
            elif action_type == "SETTLE_RIDER_DEBT":
                payload = _normalise_debt_settlement_payload(raw_payload)
            else:
                payload = raw_payload

            logger.info(
                "Ledger service invoked via API GW proxy: routeKey=%s → action_type=%s",
                route_key,
                action_type,
            )
        else:
            # Direct invocation — action_type and payload are top-level keys.
            action_type = event.get("action_type") or event.get("action") or ""
            action_type = str(action_type).upper()
            payload = event.get("payload", {})

            if not action_type and isinstance(payload, dict):
                action_hint = payload.get("action")
                if action_hint:
                    action_type = _route_key_to_action(str(action_hint)).upper()

            if action_type == "PROCESS_CANCELLATION" and isinstance(payload, dict):
                payload = _ensure_cancellation_transit_seconds(_normalise_cancellation_payload(payload))
                if _missing_cancellation_transaction_markers(payload):
                    return {
                        "statusCode": 400,
                        "headers": {"Content-Type": "application/json"},
                        "body": "Missing mandatory transaction markers",
                    }

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
