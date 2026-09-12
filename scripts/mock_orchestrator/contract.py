"""Wire-compatible re-implementation of the bidding engine's action contract.

Every function here mirrors one `route_key` branch in
`kwella-backend/src/lambdas/bidding_engine/handler.py` closely enough that a
real rider or driver app cannot tell the difference between talking to this
mock and talking to the real API Gateway WebSocket route. Field names,
fallback keys (`driverId`/`driver_id`), status strings, and push action
names are copied verbatim from that file (verified against the checked-in
handler on 2026-09-06).

One deliberate hardening: `select_bid` below rejects a second `selectBid`
against a trip that already has a `selected_driver_id` with a
`"Trip no longer available"` error. The real Lambda has no such guard today
(it will silently overwrite the winner) — this mock implements the *intended*
race-safe contract so testers can verify the rider app surfaces that error
state correctly, per the requested concurrency scenario.

Each handler returns `(response_body, pushes)`:
  - `response_body`: the dict the caller (the real app's `send`) should get
    back as a synchronous ack — the server layer wraps it as
    `{"statusCode": ..., "body": json.dumps(response_body)}`-equivalent, but
    over a plain WS this is just sent back to the same connection.
  - `pushes`: a list of `(target_entity_id, payload)` tuples to be delivered
    asynchronously to other connections/personas (e.g. the rider on a
    driver's bid, the driver on trip selection).
"""

from __future__ import annotations

import math
import sys
from pathlib import Path
from typing import Any

from state import Bid, OrchestratorState, Persona, Receipt, Trip, TripStatus

# Import the REAL fare engine rather than re-implementing it.
#
# This module used to carry its own `calculate_trip_fare` with its own
# hardcoded `flat_rate = 25.0`, which produced a floor of R150 where the real
# backend's floor was R60 — so the mock quoted a fare the deployed engine
# would never produce, and local testing actively misled. `fare_calculator`
# depends only on the standard library (os/datetime/decimal), so importing it
# here is safe and makes drift between the two impossible by construction.
_FARE_LAYER = (
    Path(__file__).resolve().parents[2]
    / "kwella-backend"
    / "src"
    / "layers"
    / "kwella_shared"
    / "python"
)
if str(_FARE_LAYER) not in sys.path:
    sys.path.insert(0, str(_FARE_LAYER))

from fare_calculator import (  # noqa: E402
    DRIVER_PAYOUT_RATE as _DRIVER_PAYOUT_RATE,
    FARE_QUANTUM_ZAR as _FARE_QUANTUM_ZAR,
    calculate_trip_fare as _calculate_trip_fare_zar,
    is_quantized_fare as _is_quantized_fare,
    quantize_fare_zar,
)

_TRIP_MATCH_RADIUS_M = 5000.0
_ARRIVAL_GEOFENCE_RADIUS_M = 50.0
RIDE_OFFER_TTL_SECONDS = 15
#: Imported rather than restated: the mock must settle a trip for exactly
#: what the real bidding engine would, or a driver testing against it sees a
#: payout that won't match production.
_PAYOUT_RATE = float(_DRIVER_PAYOUT_RATE)


class ContractError(Exception):
    def __init__(self, detail: str, error: str = "ValidationError") -> None:
        super().__init__(detail)
        self.detail = detail
        self.error = error


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def calculate_trip_fare(distance_km: float, passenger_count: int) -> float:
    """Delegate to the real server-side engine, returning a plain float.

    Kept as a thin wrapper (rather than calling `fare_calculator` directly at
    the call site) so this module's public surface still mirrors the shape the
    rest of the mock expects, and so the Decimal -> float conversion for JSON
    happens in exactly one place.
    """
    return float(
        _calculate_trip_fare_zar(
            distance_km=distance_km,
            passenger_count=passenger_count,
        )
    )


#: Mirrors the real handler's `_SUPPORTED_PAYMENT_METHODS` — anything else
#: degrades to CASH rather than being rejected.
_SUPPORTED_PAYMENT_METHODS = frozenset({"CASH", "CARD"})
_DEFAULT_PAYMENT_METHOD = "CASH"


def _normalise_payment_method(raw: Any) -> str:
    if not isinstance(raw, str):
        return _DEFAULT_PAYMENT_METHOD
    candidate = raw.strip().upper()
    if candidate not in _SUPPORTED_PAYMENT_METHODS:
        return _DEFAULT_PAYMENT_METHOD
    return candidate


