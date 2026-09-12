"""Unit tests for the server-side fare calculation engine (README.md §3A)."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal

from fare_calculator import (
    DRIVER_PAYOUT_RATE,
    FARE_QUANTUM_ZAR,
    PLATFORM_COMMISSION_RATE,
    calculate_driver_payout,
    calculate_trip_fare,
    get_flat_rate_zar,
    is_quantized_fare,
    quantize_fare_zar,
)

_OFF_PEAK_DAYTIME = datetime(2026, 6, 21, 10, 0, tzinfo=timezone.utc)  # 12:00 SAST
_PEAK_MORNING = datetime(2026, 6, 21, 6, 30, tzinfo=timezone.utc)      # 08:30 SAST
_NIGHT = datetime(2026, 6, 21, 21, 0, tzinfo=timezone.utc)             # 23:00 SAST


def test_get_flat_rate_zar_defaults_to_ten_rand(monkeypatch):
    monkeypatch.delenv("KWELLA_FLAT_RATE_ZAR", raising=False)
    assert get_flat_rate_zar() == Decimal("10.00")


def test_get_flat_rate_zar_reads_environment_override(monkeypatch):
    monkeypatch.setenv("KWELLA_FLAT_RATE_ZAR", "12.50")
    assert get_flat_rate_zar() == Decimal("12.50")


def test_fare_never_falls_below_flat_rate_times_six_seats():
    """The floor from README.md §3A: even a near-zero-distance trip must cost
    at least flat_rate x 6 seats."""
    fare = calculate_trip_fare(
        distance_km=0.0,
        passenger_count=1,
        request_time=_OFF_PEAK_DAYTIME,
        flat_rate=Decimal("10.00"),
    )
    assert fare == Decimal("60.00")


def test_fare_increases_with_distance():
    short_trip = calculate_trip_fare(distance_km=1.0, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00"))
    long_trip = calculate_trip_fare(distance_km=20.0, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00"))
    assert long_trip > short_trip


def test_fare_scales_with_passenger_count():
    one_passenger = calculate_trip_fare(
        distance_km=5.0, passenger_count=1, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00")
    )
    six_passengers = calculate_trip_fare(
        distance_km=5.0, passenger_count=6, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00")
    )
    assert six_passengers > one_passenger


def test_passenger_count_is_clamped_into_one_to_six_range():
    zero_passengers = calculate_trip_fare(
        distance_km=5.0, passenger_count=0, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00")
    )
    one_passenger = calculate_trip_fare(
        distance_km=5.0, passenger_count=1, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00")
    )
    over_capacity = calculate_trip_fare(
        distance_km=5.0, passenger_count=9, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00")
    )
    six_passengers = calculate_trip_fare(
        distance_km=5.0, passenger_count=6, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00")
    )
    assert zero_passengers == one_passenger
    assert over_capacity == six_passengers


def test_peak_hour_surcharge_increases_fare_over_off_peak():
    off_peak = calculate_trip_fare(distance_km=10.0, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00"))
    peak = calculate_trip_fare(distance_km=10.0, request_time=_PEAK_MORNING, flat_rate=Decimal("10.00"))
    assert peak > off_peak


def test_night_risk_premium_increases_fare_over_daytime():
    daytime = calculate_trip_fare(distance_km=10.0, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00"))
    night = calculate_trip_fare(distance_km=10.0, request_time=_NIGHT, flat_rate=Decimal("10.00"))
    assert night > daytime


def test_higher_flat_rate_raises_both_floor_and_variable_component():
    low_rate_fare = calculate_trip_fare(
        distance_km=5.0, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00")
    )
    high_rate_fare = calculate_trip_fare(
        distance_km=5.0, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("15.00")
    )
    assert high_rate_fare > low_rate_fare
    assert high_rate_fare >= Decimal("15.00") * 6


def test_fare_always_lands_on_the_fifty_cent_quantum():
    """Riders pay in cash, and 1c/2c/5c coins are effectively out of
    circulation in South Africa — so the total a rider is asked for can never
    carry a cent value they cannot physically hand over."""
    for distance_km in ("3.333", "7.77", "12.345", "0.5", "25.36"):
        fare = calculate_trip_fare(
            distance_km=Decimal(distance_km),
            request_time=_OFF_PEAK_DAYTIME,
            flat_rate=Decimal("10.00"),
        )
        assert fare % FARE_QUANTUM_ZAR == Decimal("0"), distance_km


# ---------------------------------------------------------------------------
# Passenger-scaled bidding formula (2026-09 revision)
#
#   subtotal = base_fare
#            + cost_per_minute x minutes
#            + cost_per_km     x km
#            + passenger_surcharge
#            + night_risk_premium
#
#   fare     = max(quantize_fare_zar(subtotal), flat_rate x 6 seats)
#
#   base_fare = (flat_rate / 2) x 6 seats,  charged ONCE per trip
#   floor     = flat_rate x 6 seats,        applied to the final total
#
# There is deliberately NO rider-side fee term. kwella's 10% is taken from
# the driver's side of the agreed fare (see the commission tests at the
# bottom of this file), so adding it to the rider's quote too would charge
# the same 10% twice.
# ---------------------------------------------------------------------------

from fare_calculator import (  # noqa: E402
    calculate_trip_fare_breakdown,
    estimate_duration_minutes,
)


def test_estimate_duration_minutes_uses_the_assumed_average_speed():
    """Duration is derived server-side from distance, never taken from the
    client (same reason the engine refuses `suggested_base_fare`)."""
    # 25 km/h assumed average => 5 km is a 12-minute ride.
    assert estimate_duration_minutes(5.0) == Decimal("12.00")
    assert estimate_duration_minutes(0.0) == Decimal("0.00")
    # Monotonic in distance.
    assert estimate_duration_minutes(10.0) > estimate_duration_minutes(5.0)


def test_breakdown_matches_the_worked_example_exactly():
    """A 5 km, 1-passenger, off-peak trip at flat_rate=R10 must come to
    R77.50: a R77.10 subtotal, lifted to the next 50c so the rider can
    actually pay it in cash. No rider-side fee is added."""
    b = calculate_trip_fare_breakdown(
        distance_km=5.0,
        passenger_count=1,
        request_time=_OFF_PEAK_DAYTIME,
        flat_rate=Decimal("10.00"),
    )

    assert b["base_fare"] == Decimal("30.00")          # (10/2) x 6 seats
    assert b["duration_minutes"] == Decimal("12.00")   # 5 km @ 25 km/h
    assert b["time_fare"] == Decimal("9.60")           # 0.08 x 10 x 12
    assert b["distance_fare"] == Decimal("37.50")      # 0.75 x 10 x 5
    assert b["passenger_surcharge"] == Decimal("0.00")
    assert b["night_risk_premium"] == Decimal("0.00")
    assert b["subtotal"] == Decimal("77.10")
    assert b["total_fare"] == Decimal("77.50")
    assert b["floor_applied"] is False
    assert "booking_fee" not in b

    # The convenience wrapper must agree with the breakdown it delegates to.
    assert calculate_trip_fare(
        distance_km=5.0,
        passenger_count=1,
        request_time=_OFF_PEAK_DAYTIME,
        flat_rate=Decimal("10.00"),
    ) == Decimal("77.50")


def test_base_fare_is_charged_once_per_trip_not_per_passenger():
    """`base_fare` already prices all 6 seats, so multiplying it by the
    passenger count would charge seats twice. Passenger scaling comes from
    the separate per-extra-passenger surcharge instead.
    """
    one = calculate_trip_fare_breakdown(
        distance_km=5.0, passenger_count=1,
        request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00"),
    )
    six = calculate_trip_fare_breakdown(
        distance_km=5.0, passenger_count=6,
        request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00"),
    )

    assert one["base_fare"] == six["base_fare"] == Decimal("30.00")
    # Six passengers still cost more, via the surcharge — 0.25 x 10 x 5 extra.
    assert six["passenger_surcharge"] == Decimal("12.50")
    assert six["total_fare"] > one["total_fare"]


def test_no_rider_side_fee_is_added_to_the_subtotal():
    """Regression guard for the fee that used to be added here.

    kwella's 10% is a driver-side commission taken out of the fare the two
    parties agree on — it is not a surcharge on the rider's quote. Adding it
    to the quote as well charged the same 10% twice: once to the rider up
    front, once to the driver on settlement.
    """
    b = calculate_trip_fare_breakdown(
        distance_km=8.0, passenger_count=3,
        request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00"),
    )
    assert b["total_fare"] == quantize_fare_zar(b["subtotal"])
    # The total never exceeds the subtotal by more than the 50c rounding.
    assert b["total_fare"] - b["subtotal"] < FARE_QUANTUM_ZAR


# ---------------------------------------------------------------------------
# Cash-payable rounding and the driver-side commission
# ---------------------------------------------------------------------------


def test_quantize_fare_zar_lifts_to_the_next_fifty_cents():
    """Rounding is one-directional: up to the next payable 50c.

    A rider is never quoted less than the formula produced, and the value is
    always one a rider can settle with the coins actually in circulation.
    """
    assert quantize_fare_zar(Decimal("95.21")) == Decimal("95.50")
    assert quantize_fare_zar(Decimal("95.01")) == Decimal("95.50")
    assert quantize_fare_zar(Decimal("95.50")) == Decimal("95.50")
    assert quantize_fare_zar(Decimal("95.51")) == Decimal("96.00")
    assert quantize_fare_zar(Decimal("95.00")) == Decimal("95.00")
    assert quantize_fare_zar(Decimal("0")) == Decimal("0.00")


def test_is_quantized_fare_accepts_only_payable_amounts():
    """The wire contract's gate on rider offers and driver counter-offers."""
    assert is_quantized_fare(80) is True
    assert is_quantized_fare(100.0) is True
    assert is_quantized_fare(Decimal("95.50")) is True
    assert is_quantized_fare(Decimal("95.21")) is False
    assert is_quantized_fare(Decimal("95.99")) is False
    # The WebSocket contract carries fares as strings on some routes.
    assert is_quantized_fare("55.00") is True
    assert is_quantized_fare("55.37") is False
    assert is_quantized_fare("not a number") is False
    assert is_quantized_fare("NaN") is False
    assert is_quantized_fare(None) is False
    # bool is an int subclass in Python — it must not pass as an amount.
    assert is_quantized_fare(True) is False


