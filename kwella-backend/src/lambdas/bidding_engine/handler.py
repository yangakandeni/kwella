"""
kwella — Bidding Engine Lambda Handler
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Real-time compute worker for the kwella WebSocket bidding plane.

Supported WebSocket route keys (dispatched by API Gateway WebSocket proxy):

  $connect          — Log connection telemetry; accept the WebSocket handshake.
  $disconnect       — Log disconnection telemetry; clean up any ephemeral state.
  BROADCAST_REQUEST — Parse an inbound Rider broadcast containing location,
                      target route strings, passenger counts, and a baseline
                      fare; persist the open-bid record to DynamoDB.
  SUBMIT_BID        — Accept a Driver counter-offer, validate it through the
                      shared Pydantic layer, and write the bid record to
                      DynamoDB for the originating Rider to evaluate.

API Gateway WebSocket proxy event structure::

    {
        "requestContext": {
            "routeKey":     "$connect" | "$disconnect" | "BROADCAST_REQUEST" | "SUBMIT_BID",
            "connectionId": "<opaque string assigned by API GW>",
            "eventType":    "CONNECT" | "DISCONNECT" | "MESSAGE",
            "domainName":   "<api-id>.execute-api.<region>.amazonaws.com",
            "stage":        "production"
        },
        "body": "<JSON-encoded string for MESSAGE events, null for connect/disconnect>"
    }

Governance compliance (KWELLA_CODE_GOVERNANCE.md):
  - Python 3.12 native syntax throughout; no legacy typing imports.
  - boto3 clients are consumed via the module-level get_table() helper
    (connection pooled outside the handler for warm-invocation reuse).
  - All DynamoDB I/O is wrapped in explicit botocore.exceptions.ClientError
    try-except blocks.
  - No hardcoded secrets or table names; sourced from os.environ via client.py.
  - Pydantic v2 only: model_dump(), model_dump_json(), ValidationError —
    no .dict() or .json() permitted.
  - boto3 ApiGatewayManagementApi client initialised at call time because the
    endpoint URL is dynamic (derived from the inbound event), but the DynamoDB
    resource is held at module scope.
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

# Shared-layer imports — resolved by the Lambda layer at runtime.
from database.client import get_table
from models.schemas import DriverProfile, RiderProfile  # noqa: F401 (re-exported for type consumers)

# ---------------------------------------------------------------------------
# Module-level initialisation
# boto3 DynamoDB resource is connection-pooled at module scope per governance §2.
# The ApiGatewayManagementApi client cannot be pooled at module scope because
# its endpoint URL is event-derived; it is constructed lazily inside each
# route handler that needs it.
# ---------------------------------------------------------------------------

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

_AWS_REGION: str = os.environ.get("AWS_REGION", "af-south-1")


# ---------------------------------------------------------------------------
# Pydantic v2 request models — bidding plane
# ---------------------------------------------------------------------------

class BroadcastRequestPayload(BaseModel):
    """Validated inbound payload for the BROADCAST_REQUEST route.

    A Rider broadcasts this when they are ready to solicit Driver bids for
    a trip. It captures everything a Driver needs to formulate a counter-offer.

    Attributes:
        rider_id:         USR#<RiderId> — the originating rider's DynamoDB PK.
        pickup_location:  Human-readable or coordinate string for the pickup point.
        destination:      Target route / destination string.
        passenger_count:  Number of passengers (1 – 7 for a 7-seater amaphela).
        baseline_fare:    Rider's opening fare offer in ZAR (Decimal for ledger
                          fidelity; must be a positive non-zero amount).
        connection_id:    API Gateway connectionId of the broadcasting Rider.
    """

    model_config = ConfigDict(
        extra="forbid",
        strict=False,
        populate_by_name=True,
    )

    rider_id: str = Field(
        ...,
        description="USR#<RiderId> of the broadcasting rider.",
        min_length=5,
    )
    pickup_location: str = Field(
        ...,
        description="Pickup point — coordinate pair or human-readable address.",
        min_length=1,
        max_length=512,
    )
    destination: str = Field(
        ...,
        description="Target route / destination string.",
        min_length=1,
        max_length=512,
    )
    passenger_count: int = Field(
        ...,
        description="Number of passengers (1–7).",
        ge=1,
        le=7,
    )
    baseline_fare: Decimal = Field(
        ...,
        description="Rider's opening fare offer in ZAR. Must be > 0.",
        gt=Decimal("0.00"),
    )
    connection_id: str = Field(
        ...,
        description="API Gateway connectionId of the originating Rider.",
        min_length=1,
    )

    @field_validator("rider_id")
    @classmethod
    def rider_id_must_have_prefix(cls, value: str) -> str:
        """Enforce USR# prefix so the PK is always well-formed."""
        if not value.startswith("USR#"):
            raise ValueError(
                f"rider_id '{value}' must carry the 'USR#' prefix "
                "(e.g. 'USR#abc-123')."
            )
        return value


