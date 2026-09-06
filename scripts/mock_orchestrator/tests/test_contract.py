"""Unit tests for contract.py — the WS-plane mock's pure logic layer.

Mirrors the style of test_rest_contract.py: plain pytest functions against
the contract functions directly, no transport/websocket involved (that's
server.py's job).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest

import contract
from state import OrchestratorState, Persona, TripStatus

PICKUP_LAT, PICKUP_LON = -33.9249, 18.4241
DROPOFF_LAT, DROPOFF_LON = -33.9258, 18.4231


@pytest.fixture
def state() -> OrchestratorState:
    st = OrchestratorState(role="rider")
    st.personas["drv-1"] = Persona(
        id="drv-1",
        name="Thabo",
        role="driver",
        latitude=PICKUP_LAT,
        longitude=PICKUP_LON,
    )
    return st


def _request_trip(state: OrchestratorState) -> str:
    response, _ = contract.request_trip(
        state,
        {
            "riderId": "rider-1",
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LON,
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LON,
        },
        sender_id="rider-1",
    )
    return response["tripId"]


def test_update_fare_raises_the_offer_and_mutates_base_fare(state: OrchestratorState) -> None:
    trip_id = _request_trip(state)
    current_fare = state.trips[trip_id].base_fare
    new_fare = current_fare + 10.0

    response, pushes = contract.update_fare(
        state, {"tripId": trip_id, "new_fare": new_fare}, sender_id="rider-1"
    )

    assert response["status"] == "FareUpdated"
    assert response["tripId"] == trip_id
    assert response["base_fare"] == str(new_fare)
    assert state.trips[trip_id].base_fare == new_fare

    matching = [p for target, p in pushes if target == "drv-1" and p.get("action") == "rideOfferAvailable"]
    assert matching, f"expected a rideOfferAvailable push to drv-1, got: {pushes}"
    assert matching[0]["base_fare"] == str(new_fare)


def test_update_fare_rejects_a_fare_not_higher_than_current(state: OrchestratorState) -> None:
    trip_id = _request_trip(state)
    current_fare = state.trips[trip_id].base_fare

    with pytest.raises(contract.ContractError) as excinfo:
        contract.update_fare(state, {"tripId": trip_id, "new_fare": current_fare}, sender_id="rider-1")

    assert excinfo.value.detail == "New fare must exceed the current base fare."


def test_update_fare_rejects_once_a_driver_has_been_selected(state: OrchestratorState) -> None:
    trip_id = _request_trip(state)
    current_fare = state.trips[trip_id].base_fare
    contract.select_bid(state, {"tripId": trip_id, "driverId": "drv-1"}, sender_id=None)
    assert state.trips[trip_id].status == TripStatus.ACCEPTED

    with pytest.raises(contract.ContractError) as excinfo:
        contract.update_fare(
            state, {"tripId": trip_id, "new_fare": current_fare + 10.0}, sender_id="rider-1"
        )

    assert excinfo.value.error == "TripNoLongerAvailable"
