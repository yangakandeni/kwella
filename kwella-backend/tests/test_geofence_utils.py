"""
tests/test_geofence_utils.py
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Unit tests for the kwella geospatial proximity utilities.

Module under test: ``geofence_utils`` (kwella_shared Lambda layer)

Coverage targets
----------------
* ``calculate_distance`` — Haversine accuracy against known Cape Town
  coordinate pairs, symmetry property, identity (zero-distance), and
  pure-math correctness independent of any AWS service.
* ``is_inside_geofence`` — boundary semantics (≤ radius resolves True),
  inside / outside separation across the default 50 m fence, and the
  explicit ``radius_meters`` parameter.
* Input validation — ``ValueError`` for ``None``, ``bool``, non-numeric
  strings, ``NaN``, and ``±Inf`` inputs on every parameter position.
* Negative radius guard.

Reference coordinates (WGS-84 decimal degrees)
-----------------------------------------------
All geographic anchors are real Cape Town landmarks chosen for
unambiguous, widely published coordinate values:

    FORESHORE  -33.9165, 18.4274   (Cape Town CBD Foreshore)
    GREEN_PT   -33.9036, 18.3989   (Green Point, near DHL Newlands)
    V_A_WTRFT  -33.9032, 18.4196   (V&A Waterfront Clock Tower)

Governance compliance
---------------------
* Python 3.12 native type hints throughout.
* No hardcoded AWS identifiers or credentials.
* No I/O; all tests are pure-function and fully deterministic.
"""

from __future__ import annotations

import math

import pytest

from geofence_utils import (
    EARTH_RADIUS_M,
    calculate_distance,
    is_inside_geofence,
)


# ---------------------------------------------------------------------------
# Reference geographic anchors
# ---------------------------------------------------------------------------

# Cape Town CBD Foreshore — used as the primary "origin" in most tests.
_FORESHORE_LAT: float = -33.9165
_FORESHORE_LON: float = 18.4274

# Green Point (≈ 3.2 km west of the Foreshore)
_GREEN_PT_LAT: float = -33.9036
_GREEN_PT_LON: float = 18.3989

# V&A Waterfront Clock Tower (≈ 900 m north-west of the Foreshore)
_VA_LAT: float = -33.9032
_VA_LON: float = 18.4196

# Tiny offset that stays well inside a 50 m fence (≈ 1–2 m shift in lat).
_MICRO_LAT_OFFSET: float = 0.000015   # ~1.67 m northward
_MICRO_LON_OFFSET: float = 0.000015   # ~1.34 m eastward at this latitude


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _approx_distance_km(lat1, lon1, lat2, lon2) -> float:
    """Quick naïve equirectangular estimate used ONLY to sanity-check order of
    magnitude in tests — not as a ground-truth reference."""
    R = 6_371.0  # km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    x = dlon * math.cos(math.radians((lat1 + lat2) / 2))
    return R * math.sqrt(dlat ** 2 + x ** 2)


# ===========================================================================
# calculate_distance — accuracy tests
# ===========================================================================

class TestCalculateDistanceAccuracy:
    """Haversine accuracy validated against published Cape Town geography."""

    def test_foreshore_to_green_point_is_approximately_3000m(self):
        """Foreshore → Green Point is a well-known ~3.0 km stretch along the
        CBD waterfront. We verify it matches within an expected threshold.
        """
        dist = calculate_distance(
            _FORESHORE_LAT, _FORESHORE_LON,
            _GREEN_PT_LAT, _GREEN_PT_LON,
        )
        assert 2_900.0 <= dist <= 3_100.0, (
            f"Foreshore→Green Point expected ~3 000 m, got {dist:.1f} m"
        )

    def test_foreshore_to_va_waterfront_is_approximately_1600m(self):
        """Foreshore → V&A Waterfront is roughly 1.6 km north-west."""
        dist = calculate_distance(
            _FORESHORE_LAT, _FORESHORE_LON,
            _VA_LAT, _VA_LON,
        )
        assert 1_500.0 <= dist <= 1_800.0, (
            f"Foreshore→V&A expected ~1 600 m, got {dist:.1f} m"
        )

    def test_green_point_to_va_waterfront_is_approximately_1900m(self):
        """Green Point → V&A Waterfront spans roughly 1.9 km east."""
        dist = calculate_distance(
            _GREEN_PT_LAT, _GREEN_PT_LON,
            _VA_LAT, _VA_LON,
        )
        assert 1_800.0 <= dist <= 2_100.0, (
            f"Green Point→V&A expected ~1 900 m, got {dist:.1f} m"
        )

    def test_distance_uses_earth_radius_constant(self):
        """Output must scale with EARTH_RADIUS_M — verifies the constant is
        actually wired into the Haversine computation."""
        dist = calculate_distance(0.0, 0.0, 0.0, 1.0)
        # One degree of longitude at the equator = (2π × R) / 360
        expected = (2.0 * math.pi * EARTH_RADIUS_M) / 360.0
        assert dist == pytest.approx(expected, rel=1e-6)

    def test_returns_float(self):
        """Return type must always be float, never int."""
        result = calculate_distance(
            _FORESHORE_LAT, _FORESHORE_LON,
            _GREEN_PT_LAT, _GREEN_PT_LON,
        )
        assert isinstance(result, float)


