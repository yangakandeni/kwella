"""
kwella — Bidding Engine Lambda Handler
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Real-time compute worker for the kwella WebSocket bidding plane.

Supported WebSocket route keys (dispatched by API Gateway WebSocket proxy):
  $connect          — Extract authorization, record connection telemetry, and save active connection session row.
  $disconnect       — Delete connection session metadata.
  sendBid           — Parse and extract particulars from Driver counter-offers.

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native syntax and type hints; no legacy typing imports (e.g. List, Dict).
  - boto3 resource/client initialized at module scope for connection pooling.
  - DynamoDB operations wrapped in explicit botocore.exceptions.ClientError exception handling.
  - Sourced from os.environ['KWELLA_TABLE_NAME'].
"""

from __future__ import annotations

import json
import logging
import os
from datetime import datetime, UTC
from typing import Any

import boto3
import botocore.exceptions

# Initialize Logger
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Environment Ingestion
_TABLE_NAME = os.environ.get("KWELLA_TABLE_NAME")
if not _TABLE_NAME:
    raise RuntimeError("Environment variable KWELLA_TABLE_NAME must be set")

_AWS_REGION = os.environ.get("AWS_REGION", "af-south-1")

# Connection-pooled DynamoDB Table resource at module scope
_dynamodb = boto3.resource("dynamodb", region_name=_AWS_REGION)
_table = _dynamodb.Table(_TABLE_NAME)


def get_table():
    """Return the module-scoped DynamoDB Table resource reference."""
    return _table


def _extract_auth_params(event: dict[str, Any]) -> str | None:
    """Extract authorization parameters from the query string or headers.

    Checks both the top-level keys and nested requestContext keys to ensure
    robust compatibility with various API Gateway integration configurations.
    """
    # 1. Inspect query string parameters
    qsp = event.get("queryStringParameters") or {}
    if not isinstance(qsp, dict):
        qsp = {}
    
    rc = event.get("requestContext") or {}
    rc_qsp = rc.get("queryStringParameters") or {}
    if not isinstance(rc_qsp, dict):
        rc_qsp = {}

    combined_qsp = {**rc_qsp, **qsp}
    for key in ("authorization", "auth", "token", "access_token"):
        for k, v in combined_qsp.items():
            if k.lower() == key:
                return v

    # 2. Inspect header parameters
    headers = event.get("headers") or {}
    if not isinstance(headers, dict):
        headers = {}
        
    rc_headers = rc.get("headers") or {}
    if not isinstance(rc_headers, dict):
        rc_headers = {}

    combined_headers = {**rc_headers, **headers}
    for key in ("authorization", "sec-websocket-protocol"):
        for k, v in combined_headers.items():
            if k.lower() == key:
                return v

    return None


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Primary Lambda handler for the kwella Bidding Engine WebSocket service.

    Extracts routeKey and connectionId, and routes to appropriate connection,
    disconnection, or bidding action handlers.
    """
    request_context = event.get("requestContext") or {}
    route_key = request_context.get("routeKey")
    connection_id = request_context.get("connectionId")

    logger.info(
        "Bidding engine invocation: routeKey=%s connectionId=%s",
        route_key,
        connection_id,
    )

    if not route_key or not connection_id:
        logger.warning("Invocation missing routeKey or connectionId in requestContext.")
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "ValidationError", "detail": "Missing routeKey or connectionId."})
        }

    table = get_table()

    try:
        if route_key == "$connect":
            auth_param = _extract_auth_params(event)
            timestamp = datetime.now(UTC).isoformat()

            # Active session metadata row key scheme
            item = {
                "PK": f"CONN#{connection_id}",
                "SK": "METADATA",
                "connected_at": timestamp,
            }
            if auth_param:
                item["auth_token"] = auth_param

            logger.info("Writing connection metadata item to DynamoDB for connectionId=%s", connection_id)
            table.put_item(Item=item)

            return {
                "statusCode": 200,
                "body": "Connected"
            }

        elif route_key == "$disconnect":
            logger.info("Removing connection metadata item from DynamoDB for connectionId=%s", connection_id)
            table.delete_item(
                Key={
                    "PK": f"CONN#{connection_id}",
                    "SK": "METADATA",
                }
            )
            return {
                "statusCode": 200,
                "body": "Disconnected"
            }

        elif route_key == "sendBid":
            body_str = event.get("body") or "{}"
            try:
                body = json.loads(body_str)
            except (json.JSONDecodeError, TypeError) as exc:
                logger.warning("Failed to parse JSON body for sendBid route on connectionId=%s: %s", connection_id, exc)
                return {
                    "statusCode": 400,
                    "body": json.dumps({"error": "ValidationError", "detail": "Request body must be valid JSON."})
                }

            # Extract the bid particulars
            bid_particulars = {
                "driver_id": body.get("driver_id") or body.get("driverId"),
                "rider_id": body.get("rider_id") or body.get("riderId"),
                "amount": body.get("amount") or body.get("counter_fare") or body.get("baseline_fare"),
                "estimated_pickup": body.get("estimated_pickup") or body.get("estimatedPickup"),
                "broadcast_pk": body.get("broadcast_pk") or body.get("broadcastPk"),
                "connection_id": connection_id,
            }

            logger.info("Received bid particulars on route sendBid: %s", bid_particulars)

            # Return a placeholder success block
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "status": "Success",
                    "message": "Bid received successfully (placeholder)",
                    "bid_particulars": bid_particulars
                })
            }

        else:
            logger.warning("Unsupported routeKey received: '%s'", route_key)
            return {
                "statusCode": 400,
                "body": json.dumps({
                    "error": "ValidationError",
                    "detail": f"Route key '{route_key}' is not supported."
                })
            }

    except botocore.exceptions.ClientError as exc:
        error_code = exc.response.get("Error", {}).get("Code", "Unknown")
        error_message = exc.response.get("Error", {}).get("Message", "DynamoDB ClientError")
        logger.error(
            "DynamoDB ClientError [%s] on routeKey %s for connectionId=%s: %s",
            error_code,
            route_key,
            connection_id,
            exc,
        )
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": "InfrastructureError",
                "detail": f"Database operation failed [{error_code}]: {error_message}"
            })
        }
    except Exception as exc:
        logger.error(
            "Unexpected exception on routeKey %s for connectionId=%s: %s",
            route_key,
            connection_id,
            exc,
            exc_info=True,
        )
        return {
            "statusCode": 500,
            "body": json.dumps({
                "error": "ServerError",
                "detail": f"An unexpected system error occurred: {type(exc).__name__}"
            })
        }
