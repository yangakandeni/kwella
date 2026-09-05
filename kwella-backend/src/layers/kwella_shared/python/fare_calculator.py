"""kwella — Server-Side Fare Calculation Engine.

Implements the dynamic passenger-scaled bidding formula from README.md §3A:

    total_fare = (flat_rate x 6 seats) + variable_fare(distance, passenger_count, time_of_day)

The flat rate is deliberately sourced from an environment variable rather
than hardcoded, since it moves with fuel-price hikes (README.md §3A) and
must be changeable at the config level without a code deploy.

The `flat_rate x 6 seats` term is a floor, not merely a starting point: the
variable component is always additive and non-negative, so the total can
never fall below it — mirroring the "special trip" pricing rule described in
README.md (a single passenger paying for all 6 seats costs the same as a
full flat-rate special trip).
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
from decimal import ROUND_HALF_UP, Decimal
from typing import Final

#: Number of physical seats in a standard amaphela (7-seater minus the driver).
SEATS_PER_VEHICLE: Final[int] = 6

#: South African Standard Time is a fixed UTC+2 offset with no DST.
_SAST_OFFSET: Final[timedelta] = timedelta(hours=2)

#: Distance-based rate, expressed as a fraction of the flat rate per km —
#: this keeps the per-km cost moving in lockstep with fuel-price-driven
#: flat_rate changes rather than needing its own separate config knob.
_PER_KM_RATE_FACTOR: Final[Decimal] = Decimal("0.50")

#: Extra per-passenger strain surcharge (beyond the first passenger),
#: expressed as a fraction of the flat rate.
_PER_EXTRA_PASSENGER_FACTOR: Final[Decimal] = Decimal("0.25")

#: Peak-hour (heavier traffic) surcharge multiplier applied to the distance
#: component. Peak windows: 06:00-09:00 and 16:00-19:00 SAST.
_PEAK_HOUR_MULTIPLIER: Final[Decimal] = Decimal("1.15")

#: Night-time risk premium (driver safety risk), expressed as a fraction of
#: the flat rate, added flat when the trip starts between 22:00 and 05:00 SAST.
_NIGHT_RISK_FACTOR: Final[Decimal] = Decimal("0.50")

_CENTS: Final[Decimal] = Decimal("0.01")


def get_flat_rate_zar() -> Decimal:
    """Read the config-level flat rate (ZAR, per passenger seat) from the environment.

    Sourced from ``KWELLA_FLAT_RATE_ZAR`` so it can be bumped without a
    redeploy when fuel prices rise. Defaults to R10.00 when unset.
    """
    raw = os.environ.get("KWELLA_FLAT_RATE_ZAR", "10.00")
    return Decimal(str(raw))


def _to_sast(request_time: datetime) -> datetime:
    if request_time.tzinfo is None:
        request_time = request_time.replace(tzinfo=timezone.utc)
    return request_time.astimezone(timezone.utc) + _SAST_OFFSET


def _is_peak_hour(local_time: datetime) -> bool:
    hour = local_time.hour
    return (6 <= hour < 9) or (16 <= hour < 19)


def _is_night_hour(local_time: datetime) -> bool:
    hour = local_time.hour
    return hour >= 22 or hour < 5


def calculate_trip_fare(
    distance_km: float | Decimal,
    passenger_count: int = 1,
    request_time: datetime | None = None,
    flat_rate: Decimal | None = None,
) -> Decimal:
    """Calculate the total trip fare, guaranteeing the `flat_rate x 6 seats` floor.

    Args:
        distance_km: Great-circle pickup-to-dropoff distance in kilometres.
        passenger_count: Passengers requested (1-6); clamped into that range.
        request_time: UTC timestamp the trip was requested at; defaults to now.
            Used only to evaluate peak/night time-of-day surcharges.
        flat_rate: Override for the configured flat rate; defaults to
            ``get_flat_rate_zar()``.

    Returns:
        The total fare in ZAR, quantized to the nearest cent.
    """
    effective_flat_rate = flat_rate if flat_rate is not None else get_flat_rate_zar()
    effective_passenger_count = max(1, min(int(passenger_count), SEATS_PER_VEHICLE))
    local_time = _to_sast(request_time or datetime.now(timezone.utc))

    floor_fare = effective_flat_rate * SEATS_PER_VEHICLE

    distance_component = _PER_KM_RATE_FACTOR * effective_flat_rate * Decimal(str(distance_km))
    if _is_peak_hour(local_time):
        distance_component *= _PEAK_HOUR_MULTIPLIER

    extra_passengers = effective_passenger_count - 1
    passenger_surcharge = _PER_EXTRA_PASSENGER_FACTOR * effective_flat_rate * extra_passengers

    night_risk_premium = effective_flat_rate * _NIGHT_RISK_FACTOR if _is_night_hour(local_time) else Decimal("0.00")

    variable_fare = distance_component + passenger_surcharge + night_risk_premium

    total_fare = floor_fare + variable_fare
    # Defensive floor enforcement per README.md §3A, even though variable_fare
    # is constructed to always be >= 0.
    total_fare = max(total_fare, floor_fare)

    return total_fare.quantize(_CENTS, rounding=ROUND_HALF_UP)


__all__ = [
    "SEATS_PER_VEHICLE",
    "calculate_trip_fare",
    "get_flat_rate_zar",
]
