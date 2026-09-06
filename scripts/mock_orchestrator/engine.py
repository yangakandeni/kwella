"""The orchestrator engine: wires state + contract + delivery + bot behavior.

This is the single object shared by the app-facing WebSocket server and the
dashboard control server. It owns:
  - the in-memory marketplace state (`OrchestratorState`)
  - the one "real" app connection under test
  - delivery of pushes to that real connection (with simulated network
    latency/drop) or to bot personas (which react autonomously)
  - the offer-timeout / resurface watchdog for ignored ride offers
  - a subscriber list of dashboard control sockets, notified on every change
"""

from __future__ import annotations

import asyncio
import random
from typing import Any, Awaitable, Callable

import bots
import contract
from state import OrchestratorState, Persona, Role

Sender = Callable[[dict[str, Any]], Awaitable[None]]


class Engine:
    def __init__(self, role: Role, scenario: dict[str, Any]) -> None:
        self.state = OrchestratorState(role=role)
        self.scenario = scenario
        self.offer_timeout_seconds: float = float(scenario.get("offerTimeoutSeconds", 15))
        self.resurface_delay_seconds: float = float(scenario.get("resurfaceDelaySeconds", 20))
        self.bid_window_seconds: float = float(scenario.get("riderAutoSelectWindowSeconds", 4))
        self.drive_step_interval: float = float(scenario.get("driveIntervalSeconds", 1.2))
        self.drive_steps: int = int(scenario.get("driveSteps", 6))

        self._real_send: Sender | None = None
        self._dashboard_subscribers: set[Sender] = set()
        self._pending_offer_tasks: dict[tuple[str, str], asyncio.Task] = {}
        # Keyed by tripId — used by bots.py to avoid double-scheduling an
        # auto-select for a rider persona watching the same trip.
        self.rider_auto_select_tasks: dict[str, asyncio.Task] = {}

        for persona_cfg in scenario.get("personas", []):
            self._spawn_persona(persona_cfg)

        self._idle_broadcast_task: asyncio.Task | None = None

    # ------------------------------------------------------------------
    # Persona lifecycle
    # ------------------------------------------------------------------

    def _spawn_persona(self, cfg: dict[str, Any]) -> Persona:
        persona = Persona(
            id=cfg["id"],
            name=cfg.get("name", cfg["id"]),
            role=self.state.persona_role,
            latitude=cfg["latitude"],
            longitude=cfg["longitude"],
            vehicle_make=cfg.get("vehicleMake"),
            vehicle_model=cfg.get("vehicleModel"),
            vehicle_color=cfg.get("vehicleColor"),
            license_plate=cfg.get("licensePlate"),
            cata_sticker=cfg.get("cataSticker"),
            rating=cfg.get("rating", 4.8),
            behavior=cfg.get("behavior", "auto"),
            bid_offset=cfg.get("bidOffset", 0.0),
            eta_minutes=cfg.get("etaMinutes", 5),
        )
        self.state.personas[persona.id] = persona
        return persona

    def add_persona(self, cfg: dict[str, Any]) -> Persona:
        persona = self._spawn_persona(cfg)
        self._log("persona", f"Added persona {persona.id} ({persona.role})")
        self.broadcast_state()
        return persona

    def remove_persona(self, persona_id: str) -> None:
        self.state.personas.pop(persona_id, None)
        self._log("persona", f"Removed persona {persona_id}")
        self.broadcast_state()

    def set_persona_behavior(self, persona_id: str, behavior: str) -> None:
        persona = self.state.personas.get(persona_id)
        if persona:
            persona.behavior = behavior
            self._log("persona", f"{persona_id} behavior -> {behavior}")
            self.broadcast_state()

    # ------------------------------------------------------------------
    # Real-app connection management
    # ------------------------------------------------------------------

    def register_real_connection(self, send: Sender) -> None:
        self._real_send = send
        self._log("connection", "Real app connected")
        self.broadcast_state()
        if self.state.role == "rider":
            self._start_idle_driver_broadcast()

    def unregister_real_connection(self) -> None:
        self._real_send = None
        self.state.real_entity_id = None
        self._log("connection", "Real app disconnected")
        self.broadcast_state()

    def note_real_entity_id(self, entity_id: str) -> None:
        if self.state.real_entity_id != entity_id:
            self.state.real_entity_id = entity_id
            self._log("connection", f"Identified real app as {entity_id}")
            self.broadcast_state()

    # ------------------------------------------------------------------
    # Dashboard subscribers
    # ------------------------------------------------------------------

    def add_dashboard_subscriber(self, send: Sender) -> None:
        self._dashboard_subscribers.add(send)

    def remove_dashboard_subscriber(self, send: Sender) -> None:
        self._dashboard_subscribers.discard(send)

    def broadcast_state(self) -> None:
        snapshot = self.state.snapshot()
        for send in list(self._dashboard_subscribers):
            asyncio.create_task(self._safe_send(send, {"type": "state", "state": snapshot}))

    def _log(self, kind: str, message: str, **extra: Any) -> None:
        entry = self.state.add_log(kind, message, **extra)
        for send in list(self._dashboard_subscribers):
            asyncio.create_task(self._safe_send(send, {"type": "log", "entry": entry}))

    @staticmethod
    async def _safe_send(send: Sender, payload: dict[str, Any]) -> None:
        try:
            await send(payload)
        except Exception:
            pass

    # ------------------------------------------------------------------
    # Action dispatch (used by both the real app socket and bot/dashboard
    # commands so every code path goes through the identical contract).
    # ------------------------------------------------------------------

    async def handle_action(self, action: str, payload: dict[str, Any], sender_id: str | None, source: str) -> dict[str, Any]:
        response, pushes, error = contract.dispatch(self.state, action, payload, sender_id)
        if error is not None:
            self._log("error", f"[{source}] {action} rejected: {error.detail}", action=action, sender=sender_id)
            self.broadcast_state()
            return {"error": error.error, "detail": error.detail}

        self._log("action", f"[{source}] {sender_id or '?'} -> {action}", action=action, sender=sender_id, payload=payload)
        for target_id, push_payload in pushes:
            await self._deliver(action, target_id, push_payload)

        if action == "requestTrip":
            self._arm_offer_timeouts(response["tripId"], pushes)

        self.broadcast_state()
        return response

    def _arm_offer_timeouts(self, trip_id: str, pushes: list[tuple[str, dict[str, Any]]]) -> None:
        for target_id, push_payload in pushes:
            if push_payload.get("action") != "rideOfferAvailable":
                continue
            key = (trip_id, target_id)
            task = asyncio.create_task(self._watch_offer_timeout(trip_id, target_id))
            self._pending_offer_tasks[key] = task

    async def _watch_offer_timeout(self, trip_id: str, target_id: str) -> None:
        try:
            await asyncio.sleep(self.offer_timeout_seconds)
        except asyncio.CancelledError:
            return

        trip = self.state.trips.get(trip_id)
        if trip is None or trip.status.value != "BROADCASTING":
            return
        if target_id in trip.bids or target_id in trip.blocked_driver_ids:
            return

        self._log("offer", f"Offer for trip {trip_id} timed out for {target_id} (ignored)", tripId=trip_id, driverId=target_id)
        self.broadcast_state()

        if self.resurface_delay_seconds <= 0:
            return
        try:
            await asyncio.sleep(self.resurface_delay_seconds)
        except asyncio.CancelledError:
            return

        trip = self.state.trips.get(trip_id)
        if trip is None or trip.status.value != "BROADCASTING":
            return
        if target_id in trip.bids or target_id in trip.blocked_driver_ids:
            return

        self._log("offer", f"Resurfacing trip {trip_id} offer to {target_id}", tripId=trip_id, driverId=target_id)
        offer_payload = {
            "action": "rideOfferAvailable",
            "tripId": trip_id,
            "rider_id": trip.rider_id,
            "pickup_location": list(trip.pickup),
            "dropoff_location": list(trip.dropoff),
            "passenger_count": trip.passenger_count,
            "base_fare": str(trip.base_fare),
            "expires_in_seconds": contract.RIDE_OFFER_TTL_SECONDS,
        }
        await self._deliver("rideOfferAvailable", target_id, offer_payload)
        self._pending_offer_tasks[(trip_id, target_id)] = asyncio.create_task(self._watch_offer_timeout(trip_id, target_id))
        self.broadcast_state()

    def cancel_offer_watch(self, trip_id: str, target_id: str) -> None:
        task = self._pending_offer_tasks.pop((trip_id, target_id), None)
        if task and not task.done():
            task.cancel()

    async def decline_offer(self, target_id: str, trip_id: str) -> None:
        trip = self.state.trips.get(trip_id)
        if trip is None:
            return
        trip.blocked_driver_ids.add(target_id)
        self.cancel_offer_watch(trip_id, target_id)
        persona = self.state.personas.get(target_id)
        if persona is not None:
            persona.status = "rejected"
        self._log("offer", f"{target_id} declined trip {trip_id} permanently", tripId=trip_id, driverId=target_id)
        self.broadcast_state()

    # ------------------------------------------------------------------
    # Delivery
    # ------------------------------------------------------------------

    async def _deliver(self, source_action: str, target_id: str, payload: dict[str, Any]) -> None:
        if target_id and target_id == self.state.real_entity_id and self._real_send is not None:
            await self._deliver_to_real(payload)
            return
        persona = self.state.personas.get(target_id)
        if persona is not None:
            self._log("push", f"-> {target_id}: {payload.get('action') or payload.get('status')}", target=target_id, payload=payload)
            # Fire-and-forget: a persona's reaction (e.g. an auto-bid after a
            # random "thinking" delay) must never block the handler that
            # triggered this push, or the real app's synchronous ack for its
            # own action could be reordered behind the bot's follow-up push.
            asyncio.create_task(bots.on_persona_push(self, persona, payload))
            return
        self._log("push", f"Dropped push (no route to '{target_id}'): {payload.get('action') or payload.get('status')}", target=target_id)

    async def _deliver_to_real(self, payload: dict[str, Any]) -> None:
        net = self.state.network
        if net.drop_rate > 0 and random.random() < net.drop_rate:
            self._log("network", f"Dropped push to real app (simulated network loss): {payload.get('action') or payload.get('status')}")
            return
        if net.latency_ms > 0:
            await asyncio.sleep(net.latency_ms / 1000.0)
        self._log("push", f"-> real app: {payload.get('action') or payload.get('status')}", payload=payload)
        assert self._real_send is not None
        await self._real_send(payload)

    # ------------------------------------------------------------------
    # Idle driver broadcast (rider-mode "nearby drivers on the map")
    # ------------------------------------------------------------------

    def _start_idle_driver_broadcast(self) -> None:
        if self._idle_broadcast_task is not None:
            return
        self._idle_broadcast_task = asyncio.create_task(self._idle_driver_broadcast_loop())

    async def _idle_driver_broadcast_loop(self) -> None:
        try:
            while True:
                await asyncio.sleep(3.0)
                if self._real_send is None:
                    continue
                for persona in self.state.personas.values():
                    if persona.role != "driver" or persona.status != "idle":
                        continue
                    persona.latitude += random.uniform(-0.0004, 0.0004)
                    persona.longitude += random.uniform(-0.0004, 0.0004)
                    await self._deliver_to_real(
                        {
                            "action": "nearbyDriverUpdate",
                            "driverId": persona.id,
                            "latitude": persona.latitude,
                            "longitude": persona.longitude,
                            "status": "idle",
                        }
                    )
                self.broadcast_state()
        except asyncio.CancelledError:
            pass

    # ------------------------------------------------------------------
    # Manual driver-lifecycle stepping (dashboard buttons)
    # ------------------------------------------------------------------

    async def driver_step(self, persona_id: str, step: str, extra: dict[str, Any] | None = None) -> dict[str, Any]:
        persona = self.state.personas.get(persona_id)
        trip_id = persona.active_trip_id if persona else (extra or {}).get("tripId")
        extra = extra or {}
        payload_map = {
            "arrived": ("driverArrived", {"tripId": trip_id, "driverId": persona_id}),
            "startTrip": ("startTrip", {"tripId": trip_id, "driverId": persona_id}),
            "confirmArrival": (
                "confirmArrival",
                {"tripId": trip_id, "driverId": persona_id, "final_bid_amount": extra.get("finalBidAmount")},
            ),
            "submitRating": (
                "submitRating",
                {"tripId": trip_id, "driverId": persona_id, "rating": extra.get("rating", 5), "target": "RIDER"},
            ),
        }
        action, payload = payload_map[step]
        return await self.handle_action(action, payload, persona_id, source="dashboard")