# ===========================================================================
# calculate_distance — mathematical properties
# ===========================================================================

class TestCalculateDistanceProperties:
    """Fundamental invariants of a distance metric."""

    def test_identity_same_point_returns_zero(self):
        """Distance from a point to itself must be exactly 0.0."""
        dist = calculate_distance(
            _FORESHORE_LAT, _FORESHORE_LON,
            _FORESHORE_LAT, _FORESHORE_LON,
        )
        assert dist == pytest.approx(0.0, abs=1e-9)

    def test_symmetry_ab_equals_ba(self):
        """d(A, B) must equal d(B, A) — symmetry property."""
        d_ab = calculate_distance(
            _FORESHORE_LAT, _FORESHORE_LON,
            _GREEN_PT_LAT, _GREEN_PT_LON,
        )
        d_ba = calculate_distance(
            _GREEN_PT_LAT, _GREEN_PT_LON,
            _FORESHORE_LAT, _FORESHORE_LON,
        )
        assert d_ab == pytest.approx(d_ba, rel=1e-9)

    def test_result_is_non_negative(self):
        """Distance must always be ≥ 0."""
        assert calculate_distance(
            _FORESHORE_LAT, _FORESHORE_LON,
            _GREEN_PT_LAT, _GREEN_PT_LON,
        ) >= 0.0

    def test_north_pole_to_south_pole_is_half_circumference(self):
        """Poles are exactly π × R apart (half the Earth's circumference)."""
        dist = calculate_distance(90.0, 0.0, -90.0, 0.0)
        expected = math.pi * EARTH_RADIUS_M
        assert dist == pytest.approx(expected, rel=1e-6)

    def test_integer_coordinates_accepted(self):
        """Integer lat/lon values must be coerced to float without error."""
        dist = calculate_distance(0, 0, 0, 1)
        assert dist > 0.0

    def test_negative_coordinates_accepted(self):
        """Southern-hemisphere and western-longitude coordinates must work."""
        dist = calculate_distance(-33.0, -70.0, -34.0, -71.0)
        assert dist > 0.0


# ===========================================================================
# is_inside_geofence — boundary and semantic tests
# ===========================================================================

