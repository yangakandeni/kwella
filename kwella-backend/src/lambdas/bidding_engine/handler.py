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
from decimal import Decimal

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

# Optional SNS Platform Application ARN for push fallback delivery.
# This is used to create or target device endpoints for FCM tokens.
_SNS_PLATFORM_APPLICATION_ARN = os.environ.get("KWELLA_SNS_PLATFORM_APPLICATION_ARN")

# Spatial matching radius (metres) for requestTrip proximity filtering.
_TRIP_MATCH_RADIUS_M: float = 5000.0

# Ride offer TTL broadcast to matching drivers (seconds).
_RIDE_OFFER_TTL_SECONDS: int = 15

# Connection-pooled DynamoDB Table resource at module scope
_dynamodb = boto3.resource("dynamodb", region_name=_AWS_REGION)
_table = _dynamodb.Table(_TABLE_NAME)
_dynamodb_client = boto3.client("dynamodb", region_name=_AWS_REGION)


def get_table():
    """Return the module-scoped DynamoDB Table resource reference."""
    return _table


def _resolve_driver_fcm_token(table: Any, driver_pk: str, telemetry_record: dict[str, Any]) -> str | None:
    """Resolve a driver's FCM token from telemetry or profile/device config records."""
    token = telemetry_record.get("fcm_token")
    if isinstance(token, str) and token:
        return token

    for sk in ("PROFILE", "DEVICE_CONFIG"):
        profile_response = table.get_item(Key={"PK": driver_pk, "SK": sk})
        profile_item = profile_response.get("Item")
        if isinstance(profile_item, dict):
            token = profile_item.get("fcm_token")
            if isinstance(token, str) and token:
                return token

    return None


