"""
tests/test_ledger_service.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Isolated unit tests for the kwella Cancellation & Platform Fee Ledger Service Lambda.

Coverage:
  PROCESS_CANCELLATION — Atomically applies debt to rider and holiday to driver.
  PROCESS_CANCELLATION — Rejects invalid penalty amounts (e.g. > R30.00).
  APPLY_TRIP_FEE      — Standard fee applied (no holiday balance).
  APPLY_TRIP_FEE      — Complete fee holiday applied (holiday balance >= fee).
  APPLY_TRIP_FEE      — Partial fee holiday applied (holiday balance < fee).
  APPLY_TRIP_FEE      — Retries on optimistic lock collision.
"""

from __future__ import annotations

import json
import sys
from decimal import Decimal
from typing import Any

import boto3
import pytest
from moto import mock_aws
from botocore.exceptions import ClientError


# ---------------------------------------------------------------------------
# Provisioning helpers
# ---------------------------------------------------------------------------

def _create_mock_table() -> Any:
    """Provision a moto-intercepted table for testing."""
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


def _reload_ledger_handler():
    """Force re-import the ledger handler to refresh the database client."""
    for mod_name in ("database.client", "ledger_service.cancellation_handler", "ledger_service.handler"):
        if mod_name in sys.modules:
            del sys.modules[mod_name]
    import ledger_service.handler as handler  # noqa: PLC0415
    return handler


# ---------------------------------------------------------------------------
# PROCESS_CANCELLATION
# ---------------------------------------------------------------------------

@mock_aws
def test_process_cancellation_applies_debt_and_fee_holiday():
    """PROCESS_CANCELLATION must atomically create the rider debt item and
    the zero-commission driver credit entry for a late cancellation.
    """
    table = _create_mock_table()
    handler = _reload_ledger_handler()

    event = {
        "action_type": "PROCESS_CANCELLATION",
        "payload": {
            "rider_id": "rider-1",
            "driver_id": "driver-1",
            "trip_id": "trip-1",
            "amount": "25.50",
            "driver_in_transit_seconds": 181,
            "timestamp": "2026-06-21T10:15:00Z",
        }
    }

    response = handler.lambda_handler(event, None)
    assert response["statusCode"] == 200

    rider_item = table.get_item(Key={"PK": "USER#rider-1", "SK": "DEBT#trip-1"})["Item"]
    assert rider_item["amount"] == Decimal("25.50")
    assert rider_item["status"] == "PENDING_SETTLEMENT"
    assert rider_item["reason"] == "LATE_CANCELLATION"

    driver_item = table.get_item(
        Key={"PK": "USER#driver-1", "SK": "LEDGER#2026-06-21T10:15:00Z"}
    )["Item"]
    assert driver_item["amount"] == Decimal("25.50")
    assert driver_item["platform_commission_rate"] == Decimal("0.00")
    assert driver_item["platform_commission_amount"] == Decimal("0.00")


@mock_aws
def test_process_cancellation_rejects_penalty_amount_exceeding_max_cap():
    """PROCESS_CANCELLATION must reject penalty amounts greater than R30.00."""
    _create_mock_table()
    handler = _reload_ledger_handler()

    event = {
        "action_type": "PROCESS_CANCELLATION",
        "payload": {
            "rider_id": "rider-1",
            "driver_id": "driver-1",
            "trip_id": "trip-1",
            "amount": "30.01",  # exceeds R30 cap
            "driver_in_transit_seconds": 181,
        }
    }

    response = handler.lambda_handler(event, None)
    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert body["error"] == "ValidationError"


# ---------------------------------------------------------------------------
# APPLY_TRIP_FEE
# ---------------------------------------------------------------------------

@mock_aws
def test_apply_trip_fee_no_holiday_charges_standard_fee():
    """APPLY_TRIP_FEE with fee_holiday_balance == 0 must calculate the 10%
    platform fee and charge it in full, leaving fee_holiday_balance at 0.
    """
    table = _create_mock_table()
    handler = _reload_ledger_handler()

    table.put_item(Item={"PK": "USR#driver-1", "SK": "PROFILE", "fee_holiday_balance": Decimal("0.00")})

    event = {
        "action_type": "APPLY_TRIP_FEE",
        "payload": {
            "driver_id": "driver-1",
            "fare_amount": "150.00"
        }
    }

    response = handler.lambda_handler(event, None)
    assert response["statusCode"] == 200
    body = json.loads(response["body"])

    assert body["platform_fee"] == 15.0
    assert body["applied_fee_holiday"] == 0.0
    assert body["actual_fee_charged"] == 15.0
    assert body["remaining_fee_holiday_balance"] == 0.0

    # Ensure DB balance remains 0
    driver_item = table.get_item(Key={"PK": "USR#driver-1", "SK": "PROFILE"})["Item"]
    assert driver_item["fee_holiday_balance"] == Decimal("0.00")


