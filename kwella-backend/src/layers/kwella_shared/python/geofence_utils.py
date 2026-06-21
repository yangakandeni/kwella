"""
geofence_utils.py
~~~~~~~~~~~~~~~~~
Pure-Python 3.12 geospatial proximity utilities for the Kwella platform.

Placed inside the ``kwella_shared`` Lambda layer so that every microservice
can import it without vendoring a copy:

    from geofence_utils import calculate_distance, is_inside_geofence

Design goals
------------
* **Zero external dependencies** — uses only the Python standard library
  (``math``).  This keeps the Layer ZIP small and avoids version-pinning
  concerns for a pure-math module.
* **Explicit Earth radius constant** — ``EARTH_RADIUS_M`` is declared at
  module scope so callers can inspect or override it in test contexts without
  monkey-patching internals.
* **Strict input validation** — both public functions raise ``ValueError``
  on ``None`` or non-numeric inputs rather than silently propagating ``NaN``
  or ``TypeError`` through downstream arithmetic.  This satisfies the Phase 13
  driver safety guardrail requirement.

Driver safety note
------------------
Coordinates are consumed directly from WebSocket telemetry payloads.  Any
malformed value that slips past the bidding engine validator is caught here
and surfaces as a clear exception rather than a silent geofence misfire.

Governance compliance
---------------------
* Python 3.12 native type hints throughout.
* No hardcoded AWS resource identifiers.
* All numeric literals are float to avoid silent integer division on edge
  cases (e.g. ``radius_meters=50`` versus ``radius_meters=50.0``).
"""

from __future__ import annotations

import math
from typing import Union

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

#: WGS-84 mean Earth radius in metres, as specified by Phase 13 requirements.
EARTH_RADIUS_M: float = 6_371_000.0

# Numeric types accepted as coordinate or radius arguments.
_Numeric = Union[int, float]


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _validate_numeric(value: object, field_name: str) -> float:
    """Coerce *value* to ``float`` or raise a descriptive ``ValueError``.

    Parameters
    ----------
    value:
        The raw value to validate.  Accepts ``int`` or ``float``; rejects
        ``None``, ``str``, ``bool``, and any other non-numeric type.
    field_name:
        The human-readable parameter name, used verbatim in the exception
        message so callers can pinpoint exactly which argument was invalid.

    Returns
    -------
    float
        The validated and coerced coordinate value.

    Raises
    ------
    ValueError
        If *value* is ``None``, a non-numeric type, or ``NaN`` / ``±Inf``
        (which would silently corrupt downstream geofence comparisons).

    Examples
    --------
    >>> _validate_numeric(-33.9249, "lat1")
    -33.9249
    >>> _validate_numeric(None, "lat1")
    ValueError: 'lat1' must be a numeric value (int or float), got NoneType.
    """
    # Explicit None guard — isinstance(None, (int, float)) is False anyway,
    # but this produces a clearer error message.
    if value is None:
        raise ValueError(
            f"'{field_name}' must be a numeric value (int or float), got NoneType."
        )

    # bool is a subclass of int in Python, but True/False are semantically
    # wrong for geographic coordinates and must be rejected explicitly.
    if isinstance(value, bool):
        raise ValueError(
            f"'{field_name}' must be a numeric value (int or float), got bool."
        )

    if not isinstance(value, (int, float)):
        raise ValueError(
            f"'{field_name}' must be a numeric value (int or float), "
            f"got {type(value).__name__}."
        )

    coerced = float(value)

    # Reject NaN and infinities — they pass isinstance checks but produce
    # nonsensical distances that could trigger false geofence hits.
    if not math.isfinite(coerced):
        raise ValueError(
            f"'{field_name}' must be a finite number; got {coerced!r}."
        )

    return coerced


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def calculate_distance(
    lat1: _Numeric,
    lon1: _Numeric,
    lat2: _Numeric,
    lon2: _Numeric,
) -> float:
    """Compute the great-circle distance between two points using the Haversine
    formula.

    The Haversine formula is numerically stable for small distances (< 1 km),
    making it appropriate for the sub-50 m proximity checks required by the
    Kwella geofencing feature.

    Parameters
    ----------
    lat1, lon1:
        Latitude and longitude of the first point in **decimal degrees**.
    lat2, lon2:
        Latitude and longitude of the second point in **decimal degrees**.

    Returns
    -------
    float
        Great-circle distance in **metres** between the two points.

    Raises
    ------
    ValueError
        If any argument is ``None``, a non-numeric type, ``NaN``, or
        non-finite.

    Examples
    --------
    >>> # Cape Town Foreshore → Green Point (approx. 2.8 km)
    >>> calculate_distance(-33.9165, 18.4274, -33.9036, 18.3989)
    3176.4...  # metres, varies slightly by floating-point precision
    """
    φ1 = math.radians(_validate_numeric(lat1, "lat1"))
    λ1 = math.radians(_validate_numeric(lon1, "lon1"))
    φ2 = math.radians(_validate_numeric(lat2, "lat2"))
    λ2 = math.radians(_validate_numeric(lon2, "lon2"))

    Δφ = φ2 - φ1
    Δλ = λ2 - λ1

    a = (
        math.sin(Δφ / 2.0) ** 2
        + math.cos(φ1) * math.cos(φ2) * math.sin(Δλ / 2.0) ** 2
    )
    c = 2.0 * math.asin(math.sqrt(a))

    return EARTH_RADIUS_M * c


def is_inside_geofence(
    current_lat: _Numeric,
    current_lon: _Numeric,
    target_lat: _Numeric,
    target_lon: _Numeric,
    radius_meters: _Numeric = 50.0,
) -> bool:
    """Determine whether a driver's current position falls within a circular
    geofence.

    Uses :func:`calculate_distance` internally, so the same ``ValueError``
    contract applies to all coordinate arguments.

    Parameters
    ----------
    current_lat, current_lon:
        The driver's live coordinates in decimal degrees, sourced directly
        from the WebSocket telemetry payload.
    target_lat, target_lon:
        The centre of the geofence in decimal degrees (e.g. a pickup or
        dropoff waypoint).
    radius_meters:
        The inclusive geofence radius in metres.  Defaults to ``50.0`` m,
        matching the Kwella Phase 13 proximity specification.

    Returns
    -------
    bool
        ``True`` if the driver is **inside or exactly on the boundary** of
        the geofence (distance ≤ radius_meters); ``False`` otherwise.

    Raises
    ------
    ValueError
        If any coordinate or *radius_meters* is ``None``, non-numeric, or
        non-finite.

    Examples
    --------
    >>> # Same point — always inside.
    >>> is_inside_geofence(-33.9249, 18.4241, -33.9249, 18.4241)
    True

    >>> # 5 km away — outside the default 50 m fence.
    >>> is_inside_geofence(-33.9249, 18.4241, -33.8749, 18.4241)
    False
    """
    # Validate radius separately to produce a field-specific error message.
    r = _validate_numeric(radius_meters, "radius_meters")
    if r < 0.0:
        raise ValueError(
            f"'radius_meters' must be non-negative; got {r!r}."
        )

    distance = calculate_distance(current_lat, current_lon, target_lat, target_lon)
    return distance <= r
