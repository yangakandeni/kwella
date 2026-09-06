"""Autonomous bot behavior for personas.

A persona's `behavior` field controls how it reacts to a push it "receives"
(delivered in-process by `engine.Engine._deliver`, no real socket involved):

  - "auto"   — bids automatically on offers, and once selected drives the
               full scripted route (pickup -> arrived -> start -> dropoff ->
               settle -> rate) for a driver persona; auto-selects the
               cheapest bid and rates the driver for a rider persona.
  - "manual" — never acts on its own; every step is driven by a dashboard
               command (`sendBid`, `selectBid`, `driverStep`, ...).
  - "ignore" — never bids / never selects. Used to exercise the "driver
               ignores the offer" and "trip no longer available" scenarios.
"""

from __future__ import annotations

import asyncio
import random
from typing import TYPE_CHECKING, Any

from state import Persona

if TYPE_CHECKING:
    from engine import Engine


async def on_persona_push(engine: "Engine", persona: Persona, payload: dict[str, Any]) -> None:
    action = payload.get("action")
    status = payload.get("status")

    if persona.role == "driver":
        if action == "rideOfferAvailable":
            await _on_driver_offer(engine, persona, payload)
        elif action == "bidSelected":
            await _on_driver_selected(engine, persona, payload)
        return

    if persona.role == "rider":
        if action == "driverBidReceived":
            await _on_rider_bid_received(engine, persona, payload)
        elif status == "WalletSettled":
            await _on_rider_trip_settled(engine, persona, payload)
        elif action == "tripMatchConfirmed":
            persona.active_trip_id = payload.get("tripId")
        return


# ---------------------------------------------------------------------------
# Driver persona behavior
# ---------------------------------------------------------------------------


async def _on_driver_offer(engine: "Engine", persona: Persona, payload: dict[str, Any]) -> None:
    persona.active_trip_id = payload.get("tripId")
    if persona.behavior != "auto":
        return
    trip_id = payload["tripId"]
    base_fare = float(payload.get("base_fare", 0))
    delay = random.uniform(0.6, 2.2)
    await asyncio.sleep(delay)

    trip = engine.state.trips.get(trip_id)
    if trip is None or trip.status.value != "BROADCASTING":
        return

    amount = round(base_fare + persona.bid_offset, 2)
    await engine.handle_action(
        "sendBid",
        {
            "driverId": persona.id,
            "tripId": trip_id,
            "amount": amount,
            "etaMinutes": persona.eta_minutes,
        },
        persona.id,
        source="bot",
    )


async def _on_driver_selected(engine: "Engine", persona: Persona, payload: dict[str, Any]) -> None:
    if persona.behavior == "manual":
        return
    trip_id = payload.get("tripId")
    trip = engine.state.trips.get(trip_id)
    if trip is None:
        return
    asyncio.create_task(_run_scripted_driver_trip(engine, persona, trip_id))


async def _run_scripted_driver_trip(engine: "Engine", persona: Persona, trip_id: str) -> None:
    trip = engine.state.trips.get(trip_id)
    if trip is None:
        return

    await _drive_route(engine, persona, trip_id, target=trip.pickup)
    await engine.handle_action("driverArrived", {"tripId": trip_id, "driverId": persona.id}, persona.id, source="bot")

    await asyncio.sleep(1.5)  # simulated passenger boarding
    await engine.handle_action("startTrip", {"tripId": trip_id, "driverId": persona.id}, persona.id, source="bot")

    await _drive_route(engine, persona, trip_id, target=trip.dropoff)

    bid = trip.bids.get(persona.id)
    final_amount = bid.amount if bid else trip.base_fare
    await engine.handle_action(
        "confirmArrival",
        {"tripId": trip_id, "driverId": persona.id, "final_bid_amount": final_amount},
        persona.id,
        source="bot",
    )

    await asyncio.sleep(0.8)
    await engine.handle_action(
        "submitRating",
        {"tripId": trip_id, "driverId": persona.id, "rating": 5, "target": "RIDER"},
        persona.id,
        source="bot",
    )


async def _drive_route(engine: "Engine", persona: Persona, trip_id: str, target: tuple[float, float]) -> None:
    start_lat, start_lon = persona.latitude, persona.longitude
    target_lat, target_lon = target
    steps = max(1, engine.drive_steps)
    for step in range(1, steps + 1):
        fraction = step / steps
        # Last step lands exactly on the target so the server-side geofence
        # check (against the trip's dropoff) reliably fires ARRIVED.
        lat = target_lat if step == steps else start_lat + (target_lat - start_lat) * fraction
        lon = target_lon if step == steps else start_lon + (target_lon - start_lon) * fraction
        await engine.handle_action(
            "updateLocation",
            {"driverId": persona.id, "tripId": trip_id, "latitude": lat, "longitude": lon, "heading": 0, "speed": 25},
            persona.id,
            source="bot",
        )
        await asyncio.sleep(engine.drive_step_interval)


# ---------------------------------------------------------------------------
# Rider persona behavior (driver-under-test mode)
# ---------------------------------------------------------------------------


async def _on_rider_bid_received(engine: "Engine", persona: Persona, payload: dict[str, Any]) -> None:
    if persona.behavior != "auto":
        return
    trip_id = payload.get("tripId")
    if trip_id in engine.rider_auto_select_tasks:
        return
    engine.rider_auto_select_tasks[trip_id] = asyncio.create_task(_auto_select_cheapest(engine, persona, trip_id))


async def _auto_select_cheapest(engine: "Engine", persona: Persona, trip_id: str) -> None:
    try:
        await asyncio.sleep(engine.bid_window_seconds)
    finally:
        engine.rider_auto_select_tasks.pop(trip_id, None)

    trip = engine.state.trips.get(trip_id)
    if trip is None or trip.status.value != "BROADCASTING" or not trip.bids:
        return
    eligible = [b for b in trip.bids.values() if b.driver_id not in trip.blocked_driver_ids]
    if not eligible:
        return
    cheapest = min(eligible, key=lambda b: b.amount)
    await engine.handle_action(
        "selectBid",
        {"tripId": trip_id, "driverId": cheapest.driver_id, "riderId": persona.id},
        persona.id,
        source="bot",
    )


async def _on_rider_trip_settled(engine: "Engine", persona: Persona, payload: dict[str, Any]) -> None:
    if persona.behavior != "auto":
        return
    trip_id = payload.get("tripId")
    await asyncio.sleep(0.8)
    await engine.handle_action(
        "submitRating",
        {"tripId": trip_id, "riderId": persona.id, "rating": 5, "target": "DRIVER"},
        persona.id,
        source="bot",
    )
    persona.active_trip_id = None