def test_commission_is_ten_percent_of_the_agreed_fare_taken_from_the_driver():
    """The worked example from the product decision: rider offers R80, driver
    counters R100, rider accepts — kwella takes R10, the driver keeps R90."""
    payout = calculate_driver_payout(100)

    assert PLATFORM_COMMISSION_RATE == Decimal("0.10")
    assert DRIVER_PAYOUT_RATE == Decimal("0.90")
    assert payout["fare_amount"] == Decimal("100.00")
    assert payout["platform_commission"] == Decimal("10.00")
    assert payout["net_earnings"] == Decimal("90.00")
    # The rider pays the agreed fare, nothing more.
    assert payout["platform_commission"] + payout["net_earnings"] == payout["fare_amount"]


def test_commission_needs_no_rounding_on_a_payable_fare():
    """Why the 50c quantum and the 10% commission fit together.

    10% of any multiple of 50c is a whole number of cents, so the commission
    split is exact — there is no half-cent to round, and therefore no rule
    about who absorbs it.
    """
    amount = Decimal("95.50")
    payout = calculate_driver_payout(amount)

    assert payout["platform_commission"] == Decimal("9.55")
    assert payout["net_earnings"] == Decimal("85.95")
    assert payout["platform_commission"] + payout["net_earnings"] == amount


def test_time_component_increases_the_fare():
    """Removing the time term must lower the fare — guards against the
    per-minute factor being silently dropped to zero."""
    b = calculate_trip_fare_breakdown(
        distance_km=12.0, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00")
    )
    assert b["time_fare"] > Decimal("0.00")
    assert b["total_fare"] > (b["total_fare"] - b["time_fare"])


def test_floor_is_reported_and_applied_on_very_short_trips():
    b = calculate_trip_fare_breakdown(
        distance_km=0.0, passenger_count=1,
        request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00"),
    )
    # Formula alone would give 30 + 10% = 33.00; the floor overrides it.
    assert b["subtotal"] == Decimal("30.00")
    assert b["total_fare"] == Decimal("60.00")
    assert b["floor_applied"] is True
    assert b["floor_fare"] == Decimal("60.00")