class TestIsInsideGeofenceSemantics:
    """Validates the ≤ radius_meters boundary contract and default fence."""

    def test_same_point_is_inside_fence(self):
        """A driver exactly at the target is always inside the geofence."""
        assert is_inside_geofence(
            _FORESHORE_LAT, _FORESHORE_LON,
            _FORESHORE_LAT, _FORESHORE_LON,
        ) is True

    def test_point_within_50m_is_inside_default_fence(self):
        """A point ~2 m from the target resolves True under the 50 m default."""
        lat_near = _FORESHORE_LAT + _MICRO_LAT_OFFSET
        lon_near = _FORESHORE_LON + _MICRO_LON_OFFSET
        assert is_inside_geofence(
            lat_near, lon_near,
            _FORESHORE_LAT, _FORESHORE_LON,
        ) is True

    def test_point_at_exact_boundary_is_inside_fence(self):
        """A point whose distance equals radius_meters exactly must return True
        (boundary is inclusive: distance ≤ radius)."""
        # Compute the exact distance and pass it as the radius.
        dist = calculate_distance(
            _FORESHORE_LAT, _FORESHORE_LON,
            _VA_LAT, _VA_LON,
        )
        assert is_inside_geofence(
            _FORESHORE_LAT, _FORESHORE_LON,
            _VA_LAT, _VA_LON,
            radius_meters=dist,
        ) is True

    def test_green_point_is_outside_default_50m_fence(self):
        """Green Point is ~3 km from the Foreshore — well outside a 50 m fence."""
        assert is_inside_geofence(
            _GREEN_PT_LAT, _GREEN_PT_LON,
            _FORESHORE_LAT, _FORESHORE_LON,
        ) is False

    def test_va_waterfront_is_outside_default_50m_fence(self):
        """V&A Waterfront is ~900 m away — outside the default 50 m fence."""
        assert is_inside_geofence(
            _VA_LAT, _VA_LON,
            _FORESHORE_LAT, _FORESHORE_LON,
        ) is False

    def test_explicit_large_radius_captures_distant_point(self):
        """With a sufficiently large radius, a distant point resolves True."""
        # Green Point is ~3 200 m away; a 4 000 m fence should contain it.
        assert is_inside_geofence(
            _GREEN_PT_LAT, _GREEN_PT_LON,
            _FORESHORE_LAT, _FORESHORE_LON,
            radius_meters=4_000.0,
        ) is True

    def test_explicit_small_radius_excludes_nearby_point(self):
        """A 1 m fence around the Foreshore excludes a point ~200 m north-west."""
        assert is_inside_geofence(
            _VA_LAT, _VA_LON,
            _FORESHORE_LAT, _FORESHORE_LON,
            radius_meters=1.0,
        ) is False

    def test_returns_bool_type(self):
        """Return type must be native bool, not int or other truthy value."""
        result = is_inside_geofence(
            _FORESHORE_LAT, _FORESHORE_LON,
            _FORESHORE_LAT, _FORESHORE_LON,
        )
        assert type(result) is bool  # noqa: E721 — strict type check intentional

    def test_zero_radius_only_matches_exact_same_point(self):
        """With radius_meters=0.0, only an identical point may return True."""
        # Identical coordinates → distance is 0.0 → 0.0 ≤ 0.0 is True.
        assert is_inside_geofence(
            _FORESHORE_LAT, _FORESHORE_LON,
            _FORESHORE_LAT, _FORESHORE_LON,
            radius_meters=0.0,
        ) is True

        # Any nearby point → distance > 0.0 → False.
        lat_near = _FORESHORE_LAT + _MICRO_LAT_OFFSET
        assert is_inside_geofence(
            lat_near, _FORESHORE_LON,
            _FORESHORE_LAT, _FORESHORE_LON,
            radius_meters=0.0,
        ) is False


# ===========================================================================
# Input validation — calculate_distance
# ===========================================================================

class TestCalculateDistanceValidation:
    """Strict safety edge cases: every invalid input must raise ValueError."""

    @pytest.mark.parametrize("bad_value, field", [
        (None,        "lat1"),
        (None,        "lon1"),
        (None,        "lat2"),
        (None,        "lon2"),
    ])
    def test_none_coordinate_raises_value_error(self, bad_value, field):
        """None in any coordinate position must raise ValueError."""
        coords: dict = {
            "lat1": _FORESHORE_LAT,
            "lon1": _FORESHORE_LON,
            "lat2": _GREEN_PT_LAT,
            "lon2": _GREEN_PT_LON,
        }
        coords[field] = bad_value
        with pytest.raises(ValueError, match=field):
            calculate_distance(**coords)

    @pytest.mark.parametrize("bad_value, field", [
        ("north",   "lat1"),
        ("18.42S",  "lon1"),
        ("--33.9",  "lat2"),
        ("",        "lon2"),
    ])
    def test_string_coordinate_raises_value_error(self, bad_value, field):
        """Non-numeric strings in any coordinate position must raise ValueError."""
        coords: dict = {
            "lat1": _FORESHORE_LAT,
            "lon1": _FORESHORE_LON,
            "lat2": _GREEN_PT_LAT,
            "lon2": _GREEN_PT_LON,
        }
        coords[field] = bad_value
        with pytest.raises(ValueError, match=field):
            calculate_distance(**coords)

    @pytest.mark.parametrize("bad_value, field", [
        (True,  "lat1"),
        (False, "lon2"),
    ])
    def test_bool_coordinate_raises_value_error(self, bad_value, field):
        """bool is a subclass of int but must be explicitly rejected."""
        coords: dict = {
            "lat1": _FORESHORE_LAT,
            "lon1": _FORESHORE_LON,
            "lat2": _GREEN_PT_LAT,
            "lon2": _GREEN_PT_LON,
        }
        coords[field] = bad_value
        with pytest.raises(ValueError, match=field):
            calculate_distance(**coords)

    @pytest.mark.parametrize("bad_value, field", [
        (float("nan"),  "lat1"),
        (float("inf"),  "lon1"),
        (float("-inf"), "lat2"),
    ])
    def test_non_finite_float_raises_value_error(self, bad_value, field):
        """NaN and ±Inf must be caught and reported, not silently propagated."""
        coords: dict = {
            "lat1": _FORESHORE_LAT,
            "lon1": _FORESHORE_LON,
            "lat2": _GREEN_PT_LAT,
            "lon2": _GREEN_PT_LON,
        }
        coords[field] = bad_value
        with pytest.raises(ValueError, match=field):
            calculate_distance(**coords)

    def test_list_coordinate_raises_value_error(self):
        """A list where a float is expected must raise ValueError."""
        with pytest.raises(ValueError, match="lat1"):
            calculate_distance(
                [-33.9165],  # type: ignore[arg-type]
                _FORESHORE_LON,
                _GREEN_PT_LAT,
                _GREEN_PT_LON,
            )

    def test_dict_coordinate_raises_value_error(self):
        """A dict where a float is expected must raise ValueError."""
        with pytest.raises(ValueError, match="lon2"):
            calculate_distance(
                _FORESHORE_LAT,
                _FORESHORE_LON,
                _GREEN_PT_LAT,
                {"value": 18.3989},  # type: ignore[arg-type]
            )


