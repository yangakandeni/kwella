"""
tests/test_fleet_clearing.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Unit tests for Phase 19: Fleet Operational Clearing Rail.
"""

from __future__ import annotations

import sys
from typing import Any

import boto3
import pytest
from moto import mock_aws
from pydantic import ValidationError

from identity_service.schemas import VehicleOwnership


# ---------------------------------------------------------------------------
# Table provisioning helper
# ---------------------------------------------------------------------------

def _create_mock_table() -> Any:
    """Provision a moto-intercepted DynamoDB table matching production structure."""
    dynamodb = boto3.resource("dynamodb", region_name="af-south-1")
    table = dynamodb.create_table(
        TableName="kwella-core-test",
        KeySchema=[
            {"AttributeName": "PK", "KeyType": "HASH"},
            {"AttributeName": "SK", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "PK",      "AttributeType": "S"},
            {"AttributeName": "SK",      "AttributeType": "S"},
            {"AttributeName": "GSI1_PK", "AttributeType": "S"},
            {"AttributeName": "GSI1_SK", "AttributeType": "S"},
        ],
        GlobalSecondaryIndexes=[
            {
                "IndexName": "GSI1",
                "KeySchema": [
                    {"AttributeName": "GSI1_PK", "KeyType": "HASH"},
                    {"AttributeName": "GSI1_SK", "KeyType": "RANGE"},
                ],
                "Projection": {"ProjectionType": "ALL"},
                "ProvisionedThroughput": {"ReadCapacityUnits": 5, "WriteCapacityUnits": 5},
            }
        ],
        BillingMode="PROVISIONED",
        ProvisionedThroughput={"ReadCapacityUnits": 5, "WriteCapacityUnits": 5},
    )
    table.meta.client.get_waiter("table_exists").wait(TableName="kwella-core-test")
    return table


def _reload_clearing_house():
    """Force-reload database.client and clearing_house to bind to current moto context."""
    for mod_name in ("database.client", "ledger_service.clearing_house"):
        if mod_name in sys.modules:
            del sys.modules[mod_name]
    from ledger_service.clearing_house import get_settlement_recipient  # noqa: PLC0415
    return get_settlement_recipient


# ---------------------------------------------------------------------------
# Data Layer Schema Tests
# ---------------------------------------------------------------------------

def test_vehicle_ownership_validation():
    """Verify VehicleOwnership validator accepts valid prefixes and raises for invalid ones."""
    # Valid configurations
    o1 = VehicleOwnership(owner_id="FLEET#owner-123", status="ACTIVE")
    assert o1.owner_id == "FLEET#owner-123"
    assert o1.status == "ACTIVE"

    o2 = VehicleOwnership(owner_id="DRIVER#driver-456")
    assert o2.owner_id == "DRIVER#driver-456"

    # Invalid configurations
    with pytest.raises(ValidationError):
        VehicleOwnership(owner_id="USR#user-123")

    with pytest.raises(ValidationError):
        VehicleOwnership(owner_id="bare-id")


# ---------------------------------------------------------------------------
# Clearing House Route Logic Tests
# ---------------------------------------------------------------------------

@mock_aws
def test_get_settlement_recipient_routes_to_fleet_owner():
    """Assert that a vehicle mapped to a FLEET owner clears directly to the FLEET owner ID."""
    table = _create_mock_table()
    get_settlement_recipient = _reload_clearing_house()

    # Seed vehicle ownership association
    table.put_item(
        Item={
            "PK": "VEHICLE#CT-1001",
            "SK": "OWNERSHIP",
            "owner_id": "FLEET#fleet-alpha",
            "status": "ACTIVE",
        }
    )

    recipient = get_settlement_recipient("CT-1001")
    assert recipient == "FLEET#fleet-alpha"


@mock_aws
def test_get_settlement_recipient_routes_to_driver_owner():
    """Assert that an owner-operator vehicle maps to the registered DRIVER owner ID."""
    table = _create_mock_table()
    get_settlement_recipient = _reload_clearing_house()

    # Seed vehicle ownership association representing owner-operator
    table.put_item(
        Item={
            "PK": "VEHICLE#CT-1002",
            "SK": "OWNERSHIP",
            "owner_id": "DRIVER#driver-beta",
            "status": "ACTIVE",
        }
    )

    recipient = get_settlement_recipient("CT-1002")
    assert recipient == "DRIVER#driver-beta"


@mock_aws
def test_get_settlement_recipient_falls_back_to_driver_profile_when_inactive():
    """Assert fallback to active driver query if vehicle ownership mapping status is not ACTIVE."""
    table = _create_mock_table()
    get_settlement_recipient = _reload_clearing_house()

    # Seed inactive vehicle ownership record
    table.put_item(
        Item={
            "PK": "VEHICLE#CT-1003",
            "SK": "OWNERSHIP",
            "owner_id": "FLEET#fleet-alpha",
            "status": "INACTIVE",
        }
    )

    # Seed driver profile associated with the vehicle CT-1003 on GSI1
    table.put_item(
        Item={
            "PK": "USR#driver-gamma",
            "SK": "PROFILE",
            "phone": "+27821234567",
            "assigned_cata_sticker": "CT-1003",
            "GSI1_PK": "VEH#CT-1003",
            "GSI1_SK": "DRIVER",
        }
    )

    recipient = get_settlement_recipient("CT-1003")
    assert recipient == "DRIVER#driver-gamma"


@mock_aws
def test_get_settlement_recipient_falls_back_to_driver_profile_when_missing():
    """Assert fallback to active driver when no vehicle ownership record exists."""
    table = _create_mock_table()
    get_settlement_recipient = _reload_clearing_house()

    # Seed active driver profile mapping to CT-1004 on GSI1 without a VEHICLE# ownership record
    table.put_item(
        Item={
            "PK": "USR#driver-delta",
            "SK": "PROFILE",
            "phone": "+27821234567",
            "assigned_cata_sticker": "CT-1004",
            "GSI1_PK": "VEH#CT-1004",
            "GSI1_SK": "DRIVER",
        }
    )

    recipient = get_settlement_recipient("CT-1004")
    assert recipient == "DRIVER#driver-delta"


@mock_aws
def test_get_settlement_recipient_returns_driver_unknown_as_last_resort():
    """Assert DRIVER#UNKNOWN is returned if no ownership record or driver profile exists."""
    _create_mock_table()
    get_settlement_recipient = _reload_clearing_house()

    recipient = get_settlement_recipient("CT-9999")
    assert recipient == "DRIVER#UNKNOWN"