class SubmitBidPayload(BaseModel):
    """Validated inbound payload for the SUBMIT_BID route.

    A Driver sends this to counter the Rider's baseline fare with their own
    offer. Both the broadcast record PK and the Driver's connection context
    are required to route the response back to the correct Rider.

    Attributes:
        driver_id:         USR#<DriverId> — the bidding driver's DynamoDB PK.
        broadcast_pk:      PK of the open BID# record created by BROADCAST_REQUEST.
        counter_fare:      Driver's counter-offer in ZAR (Decimal; must be > 0).
        estimated_pickup:  Free-text estimated arrival time (e.g. "5 minutes").
        connection_id:     API Gateway connectionId of the bidding Driver.
    """

    model_config = ConfigDict(
        extra="forbid",
        strict=False,
        populate_by_name=True,
    )

    driver_id: str = Field(
        ...,
        description="USR#<DriverId> of the bidding driver.",
        min_length=5,
    )
    broadcast_pk: str = Field(
        ...,
        description="PK of the open BID# broadcast record.",
        min_length=1,
    )
    counter_fare: Decimal = Field(
        ...,
        description="Driver's counter-offer fare in ZAR. Must be > 0.",
        gt=Decimal("0.00"),
    )
    estimated_pickup: str = Field(
        default="",
        description="Driver's free-text ETA (e.g. '5 minutes').",
        max_length=128,
    )
    connection_id: str = Field(
        ...,
        description="API Gateway connectionId of the bidding Driver.",
        min_length=1,
    )

    @field_validator("driver_id")
    @classmethod
    def driver_id_must_have_prefix(cls, value: str) -> str:
        """Enforce USR# prefix so the PK is always well-formed."""
        if not value.startswith("USR#"):
            raise ValueError(
                f"driver_id '{value}' must carry the 'USR#' prefix "
                "(e.g. 'USR#abc-123')."
            )
        return value

    @field_validator("broadcast_pk")
    @classmethod
    def broadcast_pk_must_have_prefix(cls, value: str) -> str:
        """Enforce BID# prefix on the broadcast record identifier."""
        if not value.startswith("BID#"):
            raise ValueError(
                f"broadcast_pk '{value}' must carry the 'BID#' prefix "
                "(e.g. 'BID#uuid-here')."
            )
        return value


# ---------------------------------------------------------------------------
# Response factory helpers
# ---------------------------------------------------------------------------

def _ok(body: dict[str, Any]) -> dict[str, Any]:
    """Return an API Gateway-compatible 200 OK response."""
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def _bad_request(message: str) -> dict[str, Any]:
    """Return an API Gateway-compatible 400 Bad Request response."""
    return {
        "statusCode": 400,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": "ValidationError", "detail": message}),
    }


def _server_error(message: str) -> dict[str, Any]:
    """Return an API Gateway-compatible 500 Internal Server Error response."""
    return {
        "statusCode": 500,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": "InfrastructureError", "detail": message}),
    }


def _not_found() -> dict[str, Any]:
    """Return an API Gateway-compatible 404 Not Found response."""
    return {
        "statusCode": 404,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"error": "NotFound", "detail": "Requested item does not exist."}),
    }


# ---------------------------------------------------------------------------
# Route handlers
# ---------------------------------------------------------------------------

def _handle_connect(connection_id: str, request_context: dict[str, Any]) -> dict[str, Any]:
    """Process a WebSocket $connect event.

    Logs connection telemetry. No DynamoDB write is performed at connection
    time; presence records are lazily created when the Rider issues a
    BROADCAST_REQUEST.

    Args:
        connection_id:    The opaque connectionId assigned by API Gateway.
        request_context:  The full ``requestContext`` dict from the event.

    Returns:
        200 OK — API Gateway requires a 2xx to accept the WebSocket upgrade.
    """
    source_ip: str = request_context.get("identity", {}).get("sourceIp", "unknown")
    stage: str = request_context.get("stage", "unknown")

    logger.info(
        "WS $connect — connectionId=%s sourceIp=%s stage=%s",
        connection_id,
        source_ip,
        stage,
    )
    return _ok({"message": "Connection established.", "connectionId": connection_id})


def _handle_disconnect(connection_id: str, request_context: dict[str, Any]) -> dict[str, Any]:
    """Process a WebSocket $disconnect event.

    Logs disconnection telemetry. Ephemeral connection state cleanup
    (e.g. removing stale BID# records) is deferred to a dedicated TTL sweep
    or an explicit cleanup action to avoid adding latency to the disconnect path.

    Args:
        connection_id:    The opaque connectionId being torn down.
        request_context:  The full ``requestContext`` dict from the event.

    Returns:
        200 OK — always acknowledge the disconnect without error.
    """
    disconnect_reason: str = request_context.get("disconnectReason", "unknown")

    logger.info(
        "WS $disconnect — connectionId=%s reason=%s",
        connection_id,
        disconnect_reason,
    )
    return _ok({"message": "Connection closed.", "connectionId": connection_id})


