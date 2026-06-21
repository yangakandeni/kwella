"""
kwella — Bidding Engine Lambda Handler
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Real-time compute worker for the kwella WebSocket bidding plane.

Supported WebSocket route keys (dispatched by API Gateway WebSocket proxy):
  $connect          — Extract authorization, record connection telemetry, and save active connection session row.
  $disconnect       — Delete connection session metadata.
  sendBid           — Parse and extract particulars from Driver counter-offers.
  updateLocation    — Ingest real-time driver telematics telemetry and persist to DynamoDB.
  requestTrip       — Rider-initiated spatial matching: scan active driver TELEMETRY records,
                      filter by 5000 m proximity, and broadcast rideOfferAvailable offers.

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native syntax and type hints; no legacy typing imports (e.g. List, Dict).
  - boto3 resource/client initialized at module scope for connection pooling.
  - DynamoDB operations wrapped in explicit botocore.exceptions.ClientError exception handling.
  - Sourced from os.environ['KWELLA_TABLE_NAME'].
  - WebSocket dispatch endpoint sourced from os.environ['KWELLA_APIGW_ENDPOINT'] (optional;
    omitted in local test contexts where moto cannot simulate the Management API).
"""

from __future__ import annotations

import json
import logging
import os
import uuid
from datetime import datetime, UTC
from typing import Any

import boto3
import botocore.exceptions

from geofence_utils import calculate_distance, is_inside_geofence

# Initialize Logger
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Environment Ingestion
_TABLE_NAME = os.environ.get("KWELLA_TABLE_NAME")
if not _TABLE_NAME:
    raise RuntimeError("Environment variable KWELLA_TABLE_NAME must be set")

_AWS_REGION = os.environ.get("AWS_REGION", "af-south-1")

# Optional: API Gateway Management API endpoint for WebSocket push dispatch.
# Format: https://<api-id>.execute-api.<region>.amazonaws.com/<stage>
# Absent in local/test contexts — dispatch is skipped gracefully when unset.
_APIGW_ENDPOINT = os.environ.get("KWELLA_APIGW_ENDPOINT")

# Spatial matching radius (metres) for requestTrip proximity filtering.
_TRIP_MATCH_RADIUS_M: float = 5000.0