@mock_aws
def test_apply_trip_fee_with_sufficient_holiday_waives_fee_entirely():
    """APPLY_TRIP_FEE where fee_holiday_balance >= platform_fee must waive the
    entire fee and decrement the balance accordingly.
    """
    table = _create_mock_table()
    handler = _reload_ledger_handler()

    table.put_item(Item={"PK": "USR#driver-1", "SK": "PROFILE", "fee_holiday_balance": Decimal("30.00")})

    event = {
        "action_type": "APPLY_TRIP_FEE",
        "payload": {
            "driver_id": "driver-1",
            "fare_amount": "150.00"  # 10% platform fee = R15.00
        }
    }

    response = handler.lambda_handler(event, None)
    assert response["statusCode"] == 200
    body = json.loads(response["body"])

    assert body["platform_fee"] == 15.0
    assert body["applied_fee_holiday"] == 15.0
    assert body["actual_fee_charged"] == 0.0
    assert body["remaining_fee_holiday_balance"] == 15.0

    # Ensure DB balance was decremented to 15.00
    driver_item = table.get_item(Key={"PK": "USR#driver-1", "SK": "PROFILE"})["Item"]
    assert driver_item["fee_holiday_balance"] == Decimal("15.00")


@mock_aws
def test_apply_trip_fee_with_partial_holiday_waives_fee_partially():
    """APPLY_TRIP_FEE where fee_holiday_balance < platform_fee must waive only
    up to the balance, decrementing the balance to 0.00, and charge the remaining fee.
    """
    table = _create_mock_table()
    handler = _reload_ledger_handler()

    table.put_item(Item={"PK": "USR#driver-1", "SK": "PROFILE", "fee_holiday_balance": Decimal("10.00")})

    event = {
        "action_type": "APPLY_TRIP_FEE",
        "payload": {
            "driver_id": "driver-1",
            "fare_amount": "150.00"  # 10% platform fee = R15.00
        }
    }

    response = handler.lambda_handler(event, None)
    assert response["statusCode"] == 200
    body = json.loads(response["body"])

    assert body["platform_fee"] == 15.0
    assert body["applied_fee_holiday"] == 10.0
    assert body["actual_fee_charged"] == 5.0
    assert body["remaining_fee_holiday_balance"] == 0.0

    # Ensure DB balance was decremented to 0.00
    driver_item = table.get_item(Key={"PK": "USR#driver-1", "SK": "PROFILE"})["Item"]
    assert driver_item["fee_holiday_balance"] == Decimal("0.00")


@mock_aws
def test_apply_trip_fee_retries_on_collision_and_succeeds(mocker):
    """APPLY_TRIP_FEE must retry when update_item raises a ConditionalCheckFailedException
    due to a concurrent balance update.
    """
    table = _create_mock_table()
    handler = _reload_ledger_handler()

    table.put_item(Item={"PK": "USR#driver-1", "SK": "PROFILE", "fee_holiday_balance": Decimal("30.00")})

    import database.client
    target_table = database.client.get_table()

    # Spy or mock update_item to throw ConditionalCheckFailedException on first call
    original_update_item = target_table.update_item
    call_count = 0

    def mock_update_item(*args, **kwargs):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            raise ClientError(
                {"Error": {"Code": "ConditionalCheckFailedException", "Message": "Conditional check failed"}},
                "UpdateItem",
            )
        return original_update_item(*args, **kwargs)

    mocker.patch.object(target_table, "update_item", side_effect=mock_update_item)

    event = {
        "action_type": "APPLY_TRIP_FEE",
        "payload": {
            "driver_id": "driver-1",
            "fare_amount": "150.00"
        }
    }

    response = handler.lambda_handler(event, None)
    assert response["statusCode"] == 200
    body = json.loads(response["body"])

    assert body["platform_fee"] == 15.0
    assert body["applied_fee_holiday"] == 15.0
    assert body["actual_fee_charged"] == 0.0
    assert body["remaining_fee_holiday_balance"] == 15.0
    assert call_count == 2  # Proves a retry occurred and succeeded