def _handle_broadcast_request(body: dict[str, Any]) -> dict[str, Any]:
    """Validate and persist a Rider's open-bid broadcast record.

    Parses the inbound JSON body through ``BroadcastRequestPayload`` (Pydantic v2)
    to enforce field-level hygiene before any DynamoDB write. The broadcast is
    stored under:

        PK = BID#<connectionId>   SK = OPEN

    so that Drivers querying open bids can locate all active broadcasts via a
    begins_with("BID#") scan on the GSI, and a Rider's own broadcast is
    directly addressable by their connectionId.

    Args:
        body: Decoded JSON dict from the WebSocket message body.

    Returns:
        An API Gateway-compatible response dict.
    """
    try:
        payload = BroadcastRequestPayload(**body)
    except ValidationError as exc:
        logger.warning("BROADCAST_REQUEST validation failed: %s", exc)
        return _bad_request(exc.json())

    pk: str = f"BID#{payload.connection_id}"
    sk: str = "OPEN"

    item: dict[str, Any] = {
        "PK": pk,
        "SK": sk,
        "rider_id": payload.rider_id,
        "pickup_location": payload.pickup_location,
        "destination": payload.destination,
        "passenger_count": payload.passenger_count,
        # Store Decimal as string to preserve precision in DynamoDB Number type.
        "baseline_fare": str(payload.baseline_fare),
        "connection_id": payload.connection_id,
        "status": "OPEN",
    }

    table = get_table()
    try:
        table.put_item(Item=item)
        logger.info(
            "BROADCAST_REQUEST persisted: PK=%s rider_id=%s baseline_fare=%s",
            pk,
            payload.rider_id,
            payload.baseline_fare,
        )
    except botocore.exceptions.ClientError as exc:
        error_code: str = exc.response["Error"]["Code"]
        logger.error(
            "DynamoDB ClientError [%s] on BROADCAST_REQUEST PK=%s: %s",
            error_code,
            pk,
            exc,
        )
        return _server_error(f"DynamoDB error [{error_code}]: unable to persist broadcast.")

    return _ok({
        "message": "Broadcast published. Awaiting Driver bids.",
        "broadcast_pk": pk,
        "SK": sk,
        "rider_id": payload.rider_id,
        "baseline_fare": str(payload.baseline_fare),
    })


def _handle_submit_bid(body: dict[str, Any]) -> dict[str, Any]:
    """Validate and persist a Driver's counter-offer bid record.

    Parses the inbound JSON body through ``SubmitBidPayload`` (Pydantic v2)
    to enforce field-level hygiene before any DynamoDB write. The bid record
    is stored under:

        PK = BID#<broadcast_pk>   SK = OFFER#<driver_id>

    This key scheme allows a Rider to query all offers for their broadcast
    via a begins_with("OFFER#") sort-key condition without a GSI scan.

    Args:
        body: Decoded JSON dict from the WebSocket message body.

    Returns:
        An API Gateway-compatible response dict.
    """
    try:
        payload = SubmitBidPayload(**body)
    except ValidationError as exc:
        logger.warning("SUBMIT_BID validation failed: %s", exc)
        return _bad_request(exc.json())

    # broadcast_pk already carries the BID# prefix (validated by the model).
    pk: str = payload.broadcast_pk
    sk: str = f"OFFER#{payload.driver_id}"

    item: dict[str, Any] = {
        "PK": pk,
        "SK": sk,
        "driver_id": payload.driver_id,
        "counter_fare": str(payload.counter_fare),
        "estimated_pickup": payload.estimated_pickup,
        "driver_connection_id": payload.connection_id,
        "status": "PENDING",
    }

    table = get_table()
    try:
        table.put_item(Item=item)
        logger.info(
            "SUBMIT_BID persisted: PK=%s SK=%s driver_id=%s counter_fare=%s",
            pk,
            sk,
            payload.driver_id,
            payload.counter_fare,
        )
    except botocore.exceptions.ClientError as exc:
        error_code: str = exc.response["Error"]["Code"]
        logger.error(
            "DynamoDB ClientError [%s] on SUBMIT_BID PK=%s SK=%s: %s",
            error_code,
            pk,
            sk,
            exc,
        )
        return _server_error(f"DynamoDB error [{error_code}]: unable to persist bid.")

    return _ok({
        "message": "Bid submitted. Awaiting Rider acceptance.",
        "broadcast_pk": pk,
        "offer_sk": sk,
        "driver_id": payload.driver_id,
        "counter_fare": str(payload.counter_fare),
    })


