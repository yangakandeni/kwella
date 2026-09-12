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


def test_update_fare_rejects_a_fare_off_the_cash_quantum(state: OrchestratorState) -> None:
    """Mirrors the real handler's gate — a fare nobody can pay in coins never
    reaches the driver pool, whichever backend the app is pointed at."""
    trip_id = _request_trip(state)
    current_fare = state.trips[trip_id].base_fare

    with pytest.raises(contract.ContractError) as excinfo:
        contract.update_fare(
            state, {"tripId": trip_id, "new_fare": current_fare + 10.37}, sender_id="rider-1"
        )

    assert "0.50" in excinfo.value.detail
    # Rejected before the trip was mutated.
    assert state.trips[trip_id].base_fare == current_fare


def test_send_bid_rejects_a_counter_offer_off_the_cash_quantum(state: OrchestratorState) -> None:
    trip_id = _request_trip(state)

    with pytest.raises(contract.ContractError) as excinfo:
        contract.send_bid(
            state, {"tripId": trip_id, "driverId": "drv-1", "amount": 95.37}, sender_id="drv-1"
        )

    assert "0.50" in excinfo.value.detail
    assert state.trips[trip_id].bids == {}


def test_confirm_arrival_takes_ten_percent_from_the_driver(state: OrchestratorState) -> None:
    """The product's worked example: rider offers R80, driver counters R100,
    rider accepts — kwella takes R10 and the driver banks R90."""
    trip_id = _request_trip(state)
    contract.send_bid(
        state, {"tripId": trip_id, "driverId": "drv-1", "amount": 100.0}, sender_id="drv-1"
    )
    contract.select_bid(state, {"tripId": trip_id, "driverId": "drv-1"}, sender_id=None)
    contract.driver_arrived(state, {"tripId": trip_id}, sender_id="drv-1")
    contract.start_trip(state, {"tripId": trip_id, "driverId": "drv-1"}, sender_id="drv-1")

    response, _pushes = contract.confirm_arrival(
        state,
        {"tripId": trip_id, "driverId": "drv-1", "final_bid_amount": 100.0},
        sender_id="drv-1",
    )

    assert response["net_earnings"] == 90.0
    assert state.receipts[trip_id].platform_fee == 10.0
    assert state.receipts[trip_id].net_driver_earnings == 90.0
    # The rider is charged the agreed fare and nothing more.
    assert state.receipts[trip_id].fare_amount == 100.0


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


def test_request_trip_records_and_broadcasts_the_payment_method(
    state: OrchestratorState,
) -> None:
    """The rider's payment choice must reach the trip record and the driver
    offer — mirrors `test_request_trip_persists_rider_payment_method` in the
    real backend suite.
    """
    response, pushes = contract.request_trip(
        state,
        {
            "riderId": "rider-1",
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LON,
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LON,
            "payment_method": "CASH",
        },
        sender_id="rider-1",
    )

    assert response["payment_method"] == "CASH"
    assert state.trips[response["tripId"]].payment_method == "CASH"

    offers = [p for _, p in pushes if p.get("action") == "rideOfferAvailable"]
    assert offers, f"expected a rideOfferAvailable push, got: {pushes}"
    assert offers[0]["payment_method"] == "CASH"


@pytest.mark.parametrize(
    ("supplied", "expected"),
    [(None, "CASH"), ("EFT", "CASH"), ("", "CASH"), ("card", "CARD")],
)
def test_request_trip_normalises_unknown_payment_methods(
    state: OrchestratorState, supplied: str | None, expected: str
) -> None:
    payload = {
        "riderId": "rider-1",
        "pickup_latitude": PICKUP_LAT,
        "pickup_longitude": PICKUP_LON,
        "dropoff_latitude": DROPOFF_LAT,
        "dropoff_longitude": DROPOFF_LON,
    }
    if supplied is not None:
        payload["payment_method"] = supplied

    response, _ = contract.request_trip(state, payload, sender_id="rider-1")

    assert response["payment_method"] == expected
    assert state.trips[response["tripId"]].payment_method == expected


def test_mock_fare_agrees_with_the_real_server_engine() -> None:
    """Regression guard for the R60 -> R150 jump testers used to see locally.

    This module once carried its own fare formula with a hardcoded
    flat_rate of R25, giving a floor of R150 where the deployed engine's
    floor is R60. Local testing therefore showed a fare the real backend
    would never broadcast. `calculate_trip_fare` now delegates to
    `fare_calculator`, so the two can no longer diverge.
    """
    from decimal import Decimal

    from fare_calculator import calculate_trip_fare as real_calculate_trip_fare

    for distance_km, passengers in ((0.0, 1), (2.5, 1), (12.0, 4), (25.0, 6)):
        assert contract.calculate_trip_fare(distance_km, passengers) == float(
            real_calculate_trip_fare(
                distance_km=distance_km, passenger_count=passengers
            )
        ), f"mock/real fare mismatch at {distance_km} km, {passengers} pax"

    # And specifically: a zero-distance trip floors at flat_rate x 6 = R60,
    # not the old R150.
    assert contract.calculate_trip_fare(0.0, 1) == 60.00
    assert Decimal(str(contract.calculate_trip_fare(0.0, 1))) == Decimal("60.00")
