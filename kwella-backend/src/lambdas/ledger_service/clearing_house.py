"""
src/lambdas/ledger_service/clearing_house.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Fleet Operational Clearing House logic.
"""

from __future__ import annotations

import logging
import botocore.exceptions
from boto3.dynamodb.conditions import Key

from database.client import get_table

logger = logging.getLogger(__name__)


def get_settlement_recipient(vehicle_id: str) -> str:
    """Determine the recipient of 100% of a vehicle's gross earnings.

    If a vehicle ownership association exists in DynamoDB with status 'ACTIVE',
    returns the fleet owner's profile target string (e.g. FLEET#<owner_id> or DRIVER#<owner_id>).
    Otherwise, defaults to the active driver assigned to the vehicle on the GSI1 index.

    Args:
        vehicle_id: The vehicle identifier/sticker ID.

    Returns:
        The target profile settlement string (e.g., "FLEET#123", "DRIVER#abc").
    """
    table = get_table()

    # 1. Lookup vehicle ownership mapping:
    #    PK = VEHICLE#<vehicle_id>
    #    SK = OWNERSHIP
    pk = f"VEHICLE#{vehicle_id}"
    sk = "OWNERSHIP"

    try:
        response = table.get_item(Key={"PK": pk, "SK": sk})
        item = response.get("Item")
        if item and item.get("status") == "ACTIVE" and item.get("owner_id"):
            owner_id = item["owner_id"]
            logger.info(
                "Clearing recipient resolved via ownership map: vehicle_id=%s -> owner_id=%s",
                vehicle_id,
                owner_id,
            )
            return owner_id
    except botocore.exceptions.ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error(
            "DynamoDB client error [%s] during vehicle ownership lookup for %s: %s",
            error_code,
            vehicle_id,
            exc,
        )

    # 2. Default to active driver of the vehicle via GSI1 index:
    #    GSI1_PK = VEH#<vehicle_id>
    #    GSI1_SK = DRIVER
    gsi1_pk = f"VEH#{vehicle_id}"
    gsi1_sk = "DRIVER"

    try:
        response = table.query(
            IndexName="GSI1",
            KeyConditionExpression=Key("GSI1_PK").eq(gsi1_pk) & Key("GSI1_SK").eq(gsi1_sk),
        )
        items = response.get("Items", [])
        if items:
            driver_item = items[0]
            # Driver profile has PK = USR#<driver_id>
            driver_pk = driver_item.get("PK", "")
            if driver_pk.startswith("USR#"):
                driver_id = driver_pk[4:]
                recipient = f"DRIVER#{driver_id}"
                logger.info(
                    "Defaulting clearing recipient to active driver: vehicle_id=%s -> driver_id=%s",
                    vehicle_id,
                    driver_id,
                )
                return recipient
    except botocore.exceptions.ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error(
            "DynamoDB client error [%s] during active driver query for %s: %s",
            error_code,
            vehicle_id,
            exc,
        )

    # If no ownership record and no active driver is found, fall back to a safe default
    logger.warning("No ownership mapping or active driver found for vehicle_id=%s", vehicle_id)
    return "DRIVER#UNKNOWN"
