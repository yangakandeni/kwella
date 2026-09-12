"""kwella — Server-Side Fare Calculation Engine.

Implements the passenger-scaled bidding formula (2026-09 revision):

    subtotal = base_fare
             + (cost_per_minute x duration_minutes)
             + (cost_per_km     x distance_km)
             + passenger_surcharge
             + night_risk_premium

    total_fare = max(quantize_fare_zar(subtotal), flat_rate x 6 seats)

where:

    base_fare = (flat_rate / 2) x 6 SEATS    ... R30.00 at flat_rate=R10

There is deliberately **no rider-side fee term**. kwella's 10% is a
*driver-side* commission, deducted from the fare the two parties agree on
(see :data:`PLATFORM_COMMISSION_RATE` and :func:`calculate_driver_payout`):
a rider who offers R80 against a driver's R100 counter pays R100, kwella
takes R10 of it and the driver banks R90. An earlier revision also added
10% on top of the rider's quote, which charged the same commission twice.

Three properties of this engine matter more than the arithmetic:

1. **Everything is a factor of `flat_rate`.** The flat rate is sourced from
   an environment variable rather than hardcoded because it moves with
   fuel-price hikes (README.md §3A), and every other rate is expressed as a
   fraction of it. A fuel hike is therefore a single config change, not a
   code deploy touching four separate rate constants.

2. **`base_fare` is charged once per trip, not per passenger.** The
   `x 6 SEATS` term already prices the whole vehicle, so multiplying it by
   the passenger count would charge for the same seats twice. Passenger
   scaling lives in `_PER_EXTRA_PASSENGER_FACTOR` instead.

3. **Every rider-facing amount lands on a R0.50 quantum.** Most kwella
   trips settle in cash, and 1c/2c/5c coins are effectively out of
   circulation in South Africa, so a R95.21 fare is a fare nobody can
   actually hand over. :func:`quantize_fare_zar` lifts amounts to the next
   50c — never down, so the driver is never quoted short — and
   :func:`is_quantized_fare` is the gate the wire contract applies to rider
   offers and driver counter-offers. A convenient consequence: 10% of any
   multiple of 50c is a whole number of cents, so the commission split
   below is exact and needs no rounding rule of its own.

The `flat_rate x 6 seats` term is a floor on the *final* total, mirroring
the "special trip" rule in README.md: a single passenger paying for all 6
seats costs the same as a full flat-rate special trip. It only binds on very
short hops — anything past roughly 1.5 km clears it on the formula alone.

Duration is **derived from distance here on the server**, never taken from
the client. The engine refuses to trust a client-supplied
`suggested_base_fare` for exactly this reason, and a client-supplied trip
duration would reopen the same hole. `KwellaFareEstimator` in `kwella_core`
mirrors this file term for term so the fare a rider is quoted in the app is
the fare the server will actually broadcast.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
from decimal import ROUND_CEILING, ROUND_HALF_UP, Decimal
from typing import Any, Final

#: Number of physical seats in a standard amaphela (7-seater minus the driver).
SEATS_PER_VEHICLE: Final[int] = 6

#: South African Standard Time is a fixed UTC+2 offset with no DST.
_SAST_OFFSET: Final[timedelta] = timedelta(hours=2)

#: Per-trip base fare, as a fraction of the flat rate, before the seat
#: multiplier below is applied: (flat_rate / 2) x 6 seats.
_BASE_FARE_FACTOR: Final[Decimal] = Decimal("0.50")

#: Distance-based rate, expressed as a fraction of the flat rate per km.
_PER_KM_RATE_FACTOR: Final[Decimal] = Decimal("0.75")

#: Time-based rate, expressed as a fraction of the flat rate per minute.
_PER_MINUTE_RATE_FACTOR: Final[Decimal] = Decimal("0.08")

#: Assumed average road speed (km/h) used to derive trip duration from
#: distance. Tuned for Philippi/Nyanga/Gugulethu township roads, which are
#: materially slower than the Cape Town arterials.
_ASSUMED_AVERAGE_SPEED_KMH: Final[Decimal] = Decimal("25")

#: Extra per-passenger strain surcharge (beyond the first passenger),
#: expressed as a fraction of the flat rate.
_PER_EXTRA_PASSENGER_FACTOR: Final[Decimal] = Decimal("0.25")

#: Peak-hour (heavier traffic) surcharge multiplier applied to the distance
#: and time components. Peak windows: 06:00-09:00 and 16:00-19:00 SAST.
_PEAK_HOUR_MULTIPLIER: Final[Decimal] = Decimal("1.15")

#: Night-time risk premium (driver safety risk), expressed as a fraction of
#: the flat rate, added flat when the trip starts between 22:00 and 05:00 SAST.
_NIGHT_RISK_FACTOR: Final[Decimal] = Decimal("0.50")

_CENTS: Final[Decimal] = Decimal("0.01")

#: The coin granularity every rider-facing amount is expressed in. See point
#: 3 of the module docstring for why it is 50c and not 1c.
FARE_QUANTUM_ZAR: Final[Decimal] = Decimal("0.50")

#: kwella's cut, taken from the **driver's** side of the agreed fare on
#: settlement — never added to the rider's quote.
#:
#: This is the rate the cancellation-debt "platform fee holiday" waives
#: (README.md §3B): a driver owed money by a late-cancelling rider keeps
#: 100% of subsequent fares until the debt is balanced.
PLATFORM_COMMISSION_RATE: Final[Decimal] = Decimal("0.10")

#: What the driver banks: the agreed fare less the commission above.
DRIVER_PAYOUT_RATE: Final[Decimal] = Decimal("1") - PLATFORM_COMMISSION_RATE


def quantize_fare_zar(amount: float | Decimal) -> Decimal:
    """Lift ``amount`` to the next payable multiple of R0.50.

    Deliberately one-directional. Rounding to *nearest* would sometimes quote
    under the formula's own answer, which on a cash trip means the driver
    hands back change out of their own earnings; rounding up caps the rider's
    exposure at 49c and keeps the quote at or above what the engine priced.
    """
    value = Decimal(str(amount))
    steps = (value / FARE_QUANTUM_ZAR).to_integral_value(rounding=ROUND_CEILING)
    return (steps * FARE_QUANTUM_ZAR).quantize(_CENTS)


def is_quantized_fare(amount: Any) -> bool:
    """True when ``amount`` is a number a rider could actually pay in cash.

    The gate for every client-named amount on the wire — rider offers via
    ``updateFare``, driver counter-offers via ``sendBid``. Rejecting these at
    the edge is what keeps un-payable cent values (and the change-making
    argument at the kerb that follows) out of the trip record entirely.

    Numeric strings are accepted because the WebSocket contract carries fares
    both ways (``sendBid``'s ``counter_fare`` is a string, ``updateFare``'s
    ``new_fare`` a number); ``bool`` is rejected despite being an ``int``
    subclass, so a stray ``True`` cannot read as R1.
    """
    if isinstance(amount, bool) or not isinstance(amount, (int, float, Decimal, str)):
        return False
    try:
        value = Decimal(str(amount))
    except (ArithmeticError, ValueError):
        return False
    if not value.is_finite():
        return False
    return value == value.quantize(_CENTS) and value % FARE_QUANTUM_ZAR == 0


def calculate_driver_payout(fare_amount: float | Decimal) -> dict[str, Decimal]:
    """Split an agreed fare into kwella's commission and the driver's payout.

    ``fare_amount`` is the amount the rider and driver settled on — the
    rider's offer if the driver accepted it outright, or the driver's
    counter-offer if the rider accepted that. The rider pays exactly this;
    the commission comes out of the driver's side of it.

    The split is exact on any amount :func:`is_quantized_fare` accepts, so
    the two returned components always sum back to ``fare_amount``.
    """
    amount = Decimal(str(fare_amount)).quantize(_CENTS, rounding=ROUND_HALF_UP)
    net_earnings = (amount * DRIVER_PAYOUT_RATE).quantize(_CENTS, rounding=ROUND_HALF_UP)
    return {
        "fare_amount": amount,
        # Derived by subtraction rather than computed independently, so the
        # two halves can never drift apart on an off-quantum legacy amount.
        "platform_commission": amount - net_earnings,
        "net_earnings": net_earnings,
    }


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


def estimate_duration_minutes(distance_km: float | Decimal) -> Decimal:
    """Derive expected trip duration (minutes) from distance, server-side.

    Deliberately not sourced from the client or from a Directions API call:
    keeping it a pure function of distance means the rider's in-app quote and
    the server's authoritative broadcast agree exactly, with no network call
    on the hot `requestTrip` path.
    """
    minutes = (Decimal(str(distance_km)) / _ASSUMED_AVERAGE_SPEED_KMH) * Decimal("60")
    return minutes.quantize(_CENTS, rounding=ROUND_HALF_UP)


def calculate_trip_fare_breakdown(
    distance_km: float | Decimal,
    passenger_count: int = 1,
    request_time: datetime | None = None,
    flat_rate: Decimal | None = None,
) -> dict[str, Any]:
    """Calculate the trip fare and return every component that produced it.

    Args:
        distance_km: Great-circle pickup-to-dropoff distance in kilometres.
        passenger_count: Passengers requested (1-6); clamped into that range.
        request_time: UTC timestamp the trip was requested at; defaults to now.
            Used only to evaluate peak/night time-of-day surcharges.
        flat_rate: Override for the configured flat rate; defaults to
            ``get_flat_rate_zar()``.

    Returns:
        A dict of Decimal components — ``base_fare``, ``time_fare``,
        ``distance_fare``, ``passenger_surcharge``, ``night_risk_premium``,
        ``subtotal``, ``total_fare``, ``floor_fare``, plus
        ``duration_minutes`` and a ``floor_applied`` bool. The components are
        quantized to the nearest cent; ``total_fare`` is lifted to the R0.50
        the rider actually pays.

    The breakdown exists so receipts and the rider's fare sheet can explain
    the number rather than just assert it — a rider who can see R37.50 of
    distance in an R77.50 total is far less likely to read it as arbitrary.
    """
    effective_flat_rate = flat_rate if flat_rate is not None else get_flat_rate_zar()
    effective_passenger_count = max(1, min(int(passenger_count), SEATS_PER_VEHICLE))
    local_time = _to_sast(request_time or datetime.now(timezone.utc))
    peak = _is_peak_hour(local_time)

    duration_minutes = estimate_duration_minutes(distance_km)

    # Charged once per trip: the x 6 SEATS term already prices the vehicle.
    base_fare = _BASE_FARE_FACTOR * effective_flat_rate * SEATS_PER_VEHICLE

    distance_fare = _PER_KM_RATE_FACTOR * effective_flat_rate * Decimal(str(distance_km))
    time_fare = _PER_MINUTE_RATE_FACTOR * effective_flat_rate * duration_minutes
    if peak:
        # Peak traffic costs the driver both distance and time, so it lifts
        # both components rather than distance alone.
        distance_fare *= _PEAK_HOUR_MULTIPLIER
        time_fare *= _PEAK_HOUR_MULTIPLIER

    extra_passengers = effective_passenger_count - 1
    passenger_surcharge = _PER_EXTRA_PASSENGER_FACTOR * effective_flat_rate * extra_passengers

    night_risk_premium = (
        effective_flat_rate * _NIGHT_RISK_FACTOR if _is_night_hour(local_time) else Decimal("0")
    )

    def _cents(value: Decimal) -> Decimal:
        return value.quantize(_CENTS, rounding=ROUND_HALF_UP)

    base_fare = _cents(base_fare)
    distance_fare = _cents(distance_fare)
    time_fare = _cents(time_fare)
    passenger_surcharge = _cents(passenger_surcharge)
    night_risk_premium = _cents(night_risk_premium)

    subtotal = _cents(
        base_fare + time_fare + distance_fare + passenger_surcharge + night_risk_premium
    )

    floor_fare = quantize_fare_zar(effective_flat_rate * SEATS_PER_VEHICLE)
    formula_total = quantize_fare_zar(subtotal)
    total_fare = max(formula_total, floor_fare)

    return {
        "base_fare": base_fare,
        "duration_minutes": duration_minutes,
        "time_fare": time_fare,
        "distance_fare": distance_fare,
        "passenger_surcharge": passenger_surcharge,
        "night_risk_premium": night_risk_premium,
        "subtotal": subtotal,
        "total_fare": total_fare,
        "floor_fare": floor_fare,
        "floor_applied": total_fare > formula_total,
        "peak_hour": peak,
    }


def calculate_trip_fare(
    distance_km: float | Decimal,
    passenger_count: int = 1,
    request_time: datetime | None = None,
    flat_rate: Decimal | None = None,
) -> Decimal:
    """Total trip fare in ZAR, quantized to the nearest cent.

    Thin wrapper over :func:`calculate_trip_fare_breakdown` for the many
    call sites that only need the final number.
    """
    return calculate_trip_fare_breakdown(
        distance_km=distance_km,
        passenger_count=passenger_count,
        request_time=request_time,
        flat_rate=flat_rate,
    )["total_fare"]


__all__ = [
    "DRIVER_PAYOUT_RATE",
    "FARE_QUANTUM_ZAR",
    "PLATFORM_COMMISSION_RATE",
    "SEATS_PER_VEHICLE",
    "calculate_driver_payout",
    "calculate_trip_fare",
    "calculate_trip_fare_breakdown",
    "estimate_duration_minutes",
    "get_flat_rate_zar",
    "is_quantized_fare",
    "quantize_fare_zar",
]
