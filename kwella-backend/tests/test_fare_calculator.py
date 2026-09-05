"""Unit tests for the server-side fare calculation engine (README.md §3A)."""

from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal

from fare_calculator import calculate_trip_fare, get_flat_rate_zar

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


def test_fare_is_quantized_to_the_nearest_cent():
    fare = calculate_trip_fare(distance_km=3.333, request_time=_OFF_PEAK_DAYTIME, flat_rate=Decimal("10.00"))
    assert fare == fare.quantize(Decimal("0.01"))