# ===========================================================================
# Input validation — is_inside_geofence
# ===========================================================================

class TestIsInsideGeofenceValidation:
    """Strict safety edge cases for is_inside_geofence."""

    def test_none_current_lat_raises_value_error(self):
        with pytest.raises(ValueError, match="lat1"):
            is_inside_geofence(None, _FORESHORE_LON, _GREEN_PT_LAT, _GREEN_PT_LON)  # type: ignore

    def test_none_current_lon_raises_value_error(self):
        with pytest.raises(ValueError, match="lon1"):
            is_inside_geofence(_FORESHORE_LAT, None, _GREEN_PT_LAT, _GREEN_PT_LON)  # type: ignore

    def test_none_target_lat_raises_value_error(self):
        with pytest.raises(ValueError, match="lat2"):
            is_inside_geofence(_FORESHORE_LAT, _FORESHORE_LON, None, _GREEN_PT_LON)  # type: ignore

    def test_none_target_lon_raises_value_error(self):
        with pytest.raises(ValueError, match="lon2"):
            is_inside_geofence(_FORESHORE_LAT, _FORESHORE_LON, _GREEN_PT_LAT, None)  # type: ignore

    def test_string_current_lat_raises_value_error(self):
        with pytest.raises(ValueError, match="lat1"):
            is_inside_geofence("cape-town", _FORESHORE_LON, _GREEN_PT_LAT, _GREEN_PT_LON)  # type: ignore

    def test_string_radius_raises_value_error(self):
        with pytest.raises(ValueError, match="radius_meters"):
            is_inside_geofence(
                _FORESHORE_LAT, _FORESHORE_LON,
                _GREEN_PT_LAT, _GREEN_PT_LON,
                radius_meters="fifty",  # type: ignore
            )

    def test_none_radius_raises_value_error(self):
        with pytest.raises(ValueError, match="radius_meters"):
            is_inside_geofence(
                _FORESHORE_LAT, _FORESHORE_LON,
                _GREEN_PT_LAT, _GREEN_PT_LON,
                radius_meters=None,  # type: ignore
            )

    def test_negative_radius_raises_value_error(self):
        """A negative radius is geometrically undefined and must be rejected."""
        with pytest.raises(ValueError, match="radius_meters"):
            is_inside_geofence(
                _FORESHORE_LAT, _FORESHORE_LON,
                _GREEN_PT_LAT, _GREEN_PT_LON,
                radius_meters=-10.0,
            )

    def test_nan_coordinate_raises_value_error(self):
        with pytest.raises(ValueError, match="lat1"):
            is_inside_geofence(
                float("nan"), _FORESHORE_LON,
                _GREEN_PT_LAT, _GREEN_PT_LON,
            )

    def test_bool_coordinate_raises_value_error(self):
        """bool masquerading as a coordinate must be rejected."""
        with pytest.raises(ValueError, match="lat1"):
            is_inside_geofence(
                True, _FORESHORE_LON,  # type: ignore
                _GREEN_PT_LAT, _GREEN_PT_LON,
            )
