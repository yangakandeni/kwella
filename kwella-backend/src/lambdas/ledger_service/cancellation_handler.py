"""Late-cancellation transaction writer for the hybrid payment rail.

Single-table ledger entities introduced by this module:

  Rider debt state
    PK = USER#<rider_id>
    SK = DEBT#<trip_id>
    Attributes = amount, timestamp, status=PENDING_SETTLEMENT,
                 reason=LATE_CANCELLATION

  Driver compensating credit
    PK = USER#<driver_id>
    SK = LEDGER#<timestamp>
    Attributes = amount, timestamp, trip_id, rider_id,
                 platform_commission_amount=0.00,
                 platform_commission_rate=0.00,
                 reason=LATE_CANCELLATION
"""

from __future__ import annotations

import logging
import os
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Literal

import boto3
import botocore.exceptions
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator

from database.client import get_table

logger = logging.getLogger(__name__)

_MIN_TRANSIT_SECONDS = 180

_dynamodb_client = boto3.client(
    "dynamodb",
    region_name=os.environ.get("AWS_REGION", "af-south-1"),
)


class CancellationLedgerPayload(BaseModel):
    """Validated input for the late-cancellation ledger transaction."""

    model_config = ConfigDict(
        extra="forbid",
        strict=False,
    )

    rider_id: str = Field(..., min_length=1, description="Bare or USER#/USR# prefixed rider ID.")
    driver_id: str = Field(..., min_length=1, description="Bare or USER#/USR# prefixed driver ID.")
    trip_id: str = Field(..., min_length=1, description="Trip identifier used in the debt sort key.")
    amount: Decimal = Field(
        ...,
        gt=Decimal("0.00"),
        le=Decimal("30.00"),
        description="Flat late-cancellation compensation amount in ZAR.",
    )
    timestamp: datetime | None = Field(
        default=None,
        description="UTC cancellation timestamp; defaults to now when omitted.",
    )
    driver_in_transit_seconds: int | None = Field(
        default=None,
        ge=0,
        description="Precomputed driver transit duration in seconds.",
    )
    driver_en_route_at: datetime | None = Field(
        default=None,
        description="UTC timestamp when the driver started in-transit movement.",
    )
    cancelled_at: datetime | None = Field(
        default=None,
        description="UTC timestamp when the rider cancelled the trip.",
    )
    reason: Literal["LATE_CANCELLATION"] = Field(
        default="LATE_CANCELLATION",
        description="Immutable debt reason code for this rail.",
    )

    @field_validator("rider_id", "driver_id")
    @classmethod
    def strip_user_prefix(cls, value: str) -> str:
        for prefix in ("USER#", "USR#"):
            if value.startswith(prefix):
                return value[len(prefix):]
        return value

    @model_validator(mode="after")
    def validate_timing_inputs(self) -> "CancellationLedgerPayload":
        if self.driver_in_transit_seconds is not None:
            return self
        if self.driver_en_route_at is None or self.cancelled_at is None:
            raise ValueError(
                "Either driver_in_transit_seconds or both driver_en_route_at and cancelled_at are required."
            )
        return self

    def effective_timestamp(self) -> datetime:
        reference = self.timestamp or self.cancelled_at or datetime.now(tz=timezone.utc)
        if reference.tzinfo is None:
            return reference.replace(tzinfo=timezone.utc)
        return reference.astimezone(timezone.utc)

    def transit_seconds(self) -> int:
        if self.driver_in_transit_seconds is not None:
            return self.driver_in_transit_seconds
        assert self.driver_en_route_at is not None
        assert self.cancelled_at is not None

        started_at = self.driver_en_route_at
        cancelled_at = self.cancelled_at
        if started_at.tzinfo is None:
            started_at = started_at.replace(tzinfo=timezone.utc)
        if cancelled_at.tzinfo is None:
            cancelled_at = cancelled_at.replace(tzinfo=timezone.utc)
        return max(int((cancelled_at - started_at).total_seconds()), 0)


def _isoformat_utc(timestamp: datetime) -> str:
    return timestamp.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def build_cancellation_transact_items(payload: CancellationLedgerPayload, table_name: str) -> list[dict[str, Any]]:
    """Build the exact TransactWriteItems payload for the late-cancellation rail."""
    event_timestamp = _isoformat_utc(payload.effective_timestamp())

    rider_debt_item = {
        "Put": {
            "TableName": table_name,
            "Item": {
                "PK": {"S": f"USER#{payload.rider_id}"},
                "SK": {"S": f"DEBT#{payload.trip_id}"},
                "entity_type": {"S": "RIDER_DEBT"},
                "amount": {"N": str(payload.amount)},
                "timestamp": {"S": event_timestamp},
                "status": {"S": "PENDING_SETTLEMENT"},
                "reason": {"S": payload.reason},
                "trip_id": {"S": payload.trip_id},
                "driver_id": {"S": payload.driver_id},
            },
            "ConditionExpression": "attribute_not_exists(PK) AND attribute_not_exists(SK)",
        }
    }

    driver_credit_item = {
        "Put": {
            "TableName": table_name,
            "Item": {
                "PK": {"S": f"USER#{payload.driver_id}"},
                "SK": {"S": f"LEDGER#{event_timestamp}"},
                "entity_type": {"S": "DRIVER_COMPENSATING_CREDIT"},
                "amount": {"N": str(payload.amount)},
                "timestamp": {"S": event_timestamp},
                "trip_id": {"S": payload.trip_id},
                "rider_id": {"S": payload.rider_id},
                "reason": {"S": payload.reason},
                "platform_commission_amount": {"N": "0.00"},
                "platform_commission_rate": {"N": "0.00"},
                "entry_direction": {"S": "CREDIT"},
            },
            "ConditionExpression": "attribute_not_exists(PK) AND attribute_not_exists(SK)",
        }
    }

    return [rider_debt_item, driver_credit_item]


def process_cancellation(payload: CancellationLedgerPayload) -> dict[str, Any]:
    """Apply the late-cancellation debt and zero-commission driver credit atomically."""
    transit_seconds = payload.transit_seconds()
    if transit_seconds <= _MIN_TRANSIT_SECONDS:
        return {
            "message": "No late-cancellation ledger entries applied.",
            "trip_id": payload.trip_id,
            "driver_in_transit_seconds": transit_seconds,
            "late_cancellation_applied": False,
        }

    table_name = get_table().name
    transact_items = build_cancellation_transact_items(payload, table_name)

    try:
        _dynamodb_client.transact_write_items(TransactItems=transact_items)
    except botocore.exceptions.ClientError as exc:
        error = exc.response.get("Error", {})
        error_code = error.get("Code", "Unknown")
        logger.error(
            "Late-cancellation transact_write_items failed [%s] for trip=%s rider=%s driver=%s",
            error_code,
            payload.trip_id,
            payload.rider_id,
            payload.driver_id,
            exc_info=True,
        )
        raise

    return {
        "message": "Late-cancellation debt and driver credit applied successfully.",
        "trip_id": payload.trip_id,
        "rider_id": payload.rider_id,
        "driver_id": payload.driver_id,
        "amount": payload.amount,
        "driver_in_transit_seconds": transit_seconds,
        "late_cancellation_applied": True,
    }


__all__ = [
    "CancellationLedgerPayload",
    "ValidationError",
    "build_cancellation_transact_items",
    "process_cancellation",
]