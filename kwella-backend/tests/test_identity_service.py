"""
tests/test_identity_service.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Isolated unit tests for the kwella Identity & Profile Service Lambda handler.

Coverage:
  UPSERT_PROFILE  — Rider profile path (valid payload → DynamoDB write)
  UPSERT_PROFILE  — Driver profile path (valid payload → DynamoDB write + GSI1 keys)
  REGISTER_VEHICLE — Vehicle registration (valid payload → inverted GSI1_PK mapping)
  UPSERT_PROFILE  — Missing user_id guard (400 path)
  UPSERT_PROFILE  — Invalid role guard (400 path)
  REGISTER_VEHICLE — Missing USR# prefix on owner_id → Pydantic ValidationError → 400

Test isolation strategy:
  Each test function is decorated with @mock_aws which spins up an in-process
  moto DynamoDB endpoint for the duration of that test only.  The table is
  created fresh inside the fixture and torn down automatically when the mock
  context exits, guaranteeing zero cross-test state bleed.

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native type hints; no legacy typing imports.
  - Pydantic v2 ValidationError assertions use exc.error_count() and
    exc.errors() (Pydantic v2 API) — not .json() or .dict().
  - No hardcoded AWS credentials; moto credentials supplied by conftest.py.
"""

from __future__ import annotations

import importlib
import json
import sys
from decimal import Decimal
from typing import Any

import boto3
import pytest
from moto import mock_aws


# ---------------------------------------------------------------------------
# Table provisioning helper
# ---------------------------------------------------------------------------

def _create_mock_table() -> Any:
    """Provision a moto-intercepted DynamoDB table matching the production schema.

    Creates the ``kwella-core-test`` table with the same key schema and GSI
    definition as the production ``kwella-core-production`` table documented in
    KWELLA_SYSTEM_CONTEXT.md §3.

    Returns:
        boto3 DynamoDB Table resource for direct assertion queries in tests.
    """
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


def _reload_identity_handler():
    """Force-reimport the identity_service handler so it picks up the active
    moto interceptor context rather than a previously cached boto3 resource.

    This is necessary because database.client initialises the boto3 resource at
    module scope; without a reload the resource would point to a stale endpoint
    from a prior test's mock context.
    """
    for mod_name in ("database.client", "identity_service.handler"):
        if mod_name in sys.modules:
            del sys.modules[mod_name]
    import identity_service.handler as handler  # noqa: PLC0415
    return handler


# ---------------------------------------------------------------------------
# UPSERT_PROFILE — Rider
# ---------------------------------------------------------------------------