def _persona_public_fields(persona: Persona | None) -> dict[str, Any]:
    if persona is None:
        return {
            "driverName": None,
            "rating": None,
            "vehicleMake": None,
            "vehicleModel": None,
            "vehicleColor": None,
            "licensePlate": None,
            "cataSticker": None,
        }
    return {
        "driverName": persona.name,
        "rating": persona.rating,
        "vehicleMake": persona.vehicle_make,
        "vehicleModel": persona.vehicle_model,
        "vehicleColor": persona.vehicle_color,
        "licensePlate": persona.license_plate,
        "cataSticker": persona.cata_sticker,
    }


def _get_trip(state: OrchestratorState, trip_id: str | None) -> Trip:
    if not trip_id or not isinstance(trip_id, str):
        raise ContractError("Missing or invalid required field 'tripId'.")
    trip = state.trips.get(trip_id)
    if trip is None:
        raise ContractError(f"Trip '{trip_id}' does not exist.")
    return trip


def _match_and_push_offer(
    state: OrchestratorState, pickup: tuple[float, float], offer_payload: dict[str, Any]
) -> tuple[list[str], list[tuple[str, dict[str, Any]]]]:
    """Finds drivers within `_TRIP_MATCH_RADIUS_M` of `pickup` and queues
    `offer_payload` as a push to each. Shared by `request_trip` (initial
    broadcast) and `update_fare` (re-broadcast at the new fare)."""
    pickup_lat, pickup_lon = pickup
    matched_driver_ids: list[str] = []
    pushes: list[tuple[str, dict[str, Any]]] = []

    for persona in state.personas.values():
        if persona.role != "driver":
            continue
        distance_m = _haversine_m(persona.latitude, persona.longitude, pickup_lat, pickup_lon)
        if distance_m > _TRIP_MATCH_RADIUS_M:
            continue
        matched_driver_ids.append(persona.id)
        pushes.append((persona.id, dict(offer_payload)))

    # The real app under test (when it's a driver) also receives the offer
    # if it's registered and within range — but we have no live coordinate
    # for it beyond what updateLocation last reported, so always include it.
    if state.role == "driver" and state.real_entity_id:
        matched_driver_ids.append(state.real_entity_id)
        pushes.append((state.real_entity_id, dict(offer_payload)))

    return matched_driver_ids, pushes


def request_trip(state: OrchestratorState, payload: dict[str, Any], sender_id: str | None):
    rider_id = payload.get("riderId") or sender_id
    pickup_lat = payload.get("pickup_latitude")
    pickup_lon = payload.get("pickup_longitude")
    dropoff_lat = payload.get("dropoff_latitude")
    dropoff_lon = payload.get("dropoff_longitude")

    missing = [
        k
        for k, v in {
            "riderId": rider_id,
            "pickup_latitude": pickup_lat,
            "pickup_longitude": pickup_lon,
            "dropoff_latitude": dropoff_lat,
            "dropoff_longitude": dropoff_lon,
        }.items()
        if v is None
    ]
    if missing:
        raise ContractError(f"Missing required fields: {missing}")

    passenger_count = int(payload.get("passenger_count") or payload.get("passengerCount") or 1)
    payment_method = _normalise_payment_method(
        payload.get("payment_method") or payload.get("paymentMethod")
    )
    distance_km = _haversine_m(pickup_lat, pickup_lon, dropoff_lat, dropoff_lon) / 1000.0
    calculated_fare = calculate_trip_fare(distance_km, passenger_count)

    trip_id = state.new_trip_id()
    trip = Trip(
        id=trip_id,
        rider_id=rider_id,
        pickup=(pickup_lat, pickup_lon),
        dropoff=(dropoff_lat, dropoff_lon),
        passenger_count=passenger_count,
        base_fare=calculated_fare,
        payment_method=payment_method,
    )
    state.trips[trip_id] = trip

    offer_payload = {
        "action": "rideOfferAvailable",
        "tripId": trip_id,
        "rider_id": rider_id,
        "pickup_location": [pickup_lat, pickup_lon],
        "dropoff_location": [dropoff_lat, dropoff_lon],
        "passenger_count": passenger_count,
        "base_fare": str(calculated_fare),
        "payment_method": payment_method,
        "expires_in_seconds": RIDE_OFFER_TTL_SECONDS,
    }
    matched_driver_ids, pushes = _match_and_push_offer(state, trip.pickup, offer_payload)

    response = {
        "status": "TripBroadcast",
        "tripId": trip_id,
        "matched_drivers": matched_driver_ids,
        "passenger_count": passenger_count,
        "calculated_fare": str(calculated_fare),
        "payment_method": payment_method,
    }
    return response, pushes