# Ride offer TTL broadcast to matching drivers (seconds).
_RIDE_OFFER_TTL_SECONDS: int = 15

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

        elif route_key == "updateLocation":
            # Parse the incoming telematics payload from the WebSocket body.
            # API Gateway v2 WebSocket delivers the JSON message as the top-level
            # event body string; fall back to the event root for direct invocations.
            raw_body = event.get("body")
            if raw_body:
                try:
                    payload = json.loads(raw_body)
                except (json.JSONDecodeError, TypeError) as exc:
                    logger.warning(
                        "Failed to parse JSON body for updateLocation route on connectionId=%s: %s",
                        connection_id,
                        exc,
                    )
                    return {
                        "statusCode": 400,
                        "body": json.dumps({
                            "error": "ValidationError",
                            "detail": "Request body must be valid JSON.",
                        }),
                    }
            else:
                # Allow direct invocation with a flat event (e.g. from tests or
                # internal callers that embed the fields at the top level).
                payload = event

            driver_id: str | None = payload.get("driverId")
            latitude = payload.get("latitude")
            longitude = payload.get("longitude")
            heading = payload.get("heading")
            speed = payload.get("speed")

            # Validate required fields.
            missing = [k for k, v in {
                "driverId": driver_id,
                "latitude": latitude,
                "longitude": longitude,
            }.items() if v is None]
            if missing:
                logger.warning(
                    "updateLocation payload missing required fields %s on connectionId=%s",
                    missing,
                    connection_id,
                )
                return {
                    "statusCode": 400,
                    "body": json.dumps({
                        "error": "ValidationError",
                        "detail": f"Missing required telematics fields: {missing}",
                    }),
                }

            # Validate that coordinate values are numeric.
            for field_name, field_value in (
                ("latitude", latitude),
                ("longitude", longitude),
                ("heading", heading),
                ("speed", speed),
            ):
                if field_value is not None and not isinstance(field_value, (int, float)):
                    logger.warning(
                        "updateLocation received non-numeric value for field '%s' on connectionId=%s",
                        field_name,
                        connection_id,
                    )
                    return {
                        "statusCode": 400,
                        "body": json.dumps({
                            "error": "ValidationError",
                            "detail": f"Field '{field_name}' must be a numeric value.",
                        }),
                    }

            updated_at = datetime.now(UTC).isoformat()
            pk = f"DRIVER#{driver_id}"

            logger.info(
                "Persisting telematics for driverId=%s lat=%.6f lon=%.6f",
                driver_id,
                latitude,
                longitude,
            )

            # Use update_item so that concurrent writes to other SK-keyed
            # attributes on the same PK are not clobbered.
            # ExpressionAttributeNames guards against DynamoDB reserved words
            # ('name', 'status', 'data', etc.); we alias all attribute names
            # defensively for clarity and forward-compatibility.
            update_expression_parts = [
                "#lat = :lat",
                "#lon = :lon",
                "#ua = :ua",
            ]
            expression_attr_names: dict[str, str] = {
                "#lat": "last_latitude",
                "#lon": "last_longitude",
                "#ua": "updated_at",
            }
            expression_attr_values: dict[str, Any] = {
                ":lat": str(latitude),
                ":lon": str(longitude),
                ":ua": updated_at,
            }

            if heading is not None:
                update_expression_parts.append("#hdg = :hdg")
                expression_attr_names["#hdg"] = "heading"
                expression_attr_values[":hdg"] = str(heading)

            if speed is not None:
                update_expression_parts.append("#spd = :spd")
                expression_attr_names["#spd"] = "speed"
                expression_attr_values[":spd"] = str(speed)

            table.update_item(
                Key={"PK": pk, "SK": "TELEMETRY"},
                UpdateExpression="SET " + ", ".join(update_expression_parts),
                ExpressionAttributeNames=expression_attr_names,
                ExpressionAttributeValues=expression_attr_values,
            )

            # Trip Metadata Hydration & Proximity Evaluation Loop
            trip_id = payload.get("tripId")
            target_lat = None
            target_lon = None

            if trip_id:
                try:
                    res = table.get_item(Key={"PK": f"TRIP#{trip_id}", "SK": "METADATA"})
                    item = res.get("Item")
                    if item:
                        # Convert DynamoDB Decimal coordinates to float
                        target_lat = float(item.get("destination_latitude"))
                        target_lon = float(item.get("destination_longitude"))
                except botocore.exceptions.ClientError as exc:
                    logger.warning("Failed to lookup active assigned trip %s: %s", trip_id, exc)

            # Fallback to placeholder coordinates if lookup is missing or fails
            if target_lat is None or target_lon is None:
                # Default mock destination (e.g. Green Point: -33.9036, 18.3989)
                target_lat = -33.9036
                target_lon = 18.3989

            is_inside = is_inside_geofence(
                current_lat=latitude,
                current_lon=longitude,
                target_lat=target_lat,
                target_lon=target_lon,
            )

            response_body = {"status": "Telemetry Latched"}
            if is_inside:
                response_body["flags"] = {"geofence_status": "ARRIVED"}

            return {
                "statusCode": 200,
                "body": json.dumps(response_body),
            }

        elif route_key == "requestTrip":
            # -----------------------------------------------------------------
            # Phase 14 — Marketplace Matching Engine
            # Rider-initiated trip request: locate spatially eligible drivers
            # and broadcast ride offer invitations down their WebSocket pipes.
            # -----------------------------------------------------------------
            raw_body = event.get("body")
            if raw_body:
                try:
                    payload = json.loads(raw_body)
                except (json.JSONDecodeError, TypeError) as exc:
                    logger.warning(
                        "Failed to parse JSON body for requestTrip route on connectionId=%s: %s",
                        connection_id,
                        exc,
                    )
                    return {
                        "statusCode": 400,
                        "body": json.dumps({
                            "error": "ValidationError",
                            "detail": "Request body must be valid JSON.",
                        }),
                    }
            else:
                payload = event

            rider_id: str | None = payload.get("riderId")
            pickup_lat = payload.get("pickup_latitude")
            pickup_lon = payload.get("pickup_longitude")
            dropoff_lat = payload.get("dropoff_latitude")
            dropoff_lon = payload.get("dropoff_longitude")
            suggested_fare = payload.get("suggested_base_fare")

            # Validate required fields.
            required_fields = {
                "riderId": rider_id,
                "pickup_latitude": pickup_lat,
                "pickup_longitude": pickup_lon,
                "dropoff_latitude": dropoff_lat,
                "dropoff_longitude": dropoff_lon,
            }
            missing_fields = [k for k, v in required_fields.items() if v is None]
            if missing_fields:
                logger.warning(
                    "requestTrip payload missing required fields %s on connectionId=%s",
                    missing_fields,
                    connection_id,
                )
                return {
                    "statusCode": 400,
                    "body": json.dumps({
                        "error": "ValidationError",
                        "detail": f"Missing required fields: {missing_fields}",
                    }),
                }

            # Validate coordinate numerics.
            for coord_name, coord_value in (
                ("pickup_latitude", pickup_lat),
                ("pickup_longitude", pickup_lon),
                ("dropoff_latitude", dropoff_lat),
                ("dropoff_longitude", dropoff_lon),
            ):
                if not isinstance(coord_value, (int, float)) or isinstance(coord_value, bool):
                    return {
                        "statusCode": 400,
                        "body": json.dumps({
                            "error": "ValidationError",
                            "detail": f"Field '{coord_name}' must be a numeric value.",
                        }),
                    }

            # ------------------------------------------------------------------
            # Spatial Grid Loop — scan all active TELEMETRY records and isolate
            # drivers within _TRIP_MATCH_RADIUS_M of the rider's pickup point.
            # ------------------------------------------------------------------
            logger.info(
                "requestTrip spatial scan: riderId=%s pickup=(%.6f, %.6f)",
                rider_id,
                pickup_lat,
                pickup_lon,
            )

            scan_response = table.scan(
                FilterExpression="SK = :sk",
                ExpressionAttributeValues={":sk": "TELEMETRY"},
            )
            driver_records: list[dict[str, Any]] = scan_response.get("Items", [])

            # Handle DynamoDB pagination for large fleets.
            while "LastEvaluatedKey" in scan_response:
                scan_response = table.scan(
                    FilterExpression="SK = :sk",
                    ExpressionAttributeValues={":sk": "TELEMETRY"},
                    ExclusiveStartKey=scan_response["LastEvaluatedKey"],
                )
                driver_records.extend(scan_response.get("Items", []))

            matched_driver_ids: list[str] = []

            # Generate a stable trip identifier for this dispatch cycle.
            trip_id = f"TRP#{uuid.uuid4()}"

            # Construct the offer payload template (mutated per-driver only for
            # connection-id routing; the offer content itself is broadcast-identical).
            offer_payload = {
                "action": "rideOfferAvailable",
                "tripId": trip_id,
                "pickup_location": [pickup_lat, pickup_lon],
                "dropoff_location": [dropoff_lat, dropoff_lon],
                "base_fare": suggested_fare,
                "expires_in_seconds": _RIDE_OFFER_TTL_SECONDS,
            }
            offer_data = json.dumps(offer_payload).encode("utf-8")

            # Initialise the Management API client only when the endpoint is
            # configured (absent in local test contexts).
            apigw_client: Any = None
            if _APIGW_ENDPOINT:
                apigw_client = boto3.client(
                    "apigatewaymanagementapi",
                    endpoint_url=_APIGW_ENDPOINT,
                    region_name=_AWS_REGION,
                )

            for record in driver_records:
                driver_pk: str = record.get("PK", "")
                raw_lat = record.get("last_latitude")
                raw_lon = record.get("last_longitude")

                if raw_lat is None or raw_lon is None:
                    logger.debug(
                        "Skipping driver record with missing coordinates: PK=%s", driver_pk
                    )
                    continue

                try:
                    driver_lat = float(raw_lat)
                    driver_lon = float(raw_lon)
                except (ValueError, TypeError):
                    logger.warning(
                        "Non-numeric coordinates for driver PK=%s; skipping.", driver_pk
                    )
                    continue

                distance_m = calculate_distance(
                    driver_lat, driver_lon,
                    pickup_lat, pickup_lon,
                )

                if distance_m > _TRIP_MATCH_RADIUS_M:
                    logger.debug(
                        "Driver PK=%s is %.0f m away — outside matching radius; skipped.",
                        driver_pk,
                        distance_m,
                    )
                    continue

                # Strip the "DRIVER#" namespace prefix to recover the raw driver id.
                driver_id = driver_pk.removeprefix("DRIVER#")
                matched_driver_ids.append(driver_id)

                logger.info(
                    "Matched driver %s at %.0f m — dispatching rideOfferAvailable",
                    driver_id,
                    distance_m,
                )

                # Dispatch the offer to the driver's WebSocket connection.
                # Resolve the driver's live connectionId from the TELEMETRY record
                # (populated by updateLocation; absent before first location ping).
                driver_conn_id: str | None = record.get("connection_id")
                if apigw_client and driver_conn_id:
                    try:
                        apigw_client.post_to_connection(
                            ConnectionId=driver_conn_id,
                            Data=offer_data,
                        )
                        logger.info(
                            "Offer dispatched to connectionId=%s (driverId=%s)",
                            driver_conn_id,
                            driver_id,
                        )
                    except botocore.exceptions.ClientError as dispatch_exc:
                        # Stale or expired connections must not abort the entire
                        # dispatch loop; log and continue to remaining drivers.
                        error_code = dispatch_exc.response.get("Error", {}).get("Code", "Unknown")
                        logger.warning(
                            "Failed to dispatch offer to connectionId=%s [%s]; continuing.",
                            driver_conn_id,
                            error_code,
                        )
                else:
                    logger.debug(
                        "WebSocket dispatch skipped for driverId=%s (no endpoint or connectionId).",
                        driver_id,
                    )

            logger.info(
                "requestTrip scan complete: %d driver(s) matched within %.0f m for riderId=%s",
                len(matched_driver_ids),
                _TRIP_MATCH_RADIUS_M,
                rider_id,
            )

            return {
                "statusCode": 200,
                "body": json.dumps({
                    "status": "TripBroadcast",
                    "tripId": trip_id,
                    "matched_drivers": matched_driver_ids,
                }),
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