# ---------------------------------------------------------------------------
# Route dispatcher map
# ---------------------------------------------------------------------------

_ROUTER: dict[str, Any] = {
    "BROADCAST_REQUEST": lambda body, _ctx: _handle_broadcast_request(body),
    "SUBMIT_BID": lambda body, _ctx: _handle_submit_bid(body),
}


# ---------------------------------------------------------------------------
# Lambda entrypoint
# ---------------------------------------------------------------------------

def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Primary Lambda entrypoint for the kwella Bidding Engine WebSocket worker.

    Parses an API Gateway WebSocket proxy event, extracts the route key and
    connection metadata, and dispatches to the appropriate route handler.

    Args:
        event:   The Lambda event dict supplied by API Gateway WebSocket proxy.
                 Must contain a ``requestContext`` with at minimum a ``routeKey``
                 and ``connectionId``. MESSAGE events additionally carry a
                 JSON-encoded ``body`` string.
        context: The Lambda runtime context object (reserved for future use).

    Returns:
        An API Gateway-compatible response dict containing a ``statusCode``,
        ``headers``, and JSON-serialised ``body``.

    WebSocket route key dispatch:

        $connect          → _handle_connect
        $disconnect       → _handle_disconnect
        BROADCAST_REQUEST → _handle_broadcast_request
        SUBMIT_BID        → _handle_submit_bid

    Event contract for MESSAGE routes (BROADCAST_REQUEST / SUBMIT_BID)::

        {
            "requestContext": {
                "routeKey":     "BROADCAST_REQUEST",
                "connectionId": "abc123==",
                "domainName":   "<api-id>.execute-api.af-south-1.amazonaws.com",
                "stage":        "production"
            },
            "body": "{...}"    ← JSON-encoded string; decoded internally
        }

    Example — rider broadcasts a trip request::

        {
            "requestContext": {
                "routeKey": "BROADCAST_REQUEST",
                "connectionId": "rider-conn-id=="
            },
            "body": "{
                \\"rider_id\\": \\"USR#abc-123\\",
                \\"pickup_location\\": \\"Bellville Station\\",
                \\"destination\\": \\"Cape Town CBD\\",
                \\"passenger_count\\": 3,
                \\"baseline_fare\\": \\"25.00\\",
                \\"connection_id\\": \\"rider-conn-id==\\"
            }"
        }

    Example — driver submits a counter-offer::

        {
            "requestContext": {
                "routeKey": "SUBMIT_BID",
                "connectionId": "driver-conn-id=="
            },
            "body": "{
                \\"driver_id\\": \\"USR#drv-456\\",
                \\"broadcast_pk\\": \\"BID#rider-conn-id==\\",
                \\"counter_fare\\": \\"22.50\\",
                \\"estimated_pickup\\": \\"4 minutes\\",
                \\"connection_id\\": \\"driver-conn-id==\\"
            }"
        }
    """
    request_context: dict[str, Any] = event.get("requestContext", {})
    route_key: str = request_context.get("routeKey", "")
    connection_id: str = request_context.get("connectionId", "")

    logger.info(
        "Bidding engine invoked: routeKey=%s connectionId=%s",
        route_key,
        connection_id,
    )

    # -----------------------------------------------------------------------
    # $connect — WebSocket handshake; must respond 2xx to accept upgrade.
    # -----------------------------------------------------------------------
    if route_key == "$connect":
        return _handle_connect(connection_id, request_context)

    # -----------------------------------------------------------------------
    # $disconnect — WebSocket teardown; always acknowledge cleanly.
    # -----------------------------------------------------------------------
    if route_key == "$disconnect":
        return _handle_disconnect(connection_id, request_context)

    # -----------------------------------------------------------------------
    # Custom route keys — require a JSON-encoded body.
    # -----------------------------------------------------------------------
    raw_body: str | None = event.get("body")
    if not raw_body:
        logger.warning(
            "Empty body received for route '%s' on connectionId=%s",
            route_key,
            connection_id,
        )
        return _bad_request(f"Route '{route_key}' requires a non-empty JSON body.")

    try:
        body: dict[str, Any] = json.loads(raw_body)
    except (json.JSONDecodeError, ValueError) as exc:
        logger.warning(
            "Malformed JSON body on route '%s' connectionId=%s: %s",
            route_key,
            connection_id,
            exc,
        )
        return _bad_request("Request body is not valid JSON.")

    route_fn = _ROUTER.get(route_key)
    if route_fn is None:
        supported: str = ", ".join(_ROUTER.keys())
        logger.warning("Unknown routeKey received: '%s'", route_key)
        return _bad_request(
            f"Unknown route key '{route_key}'. "
            f"Supported MESSAGE routes: {supported}."
        )

    return route_fn(body, request_context)