def send_bid(state: OrchestratorState, payload: dict[str, Any], sender_id: str | None):
    driver_id = payload.get("driverId") or payload.get("driver_id") or sender_id
    rider_id = payload.get("riderId") or payload.get("rider_id")
    trip_id = payload.get("tripId") or payload.get("trip_id")
    amount = payload.get("amount") or payload.get("counter_fare") or payload.get("baseline_fare")
    eta_minutes = payload.get("etaMinutes") or payload.get("estimated_pickup") or payload.get("estimatedPickup")

    trip = _get_trip(state, trip_id)
    if driver_id in trip.blocked_driver_ids:
        raise ContractError(f"Driver '{driver_id}' has declined this trip and cannot bid again.")

    try:
        amount_f = float(amount)
    except (TypeError, ValueError):
        raise ContractError("Field 'amount' must be numeric.") from None

    # Mirrors the real handler's gate: a counter-offer is what the rider hands
    # over in cash if they accept it, so it has to land on the R0.50 quantum.
    if not _is_quantized_fare(amount_f):
        raise ContractError(
            f"Bid amount must be a multiple of R{_FARE_QUANTUM_ZAR}."
        )

    try:
        eta_i = int(eta_minutes)
    except (TypeError, ValueError):
        eta_i = 5

    trip.bids[driver_id] = Bid(trip_id=trip_id, driver_id=driver_id, amount=amount_f, eta_minutes=eta_i)
    if not rider_id:
        rider_id = trip.rider_id

    persona = state.personas.get(driver_id)
    if persona is not None:
        persona.status = "bidding"
        persona.active_trip_id = trip_id

    pushes: list[tuple[str, dict[str, Any]]] = []
    if rider_id:
        notification = {
            "action": "driverBidReceived",
            "tripId": trip_id,
            "driverId": driver_id,
            "amount": amount_f,
            "etaMinutes": eta_i,
            **_persona_public_fields(persona),
        }
        pushes.append((rider_id, notification))

    response = {
        "status": "Success",
        "message": "Bid received and dispatched to rider.",
        "tripId": trip_id,
        "driverId": driver_id,
        "bid_particulars": {
            "driver_id": driver_id,
            "rider_id": rider_id,
            "amount": amount_f,
            "eta_minutes": eta_i,
        },
    }
    return response, pushes


def select_bid(state: OrchestratorState, payload: dict[str, Any], sender_id: str | None):
    driver_id = payload.get("driverId") or payload.get("driver_id")
    trip_id = payload.get("tripId") or payload.get("trip_id")
    rider_id = payload.get("riderId") or payload.get("rider_id") or sender_id

    if not driver_id or not isinstance(driver_id, str):
        raise ContractError("Missing or invalid required field 'driverId'.")

    trip = _get_trip(state, trip_id)

    # Deliberate hardening beyond the current real backend: reject a
    # late/racing selectBid once another driver already won the trip.
    if trip.status != TripStatus.BROADCASTING:
        raise ContractError("Trip no longer available", error="TripNoLongerAvailable")

    trip.status = TripStatus.ACCEPTED
    trip.selected_driver_id = driver_id
    if rider_id:
        trip.rider_id = rider_id

    pushes: list[tuple[str, dict[str, Any]]] = []
    pushes.append((driver_id, {"action": "bidSelected", "tripId": trip_id, "driverId": driver_id, "riderId": trip.rider_id}))

    persona = state.personas.get(driver_id)
    if persona is not None:
        persona.status = "selected"
    for other_id, other_persona in state.personas.items():
        if other_id != driver_id and other_persona.role == "driver" and other_persona.active_trip_id == trip_id:
            other_persona.status = "rejected"

    if trip.rider_id:
        pushes.append(
            (
                trip.rider_id,
                {
                    "action": "tripMatchConfirmed",
                    "tripId": trip_id,
                    "driverId": driver_id,
                    "riderId": trip.rider_id,
                    **_persona_public_fields(persona),
                },
            )
        )

    response = {"status": "BidSelected", "tripId": trip_id, "driverId": driver_id, "riderId": trip.rider_id}
    return response, pushes