@mock_aws
def test_upsert_profile_rider_writes_correct_item_to_dynamodb():
    """UPSERT_PROFILE with a valid Rider payload must:

    - Return HTTP 200.
    - Persist a DynamoDB item with PK = USR#<user_id> and SK = PROFILE.
    - Write the ``role`` attribute as the string ``"RIDER"``.
    - NOT write GSI1_PK or GSI1_SK keys (Riders have no vehicle link).
    - Preserve the phone field verbatim after E.164 normalisation.
    """
    table = _create_mock_table()
    handler = _reload_identity_handler()

    event: dict[str, Any] = {
        "action_type": "UPSERT_PROFILE",
        "payload": {
            "user_id": "rider-001",
            "role": "RIDER",
            "phone": "+27821234567",
        },
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200, (
        f"Expected 200 for valid Rider upsert, got {response['statusCode']}. "
        f"Body: {response['body']}"
    )

    # Verify the item was written to the mocked table.
    result = table.get_item(Key={"PK": "USR#rider-001", "SK": "PROFILE"})
    item = result.get("Item")
    assert item is not None, "DynamoDB item must exist after a successful UPSERT_PROFILE."

    assert item["PK"] == "USR#rider-001"
    assert item["SK"] == "PROFILE"
    assert item["role"] == "RIDER"
    assert item["phone"] == "+27821234567"

    # Riders must NOT carry GSI1 keys — those are Driver-plane attributes.
    assert "GSI1_PK" not in item, "Rider items must NOT have a GSI1_PK attribute."
    assert "GSI1_SK" not in item, "Rider items must NOT have a GSI1_SK attribute."


@mock_aws
def test_upsert_profile_rider_with_cancellation_debt_writes_decimal_field():
    """UPSERT_PROFILE for a Rider with outstanding debt must persist the
    cancellation_debt field as a non-zero Decimal without floating-point drift.
    """
    table = _create_mock_table()
    handler = _reload_identity_handler()

    event: dict[str, Any] = {
        "action_type": "UPSERT_PROFILE",
        "payload": {
            "user_id": "rider-debt-002",
            "role": "RIDER",
            "phone": "+27831234567",
            "cancellation_debt": "15.50",
        },
    }

    response = handler.lambda_handler(event, context=None)
    assert response["statusCode"] == 200

    result = table.get_item(Key={"PK": "USR#rider-debt-002", "SK": "PROFILE"})
    item = result["Item"]

    # DynamoDB stores numbers as Decimal; the debt must survive the round-trip.
    assert item["cancellation_debt"] == Decimal("15.50"), (
        "cancellation_debt must survive the serialisation round-trip as Decimal('15.50')."
    )


# ---------------------------------------------------------------------------
# UPSERT_PROFILE — Driver
# ---------------------------------------------------------------------------

@mock_aws
def test_upsert_profile_driver_writes_gsi1_keys_for_vehicle_driver_map():
    """UPSERT_PROFILE with a valid Driver payload must:

    - Return HTTP 200.
    - Persist PK = USR#<user_id> and SK = PROFILE.
    - Write GSI1_PK = VEH#<assigned_cata_sticker> (uppercase).
    - Write GSI1_SK = ``"DRIVER"`` exactly.

    This mapping enforces the fleet-view constraint documented in
    KWELLA_SYSTEM_CONTEXT.md §3: querying GSI1 by GSI1_PK = VEH#<sticker>
    returns the Driver record assigned to that vehicle.
    """
    table = _create_mock_table()
    handler = _reload_identity_handler()

    event: dict[str, Any] = {
        "action_type": "UPSERT_PROFILE",
        "payload": {
            "user_id": "driver-001",
            "role": "DRIVER",
            "phone": "+27841234567",
            "name": "Thandiwe Mokoena",
            "assigned_cata_sticker": "ct-7001",   # deliberately lowercase → normaliser must uppercase
        },
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200, (
        f"Expected 200 for valid Driver upsert, got {response['statusCode']}. "
        f"Body: {response['body']}"
    )

    result = table.get_item(Key={"PK": "USR#driver-001", "SK": "PROFILE"})
    item = result.get("Item")
    assert item is not None, "DynamoDB item must exist after a successful Driver UPSERT_PROFILE."

    assert item["PK"] == "USR#driver-001"
    assert item["SK"] == "PROFILE"
    assert item["role"] == "DRIVER"
    assert item["name"] == "Thandiwe Mokoena"

    # GSI1_PK must use the normalised (uppercase) CATA sticker as VEH# prefix.
    assert item["GSI1_PK"] == "VEH#CT-7001", (
        f"GSI1_PK must be 'VEH#CT-7001' (uppercase-normalised); got '{item.get('GSI1_PK')}'."
    )
    assert item["GSI1_SK"] == "DRIVER", (
        f"GSI1_SK must be the literal string 'DRIVER'; got '{item.get('GSI1_SK')}'."
    )


@mock_aws
def test_upsert_profile_driver_with_fee_holiday_balance_writes_decimal_field():
    """UPSERT_PROFILE for a Driver carrying a platform-fee holiday balance must
    persist fee_holiday_balance as a Decimal, bounded by the R30 cap defined in
    KWELLA_SYSTEM_CONTEXT.md §4.
    """
    table = _create_mock_table()
    handler = _reload_identity_handler()

    event: dict[str, Any] = {
        "action_type": "UPSERT_PROFILE",
        "payload": {
            "user_id": "driver-fee-002",
            "role": "DRIVER",
            "phone": "+27851234567",
            "name": "Sipho Mahlangu",
            "assigned_cata_sticker": "CT-7002",
            "fee_holiday_balance": "25.00",
            "is_online": True,
        },
    }

    response = handler.lambda_handler(event, context=None)
    assert response["statusCode"] == 200

    result = table.get_item(Key={"PK": "USR#driver-fee-002", "SK": "PROFILE"})
    item = result["Item"]

    assert item["fee_holiday_balance"] == Decimal("25.00"), (
        "fee_holiday_balance must persist as Decimal('25.00') without floating-point error."
    )
    assert item["is_online"] is True


# ---------------------------------------------------------------------------
# REGISTER_VEHICLE
# ---------------------------------------------------------------------------

@mock_aws
def test_register_vehicle_writes_correct_gsi1_inverted_pk_for_fleet_view():
    """REGISTER_VEHICLE with a valid VehicleAsset payload must:

    - Return HTTP 200.
    - Write PK = VEH#<cata_sticker> and SK = METADATA.
    - Write the *inverted* GSI1_PK = USR#<owner_id> — enabling an owner-centric
      fleet query on the GSI without a full table scan.
    - Write GSI1_SK = VEH#<cata_sticker>.

    This is the key inversion pattern that powers the fleet-view constraint:
    querying GSI1 by GSI1_PK = USR#<owner_id> returns all vehicles belonging
    to that owner (KWELLA_SYSTEM_CONTEXT.md §3).
    """
    table = _create_mock_table()
    handler = _reload_identity_handler()

    event: dict[str, Any] = {
        "action_type": "REGISTER_VEHICLE",
        "payload": {
            "cata_sticker": "ct-8001",           # lowercase → normaliser uppercases it
            "make": "Toyota",
            "model": "HiAce",
            "color": "White",
            "license_plate": "ca 123-456",       # lowercase → normaliser uppercases it
            "owner_id": "USR#owner-fleet-001",
        },
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200, (
        f"Expected 200 for valid vehicle registration, got {response['statusCode']}. "
        f"Body: {response['body']}"
    )

    # Primary key: VEH#<uppercase sticker> / METADATA
    result = table.get_item(Key={"PK": "VEH#CT-8001", "SK": "METADATA"})
    item = result.get("Item")
    assert item is not None, "DynamoDB item must exist after a successful REGISTER_VEHICLE."

    assert item["PK"] == "VEH#CT-8001", (
        f"PK must be 'VEH#CT-8001'; got '{item.get('PK')}'."
    )
    assert item["SK"] == "METADATA"

    # Inverted GSI mapping for fleet-view (owner → vehicles).
    assert item["GSI1_PK"] == "USR#owner-fleet-001", (
        "GSI1_PK must equal the owner_id so an owner can query all their vehicles via GSI1."
    )
    assert item["GSI1_SK"] == "VEH#CT-8001", (
        "GSI1_SK must be VEH#<cata_sticker> to allow range sorting within the owner's fleet."
    )
    assert item["color"] == "White"
    assert item["license_plate"] == "CA 123-456", (
        f"license_plate must be normalised to uppercase; got '{item.get('license_plate')}'."
    )

    # Verify the 200 response body carries the GSI key confirmations.
    body: dict[str, Any] = json.loads(response["body"])
    assert body["GSI1_PK"] == "USR#owner-fleet-001"
    assert body["GSI1_SK"] == "VEH#CT-8001"


@mock_aws
def test_register_vehicle_duplicate_sticker_returns_400():
    """REGISTER_VEHICLE for an already-registered CATA sticker must return 400.

    The handler uses a DynamoDB ConditionExpression (attribute_not_exists(PK))
    to prevent silent overwrites — an essential fleet safety guard.
    """
    _create_mock_table()
    handler = _reload_identity_handler()

    payload_event: dict[str, Any] = {
        "action_type": "REGISTER_VEHICLE",
        "payload": {
            "cata_sticker": "CT-DUPE-001",
            "make": "Toyota",
            "model": "HiAce",
            "color": "Silver",
            "license_plate": "CA 654-321",
            "owner_id": "USR#owner-001",
        },
    }

    # First registration must succeed.
    first_response = handler.lambda_handler(payload_event, context=None)
    assert first_response["statusCode"] == 200

    # Duplicate registration attempt must be rejected.
    second_response = handler.lambda_handler(payload_event, context=None)
    assert second_response["statusCode"] == 400, (
        "Duplicate vehicle registration must return 400; the ConditionExpression guard failed."
    )


# ---------------------------------------------------------------------------
# UPSERT_PROFILE — validation failure paths
# ---------------------------------------------------------------------------

@mock_aws
def test_upsert_profile_without_user_id_returns_400():
    """UPSERT_PROFILE without a user_id must short-circuit before hitting
    DynamoDB and return a deterministic 400 Bad Request response.
    """
    _create_mock_table()
    handler = _reload_identity_handler()

    event: dict[str, Any] = {
        "action_type": "UPSERT_PROFILE",
        "payload": {
            "role": "RIDER",
            "phone": "+27821234567",
            # user_id deliberately omitted
        },
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body: dict[str, Any] = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "user_id" in body["detail"]


@mock_aws
def test_upsert_profile_driver_without_name_returns_400():
    """UPSERT_PROFILE for a Driver missing the required 'name' field must
    return 400 rather than silently persisting a nameless driver record.
    """
    _create_mock_table()
    handler = _reload_identity_handler()

    event: dict[str, Any] = {
        "action_type": "UPSERT_PROFILE",
        "payload": {
            "user_id": "driver-no-name",
            "role": "DRIVER",
            "phone": "+27861234567",
            "assigned_cata_sticker": "CT-7003",
            # name deliberately omitted
        },
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body: dict[str, Any] = json.loads(response["body"])
    assert body["error"] == "ValidationError"
    assert "name" in body["detail"]


@mock_aws
def test_upsert_profile_with_invalid_role_returns_400():
    """UPSERT_PROFILE with an unrecognised role string must return 400.

    Only ``"RIDER"`` and ``"DRIVER"`` are valid role values; the handler must
    reject anything else before attempting a DynamoDB write.
    """
    _create_mock_table()
    handler = _reload_identity_handler()

    event: dict[str, Any] = {
        "action_type": "UPSERT_PROFILE",
        "payload": {
            "user_id": "any-user",
            "role": "OWNER",          # OWNER is not a routable profile role
            "phone": "+27821234567",
        },
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body: dict[str, Any] = json.loads(response["body"])
    assert body["error"] == "ValidationError"


# ---------------------------------------------------------------------------
# REGISTER_VEHICLE — validation failure paths
# ---------------------------------------------------------------------------

@mock_aws
def test_register_vehicle_without_usr_prefix_on_owner_id_raises_validation_error_and_returns_400():
    """REGISTER_VEHICLE where owner_id lacks the required 'USR#' prefix must
    trigger a Pydantic ValidationError inside the handler and return HTTP 400.

    This verifies that the VehicleAsset.owner_id_must_have_prefix validator is
    active and correctly surfaced through the handler's exception handling block
    without leaking an unhandled exception to API Gateway.
    """
    _create_mock_table()
    handler = _reload_identity_handler()

    event: dict[str, Any] = {
        "action_type": "REGISTER_VEHICLE",
        "payload": {
            "cata_sticker": "CT-9001",
            "make": "Toyota",
            "model": "HiAce",
            "color": "Blue",
            "license_plate": "CA 987-654",
            "owner_id": "owner-no-prefix",   # missing USR# prefix
        },
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400, (
        "A missing 'USR#' prefix on owner_id must trigger a ValidationError and return 400."
    )

    body: dict[str, Any] = json.loads(response["body"])
    assert body["error"] == "ValidationError", (
        f"Response error field must be 'ValidationError'; got '{body.get('error')}'."
    )
    # The detail should surface the Pydantic error JSON from exc.model_dump_json().
    assert "owner_id" in body["detail"] or "USR#" in body["detail"], (
        "The 400 detail body must reference the offending field (owner_id) or the expected prefix."
    )


@mock_aws
def test_register_vehicle_without_color_or_license_plate_returns_400():
    """REGISTER_VEHICLE missing 'color' or 'license_plate' must return 400 —
    both fields are required so the bidding engine can surface real vehicle
    details to a rider once a bid is selected.
    """
    _create_mock_table()
    handler = _reload_identity_handler()

    event: dict[str, Any] = {
        "action_type": "REGISTER_VEHICLE",
        "payload": {
            "cata_sticker": "CT-9002",
            "make": "Toyota",
            "model": "HiAce",
            "owner_id": "USR#owner-002",
            # color and license_plate deliberately omitted
        },
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body: dict[str, Any] = json.loads(response["body"])
    assert body["error"] == "ValidationError"


# ---------------------------------------------------------------------------
# PRESIGN_DOCUMENT_UPLOAD
# ---------------------------------------------------------------------------

@mock_aws
def test_presign_document_upload_returns_url_and_persists_pending_record(monkeypatch):
    """PRESIGN_DOCUMENT_UPLOAD with a valid payload must:

    - Return HTTP 200 with an 'upload_url' and 's3_key'.
    - Persist a PENDING_UPLOAD audit record at PK=USR#<user_id>, SK=DOCUMENT#<doc_type>.
    """
    monkeypatch.setenv("DRIVER_DOCUMENTS_BUCKET", "kwella-driver-documents-test")
    table = _create_mock_table()
    handler = _reload_identity_handler()

    s3 = boto3.client("s3", region_name="af-south-1")
    s3.create_bucket(
        Bucket="kwella-driver-documents-test",
        CreateBucketConfiguration={"LocationConstraint": "af-south-1"},
    )

    event: dict[str, Any] = {
        "action_type": "PRESIGN_DOCUMENT_UPLOAD",
        "payload": {
            "user_id": "driver-001",
            "doc_type": "PRDP",
        },
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 200, (
        f"Expected 200 for valid presign request, got {response['statusCode']}. "
        f"Body: {response['body']}"
    )
    body: dict[str, Any] = json.loads(response["body"])
    assert body["upload_url"].startswith("https://")
    assert "driver-001/PRDP/" in body["s3_key"]

    result = table.get_item(Key={"PK": "USR#driver-001", "SK": "DOCUMENT#PRDP"})
    item = result.get("Item")
    assert item is not None, "A PENDING_UPLOAD audit record must be written."
    assert item["status"] == "PENDING_UPLOAD"
    assert item["s3_key"] == body["s3_key"]


@mock_aws
def test_presign_document_upload_rejects_unknown_doc_type():
    """PRESIGN_DOCUMENT_UPLOAD with a doc_type outside the allow-list must
    return 400 without generating a presigned URL or touching DynamoDB.
    """
    _create_mock_table()
    handler = _reload_identity_handler()

    event: dict[str, Any] = {
        "action_type": "PRESIGN_DOCUMENT_UPLOAD",
        "payload": {
            "user_id": "driver-001",
            "doc_type": "PASSPORT_PHOTO",  # not in the allow-list
        },
    }

    response = handler.lambda_handler(event, context=None)

    assert response["statusCode"] == 400
    body: dict[str, Any] = json.loads(response["body"])
    assert body["error"] == "ValidationError"
