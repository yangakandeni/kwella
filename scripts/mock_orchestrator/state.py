"""In-memory state model for the Kwella mock marketplace orchestrator.

Mirrors the shapes persisted in DynamoDB by `kwella-backend/src/lambdas/
bidding_engine/handler.py` (TRIP#/METADATA, BID#/DRIVER#, DRIVER#/TELEMETRY,
DRIVER#/WALLET) closely enough that the contract layer built on top of this
state produces wire-identical responses, without needing DynamoDB, AWS
credentials, or API Gateway.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Literal

Role = Literal["driver", "rider"]


class TripStatus(str, Enum):
    BROADCASTING = "BROADCASTING"
    ACCEPTED = "ACCEPTED"
    ARRIVED = "ARRIVED"
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"


@dataclass
class Persona:
    """A bot actor standing in for the "other side" of the marketplace.

    In `--role rider` sessions personas are drivers; in `--role driver`
    sessions personas are riders. `behavior` controls whether the
    orchestrator drives the persona autonomously or waits for a dashboard
    command.
    """

    id: str
    name: str
    role: Role
    latitude: float
    longitude: float
    heading: float = 0.0
    speed: float = 0.0
    vehicle_make: str | None = None
    vehicle_model: str | None = None
    vehicle_color: str | None = None
    license_plate: str | None = None
    cata_sticker: str | None = None
    rating: float | None = 4.8
    # manual | auto-bid | auto-select-cheapest | auto-select-fastest | ignore
    behavior: str = "manual"
    bid_offset: float = 0.0
    eta_minutes: int = 5
    status: str = "idle"  # idle | bidding | selected | rejected | enroute | arrived
    active_trip_id: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "role": self.role,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "heading": self.heading,
            "speed": self.speed,
            "vehicleMake": self.vehicle_make,
            "vehicleModel": self.vehicle_model,
            "vehicleColor": self.vehicle_color,
            "licensePlate": self.license_plate,
            "cataSticker": self.cata_sticker,
            "rating": self.rating,
            "behavior": self.behavior,
            "bidOffset": self.bid_offset,
            "etaMinutes": self.eta_minutes,
            "status": self.status,
            "activeTripId": self.active_trip_id,
        }


@dataclass
class Bid:
    trip_id: str
    driver_id: str
    amount: float
    eta_minutes: int
    created_at: float = field(default_factory=time.time)

    def to_dict(self) -> dict[str, Any]:
        return {
            "tripId": self.trip_id,
            "driverId": self.driver_id,
            "amount": self.amount,
            "etaMinutes": self.eta_minutes,
        }


@dataclass
class Trip:
    id: str
    rider_id: str
    pickup: tuple[float, float]
    dropoff: tuple[float, float]
    passenger_count: int
    base_fare: float
    status: TripStatus = TripStatus.BROADCASTING
    selected_driver_id: str | None = None
    bids: dict[str, Bid] = field(default_factory=dict)
    blocked_driver_ids: set[str] = field(default_factory=set)
    final_bid_amount: float | None = None
    created_at: float = field(default_factory=time.time)

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "riderId": self.rider_id,
            "pickup": list(self.pickup),
            "dropoff": list(self.dropoff),
            "passengerCount": self.passenger_count,
            "baseFare": self.base_fare,
            "status": self.status.value,
            "selectedDriverId": self.selected_driver_id,
            "bids": [b.to_dict() for b in self.bids.values()],
            "blockedDriverIds": sorted(self.blocked_driver_ids),
            "finalBidAmount": self.final_bid_amount,
        }


@dataclass
class NetworkConditions:
    latency_ms: int = 0
    drop_rate: float = 0.0  # 0..1 — fraction of outbound pushes silently dropped

    def to_dict(self) -> dict[str, Any]:
        return {"latencyMs": self.latency_ms, "dropRate": self.drop_rate}


class OrchestratorState:
    """Single-process, single-event-loop state — no locking required since
    every mutation happens inside the same asyncio loop."""

    def __init__(self, role: Role) -> None:
        # `role` is the role of the REAL app under test. Personas play the
        # opposite role.
        self.role: Role = role
        self.persona_role: Role = "driver" if role == "rider" else "rider"
        self.personas: dict[str, Persona] = {}
        self.trips: dict[str, Trip] = {}
        self.wallets: dict[str, float] = {}
        self.real_entity_id: str | None = None
        self.network = NetworkConditions()
        self.log: list[dict[str, Any]] = []

    def new_trip_id(self) -> str:
        return f"TRP#{uuid.uuid4()}"

    def add_log(self, kind: str, message: str, **extra: Any) -> dict[str, Any]:
        entry = {
            "ts": time.time(),
            "kind": kind,
            "message": message,
            **extra,
        }
        self.log.append(entry)
        del self.log[:-500]
        return entry

    def snapshot(self) -> dict[str, Any]:
        return {
            "role": self.role,
            "personaRole": self.persona_role,
            "realEntityId": self.real_entity_id,
            "network": self.network.to_dict(),
            "personas": [p.to_dict() for p in self.personas.values()],
            "trips": [t.to_dict() for t in self.trips.values()],
            "wallets": self.wallets,
        }