def update_fare(state: OrchestratorState, payload: dict[str, Any], sender_id: str | None):
    trip_id = payload.get("tripId") or payload.get("trip_id")
    trip = _get_trip(state, trip_id)

    # Same late-request guard select_bid uses: once a driver has won (or the
    # trip has otherwise moved past BROADCASTING) there's no offer left to
    # re-price.
    if trip.status != TripStatus.BROADCASTING:
        raise ContractError("Trip no longer available", error="TripNoLongerAvailable")

    new_fare = payload.get("new_fare") or payload.get("newFare")
    try:
        new_fare_f = float(new_fare)
    except (TypeError, ValueError):
        raise ContractError("Field 'new_fare' must be numeric.") from None

    if not _is_quantized_fare(new_fare_f):
        raise ContractError(
            f"Field 'new_fare' must be a multiple of R{_FARE_QUANTUM_ZAR}."
        )

    if new_fare_f <= trip.base_fare:
        raise ContractError("New fare must exceed the current base fare.")

    trip.base_fare = new_fare_f

    offer_payload = {
        "action": "rideOfferAvailable",
        "tripId": trip_id,
        "rider_id": trip.rider_id,
        "pickup_location": list(trip.pickup),
        "dropoff_location": list(trip.dropoff),
        "passenger_count": trip.passenger_count,
        "base_fare": str(new_fare_f),
        "expires_in_seconds": RIDE_OFFER_TTL_SECONDS,
    }
    _matched_driver_ids, pushes = _match_and_push_offer(state, trip.pickup, offer_payload)

    response = {"status": "FareUpdated", "tripId": trip_id, "base_fare": str(new_fare_f)}
    return response, pushes


def driver_arrived(state: OrchestratorState, payload: dict[str, Any], sender_id: str | None):
    trip_id = payload.get("tripId") or payload.get("trip_id")
    trip = _get_trip(state, trip_id)
    if trip.status != TripStatus.ACCEPTED:
        raise ContractError("Trip status must be ACCEPTED to mark arrival.")

    trip.status = TripStatus.ARRIVED
    pushes: list[tuple[str, dict[str, Any]]] = []
    if trip.rider_id:
        pushes.append((trip.rider_id, {"action": "driverArrived", "tripId": trip_id}))

    response = {"status": "DriverArrived", "tripId": trip_id}
    return response, pushes


def update_location(state: OrchestratorState, payload: dict[str, Any], sender_id: str | None):
    driver_id = payload.get("driverId") or sender_id
    latitude = payload.get("latitude")
    longitude = payload.get("longitude")

    missing = [k for k, v in {"driverId": driver_id, "latitude": latitude, "longitude": longitude}.items() if v is None]
    if missing:
        raise ContractError(f"Missing required telematics fields: {missing}")

    persona = state.personas.get(driver_id)
    if persona is not None:
        persona.latitude = float(latitude)
        persona.longitude = float(longitude)
        persona.heading = float(payload.get("heading") or 0.0)
        persona.speed = float(payload.get("speed") or 0.0)

    trip_id = payload.get("tripId")
    target_lat, target_lon = -33.9036, 18.3989
    trip: Trip | None = None
    if trip_id:
        trip = state.trips.get(trip_id)
        if trip is not None:
            target_lat, target_lon = trip.dropoff

    distance_m = _haversine_m(latitude, longitude, target_lat, target_lon)
    response: dict[str, Any] = {"status": "Telemetry Latched"}
    if distance_m <= _ARRIVAL_GEOFENCE_RADIUS_M:
        response["flags"] = {"geofence_status": "ARRIVED"}

    pushes: list[tuple[str, dict[str, Any]]] = []
    if trip is not None and trip.rider_id:
        pushes.append(
            (
                trip.rider_id,
                {
                    "action": "liveDriverLocation",
                    "tripId": trip_id,
                    "driverId": driver_id,
                    "latitude": latitude,
                    "longitude": longitude,
                },
            )
        )
    return response, pushes