def _send_fcm_push_via_sns(fcm_token: str, trip_id: str, base_fare: Any) -> None:
    """Publish a high-priority FCM push payload through AWS SNS as a fallback."""
    if not _SNS_PLATFORM_APPLICATION_ARN:
        logger.debug("SNS fallback skipped because KWELLA_SNS_PLATFORM_APPLICATION_ARN is not configured.")
        return

    sns_client = boto3.client("sns", region_name=_AWS_REGION)
    try:
        endpoint_response = sns_client.create_platform_endpoint(
            PlatformApplicationArn=_SNS_PLATFORM_APPLICATION_ARN,
            Token=fcm_token,
        )
        endpoint_arn = endpoint_response.get("EndpointArn")
        if not endpoint_arn:
            raise RuntimeError("SNS create_platform_endpoint did not return an EndpointArn")

        push_payload = {
            "GCM": json.dumps({
                "priority": "high",
                "data": {
                    "action": "rideOfferAvailable",
                    "tripId": trip_id,
                    "base_fare": str(base_fare) if base_fare is not None else "",
                    "click_action": "FLUTTER_NOTIFICATION_CLICK",
                },
            })
        }

        sns_client.publish(
            TargetArn=endpoint_arn,
            MessageStructure="json",
            Message=json.dumps(push_payload),
        )
        logger.info(
            "SNS push fallback sent for tripId=%s endpointArn=%s",
            trip_id,
            endpoint_arn,
        )
    except botocore.exceptions.ClientError as exc:
        error_code = exc.response.get("Error", {}).get("Code", "Unknown")
        logger.warning(
            "SNS fallback publish failed for tripId=%s token=%s: %s",
            trip_id,
            fcm_token,
            error_code,
        )
    except Exception as exc:
        logger.warning(
            "SNS fallback publish unexpected failure for tripId=%s token=%s: %s",
            trip_id,
            fcm_token,
            exc,
        )


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

            # Extract userId from query string to pre-seed the TELEMETRY record
            # with the current connection_id. This ensures requestTrip can dispatch
            # a rideOfferAvailable even before the first updateLocation call.
            qsp = (event.get("queryStringParameters") or {})
            user_id_param: str | None = qsp.get("userId") or qsp.get("userid")

            if user_id_param:
                item["user_id"] = user_id_param
                # If it's a rider, store a GSI1_PK so sendBid can query it efficiently
                if user_id_param.startswith("rider-") or user_id_param.upper().startswith("RIDER"):
                    item["GSI1_PK"] = f"RIDER#{user_id_param}"
                    item["GSI1_SK"] = timestamp

            logger.info("Writing connection metadata item to DynamoDB for connectionId=%s", connection_id)
            table.put_item(Item=item)

            if user_id_param and user_id_param.upper() == "DRIVER":
                # userId=DRIVER is the mock sim token; skip seeding (no real driverId).
                pass
            elif user_id_param and not user_id_param.upper().startswith(("RIDER", "USR#")):
                # Seed TELEMETRY with the fresh connection_id so spatial scans
                # from requestTrip can post to this WebSocket immediately.
                driver_telemetry_pk = f"DRIVER#{user_id_param}"
                try:
                    table.update_item(
                        Key={"PK": driver_telemetry_pk, "SK": "TELEMETRY"},
                        UpdateExpression="SET #cid = :cid, #ua = :ua",
                        ExpressionAttributeNames={"#cid": "connection_id", "#ua": "updated_at"},
                        ExpressionAttributeValues={":cid": connection_id, ":ua": timestamp},
                    )
                    logger.info(
                        "Pre-seeded connection_id on TELEMETRY for driverId=%s connectionId=%s",
                        user_id_param,
                        connection_id,
                    )
                except Exception as seed_exc:  # noqa: BLE001
                    logger.warning(
                        "Could not pre-seed TELEMETRY connection_id for userId=%s: %s",
                        user_id_param,
                        seed_exc,
                    )

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

            driver_id: str | None = body.get("driver_id") or body.get("driverId")
            rider_id: str | None = body.get("rider_id") or body.get("riderId")
            trip_id: str | None = body.get("tripId") or body.get("trip_id")
            bid_amount = body.get("amount") or body.get("counter_fare") or body.get("baseline_fare")

            logger.info(
                "sendBid received: driverId=%s riderId=%s tripId=%s amount=%s",
                driver_id, rider_id, trip_id, bid_amount,
            )

            # Persist the bid record so selectBid can look it up later.
            if driver_id and trip_id:
                table.put_item(Item={
                    "PK": f"BID#{trip_id}",
                    "SK": f"DRIVER#{driver_id}",
                    "driver_id": driver_id,
                    "rider_id": rider_id,
                    "trip_id": trip_id,
                    "amount": str(bid_amount) if bid_amount is not None else "0",
                    "driver_connection_id": connection_id,
                    "status": "PENDING",
                    "created_at": datetime.now(UTC).isoformat(),
                })

            # Initialize API Gateway client for WebSocket pushes.
            apigw_client: Any = None
            if _APIGW_ENDPOINT:
                apigw_client = boto3.client(
                    "apigatewaymanagementapi",
                    endpoint_url=_APIGW_ENDPOINT,
                    region_name=_AWS_REGION,
                )

            # Push driverBidReceived to the rider's active WebSocket connection.
            # Look up the rider's connection_id via their TELEMETRY record.
            rider_conn_id: str | None = None
            if rider_id and apigw_client:
                # Rider connection is stored in CONN#<connectionId>/METADATA with
                # the userId query param. Scan active connections for the rider.
                try:
                    rider_conn_resp = table.query(
                        IndexName="GSI1",
                        KeyConditionExpression="GSI1_PK = :rpk",
                        ExpressionAttributeValues={":rpk": f"RIDER#{rider_id}"},
                    )
                    rider_items = rider_conn_resp.get("Items", [])
                    if rider_items:
                        rider_conn_id = rider_items[0].get("connection_id")
                except Exception as lookup_exc:  # noqa: BLE001
                    logger.warning("Could not look up rider connection for riderId=%s: %s", rider_id, lookup_exc)

            # If GSI1 lookup failed, fall back to scanning CONN# records for this rider.
            if not rider_conn_id and rider_id and apigw_client:
                try:
                    conn_scan = table.scan(
                        FilterExpression="SK = :sk AND #uid = :uid",
                        ExpressionAttributeNames={"#uid": "user_id"},
                        ExpressionAttributeValues={":sk": "METADATA", ":uid": rider_id},
                        ConsistentRead=True,
                    )
                    conn_items = conn_scan.get("Items", [])
                    for ci in conn_items:
                        pk = ci.get("PK", "")
                        if pk.startswith("CONN#"):
                            rider_conn_id = pk.removeprefix("CONN#")
                            break
                except Exception as scan_exc:  # noqa: BLE001
                    logger.warning("CONN scan for riderId=%s failed: %s", rider_id, scan_exc)

            if rider_conn_id and apigw_client:
                bid_notification = json.dumps({
                    "action": "driverBidReceived",
                    "tripId": trip_id,
                    "driverId": driver_id,
                    "amount": bid_amount,
                    "driver_connection_id": connection_id,
                }).encode("utf-8")
                try:
                    apigw_client.post_to_connection(
                        ConnectionId=rider_conn_id,
                        Data=bid_notification,
                    )
                    logger.info(
                        "Dispatched driverBidReceived to rider connectionId=%s for tripId=%s",
                        rider_conn_id, trip_id,
                    )
                except botocore.exceptions.ClientError as notify_exc:
                    logger.warning(
                        "Failed to push driverBidReceived to riderConnectionId=%s: %s",
                        rider_conn_id, notify_exc,
                    )
            else:
                logger.warning(
                    "Could not resolve rider WebSocket connection for riderId=%s tripId=%s — skipping push",
                    rider_id, trip_id,
                )

            # Return success response
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "status": "Success",
                    "message": "Bid received and dispatched to rider.",
                    "tripId": trip_id,
                    "driverId": driver_id,
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

            update_expression_parts.append("#cid = :cid")
            expression_attr_names["#cid"] = "connection_id"
            expression_attr_values[":cid"] = connection_id

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

        elif route_key == "confirmArrival":
            raw_body = event.get("body")
            if raw_body:
                try:
                    payload = json.loads(raw_body)
                except (json.JSONDecodeError, TypeError) as exc:
                    logger.warning(
                        "Failed to parse JSON body for confirmArrival route on connectionId=%s: %s",
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

            driver_id = payload.get("driverId")
            trip_id = payload.get("tripId")
            final_bid_amount = payload.get("final_bid_amount")

            if not driver_id or not isinstance(driver_id, str):
                return {
                    "statusCode": 400,
                    "body": json.dumps({
                        "error": "ValidationError",
                        "detail": "Missing or invalid required field 'driverId'.",
                    }),
                }
            if not trip_id or not isinstance(trip_id, str):
                return {
                    "statusCode": 400,
                    "body": json.dumps({
                        "error": "ValidationError",
                        "detail": "Missing or invalid required field 'tripId'.",
                    }),
                }
            if not isinstance(final_bid_amount, (int, float, Decimal)) or isinstance(final_bid_amount, bool):
                return {
                    "statusCode": 400,
                    "body": json.dumps({
                        "error": "ValidationError",
                        "detail": "Missing or invalid required field 'final_bid_amount'.",
                    }),
                }

            # Safely convert to Decimal for accurate math
            amount_decimal = Decimal(str(final_bid_amount))
            net_earnings = (amount_decimal * Decimal("0.85")).quantize(Decimal("0.01"))

            try:
                logger.info(
                    "Executing payout transact_write_items for driverId=%s tripId=%s final_bid_amount=%s",
                    driver_id,
                    trip_id,
                    final_bid_amount,
                )
                _dynamodb_client.transact_write_items(
                    TransactItems=[
                        {
                            "Update": {
                                "TableName": _TABLE_NAME,
                                "Key": {
                                    "PK": {"S": f"TRIP#{trip_id}"},
                                    "SK": {"S": "METADATA"},
                                },
                                "UpdateExpression": "SET #status = :completed",
                                "ConditionExpression": "#status = :accepted OR #status = :arrived",
                                "ExpressionAttributeNames": {
                                    "#status": "status",
                                },
                                "ExpressionAttributeValues": {
                                    ":completed": {"S": "COMPLETED"},
                                    ":accepted": {"S": "ACCEPTED"},
                                    ":arrived": {"S": "ARRIVED"},
                                },
                            }
                        },
                        {
                            "Update": {
                                "TableName": _TABLE_NAME,
                                "Key": {
                                    "PK": {"S": f"DRIVER#{driver_id}"},
                                    "SK": {"S": "WALLET"},
                                },
                                "UpdateExpression": (
                                    "SET balance = if_not_exists(balance, :zero) + :payout, "
                                    "daily_total = if_not_exists(daily_total, :zero) + :payout"
                                ),
                                "ExpressionAttributeValues": {
                                    ":payout": {"N": str(net_earnings)},
                                    ":zero": {"N": "0.00"},
                                },
                            }
                        },
                    ]
                )
            except botocore.exceptions.ClientError as exc:
                error_code = exc.response.get("Error", {}).get("Code", "Unknown")
                if error_code == "TransactionCanceledException":
                    reasons = exc.response.get("CancellationReasons", [])
                    logger.warning(
                        "Transaction canceled for tripId=%s driverId=%s. Reasons: %s",
                        trip_id,
                        driver_id,
                        reasons,
                    )
                    return {
                        "statusCode": 400,
                        "body": json.dumps({
                            "error": "ValidationError",
                            "detail": "Payout settlement failed. Trip status must be ACCEPTED or ARRIVED.",
                        }),
                    }
                raise

            # Transaction succeeded. Read driver's wallet to get updated daily total.
            wallet_res = table.get_item(
                Key={
                    "PK": f"DRIVER#{driver_id}",
                    "SK": "WALLET",
                }
            )
            wallet_item = wallet_res.get("Item") or {}
            updated_daily_total = wallet_item.get("daily_total")
            if updated_daily_total is not None:
                updated_daily_total = float(updated_daily_total)
            else:
                updated_daily_total = float(net_earnings)

            return {
                "statusCode": 200,
                "body": json.dumps({
                    "status": "WalletSettled",
                    "tripId": trip_id,
                    "net_earnings": float(net_earnings),
                    "currency": "ZAR",
                    "updated_daily_total": updated_daily_total,
                }),
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
                ConsistentRead=True,
            )
            driver_records: list[dict[str, Any]] = scan_response.get("Items", [])

            # Handle DynamoDB pagination for large fleets.
            while "LastEvaluatedKey" in scan_response:
                scan_response = table.scan(
                    FilterExpression="SK = :sk",
                    ExpressionAttributeValues={":sk": "TELEMETRY"},
                    ExclusiveStartKey=scan_response["LastEvaluatedKey"],
                    ConsistentRead=True,
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

                driver_offline_or_suspended = False
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
                        error_code = dispatch_exc.response.get("Error", {}).get("Code", "Unknown")
                        logger.warning(
                            "Failed to dispatch offer to connectionId=%s [%s]; marking offline/suspended.",
                            driver_conn_id,
                            error_code,
                        )
                        driver_offline_or_suspended = True
                else:
                    logger.debug(
                        "WebSocket dispatch skipped for driverId=%s (no endpoint or connectionId).",
                        driver_id,
                    )
                    driver_offline_or_suspended = True

                if driver_offline_or_suspended:
                    fcm_token = _resolve_driver_fcm_token(table, driver_pk, record)
                    if fcm_token:
                        _send_fcm_push_via_sns(
                            fcm_token=fcm_token,
                            trip_id=trip_id,
                            base_fare=suggested_fare,
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