def start_trip(state: OrchestratorState, payload: dict[str, Any], sender_id: str | None):
    driver_id = payload.get("driverId") or payload.get("driver_id") or sender_id
    trip_id = payload.get("tripId") or payload.get("trip_id")
    if not driver_id or not isinstance(driver_id, str):
        raise ContractError("Missing or invalid required field 'driverId'.")

    trip = _get_trip(state, trip_id)
    if trip.status != TripStatus.ARRIVED:
        raise ContractError("Trip status must be ARRIVED to start.")

    trip.status = TripStatus.IN_PROGRESS
    pushes: list[tuple[str, dict[str, Any]]] = []
    if trip.rider_id:
        pushes.append((trip.rider_id, {"action": "tripStarted", "tripId": trip_id, "driverId": driver_id}))

    response = {"status": "TripStarted", "tripId": trip_id, "driverId": driver_id}
    return response, pushes


def confirm_arrival(state: OrchestratorState, payload: dict[str, Any], sender_id: str | None):
    driver_id = payload.get("driverId") or sender_id
    trip_id = payload.get("tripId")
    final_bid_amount = payload.get("final_bid_amount")

    if not driver_id or not isinstance(driver_id, str):
        raise ContractError("Missing or invalid required field 'driverId'.")
    trip = _get_trip(state, trip_id)
    if not isinstance(final_bid_amount, (int, float)) or isinstance(final_bid_amount, bool):
        raise ContractError("Missing or invalid required field 'final_bid_amount'.")
    if trip.status != TripStatus.IN_PROGRESS:
        raise ContractError("Payout settlement failed. Trip status must be IN_PROGRESS.")

    trip.status = TripStatus.COMPLETED
    trip.final_bid_amount = float(final_bid_amount)
    net_earnings = round(float(final_bid_amount) * _PAYOUT_RATE, 2)
    updated_daily_total = round(state.wallets.get(driver_id, 0.0) + net_earnings, 2)
    state.wallets[driver_id] = updated_daily_total

    # Instant receipt creation post-trip, for the mock payment plane
    # (`rest_contract.py::get_receipt`) — mirrors the same payout split
    # already computed above rather than inventing a separate fee rate.
    state.receipts[trip_id] = Receipt(
        trip_id=trip_id,
        rider_id=trip.rider_id,
        driver_id=driver_id,
        fare_amount=float(final_bid_amount),
        platform_fee=round(float(final_bid_amount) - net_earnings, 2),
        net_driver_earnings=net_earnings,
    )

    persona = state.personas.get(driver_id)
    if persona is not None:
        persona.status = "idle"
        persona.active_trip_id = None

    settled_payload = {
        "status": "WalletSettled",
        "tripId": trip_id,
        "net_earnings": net_earnings,
        "currency": "ZAR",
        "updated_daily_total": updated_daily_total,
    }
    pushes: list[tuple[str, dict[str, Any]]] = []
    if trip.rider_id:
        pushes.append((trip.rider_id, dict(settled_payload)))
    return settled_payload, pushes


def submit_rating(state: OrchestratorState, payload: dict[str, Any], sender_id: str | None):
    trip_id = payload.get("tripId") or payload.get("trip_id")
    rating = payload.get("rating")
    target = payload.get("target")
    _get_trip(state, trip_id)

    if not isinstance(rating, (int, float)) or not (1 <= rating <= 5):
        raise ContractError("Field 'rating' must be between 1 and 5.")
    if target not in ("RIDER", "DRIVER"):
        raise ContractError("Field 'target' must be 'RIDER' or 'DRIVER'.")

    response = {"status": "RatingRecorded", "tripId": trip_id, "target": target}
    return response, []


DISPATCH = {
    "requestTrip": request_trip,
    "sendBid": send_bid,
    "selectBid": select_bid,
    "updateFare": update_fare,
    "driverArrived": driver_arrived,
    "updateLocation": update_location,
    "startTrip": start_trip,
    "confirmArrival": confirm_arrival,
    "submitRating": submit_rating,
}


def dispatch(state: OrchestratorState, action: str, payload: dict[str, Any], sender_id: str | None):
    """Routes an inbound action to its handler.

    Returns `(response_body, pushes, error)` — `error` is a `ContractError`
    (or `None`) so the caller can decide how to shape the synchronous ack
    without a try/except at every call site.
    """
    handler = DISPATCH.get(action)
    if handler is None:
        return None, [], ContractError(f"Route key '{action}' is not supported.")
    try:
        response, pushes = handler(state, payload, sender_id)
        return response, pushes, None
    except ContractError as exc:
        return None, [], exc
