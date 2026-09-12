import 'package:flutter/foundation.dart';

/// Immutable value-object representing a ride offer broadcast from the
/// Kwella marketplace to an active driver.
///
/// There is exactly one `rideOfferAvailable` payload shape in the stack,
/// sent over WebSocket by `kwella-backend/src/lambdas/bidding_engine/
/// handler.py`'s `_dispatch_ride_offer_to_matched_drivers` and mirrored
/// field-for-field by `scripts/mock_orchestrator/contract.py`:
///
/// ```json
/// {
///   "action": "rideOfferAvailable",
///   "tripId": "TRIP#abc-123",
///   "rider_id": "USR#rider-001",
///   "pickup_location": [-33.9249, 18.4241],
///   "dropoff_location": [-33.9581, 18.6961],
///   "passenger_count": 3,
///   "base_fare": "45.50",
///   "expires_in_seconds": 15
/// }
/// ```
///
/// Note there are no address strings anywhere in it, `base_fare` is a
/// string, and the offline FCM fallback (`_send_fcm_push_via_sns` in the
/// same handler) carries only `action`/`tripId`/`base_fare` — hence the
/// nullable coordinates and the derived [pickupLocation]/[dropoffLocation]
/// labels. [baseFare] is in the base currency unit (e.g. ZAR).
@immutable
class ActiveRideOffer {
  const ActiveRideOffer({
    required this.tripId,
    required this.baseFare,
    this.riderId,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
  });

  /// Deserialises an offer from either transport's payload — the WebSocket
  /// frame or the FCM data map, which is a strict subset of it. Throws
  /// [FormatException] when the two fields every payload does carry
  /// (`tripId`, `base_fare`) are missing or unparseable.
  factory ActiveRideOffer.fromJson(Map<String, dynamic> json) {
    final String? tripId = json['tripId'] as String?;
    if (tripId == null || tripId.isEmpty) {
      throw const FormatException(
        'rideOfferAvailable payload is missing tripId.',
      );
    }

    final (double? pickupLat, double? pickupLng) =
        _coordinatePair(json['pickup_location']);
    final (double? dropoffLat, double? dropoffLng) =
        _coordinatePair(json['dropoff_location']);

    return ActiveRideOffer(
      tripId: tripId,
      baseFare: _parseFare(json['base_fare']),
      riderId: json['rider_id'] as String?,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
    );
  }

  /// The unique server-assigned trip identifier (e.g. `"TRIP#abc-123"`).
  final String tripId;

  /// The flat base fare offered by the marketplace in the base currency.
  final double baseFare;

  /// The rider who requested this trip, or null on the FCM fallback path.
  /// Required by the backend's `sendBid` route to notify the rider of an
  /// incoming bid — see `kwella-backend/src/lambdas/bidding_engine/handler.py`.
  final String? riderId;

  /// Pickup coordinates, or null on the FCM fallback path. Drive the pickup
  /// marker and route on the driver's map screens.
  final double? pickupLat;
  final double? pickupLng;

  /// Dropoff counterpart of [pickupLat]/[pickupLng].
  final double? dropoffLat;
  final double? dropoffLng;

  /// Display label for the pickup point. No payload in the stack carries an
  /// address string, so this is always derived from the coordinates (or a
  /// placeholder when even those are absent).
  String get pickupLocation => _label('Pickup', pickupLat, pickupLng);

  /// Dropoff counterpart of [pickupLocation].
  String get dropoffLocation => _label('Dropoff', dropoffLat, dropoffLng);

  /// Reads a `[lat, lon]` pair, or `(null, null)` for any other shape.
  /// A half-present pair is useless to every consumer, so it is discarded
  /// whole rather than per-axis.
  static (double?, double?) _coordinatePair(Object? value) {
    if (value is! List || value.length < 2) return (null, null);
    final Object? lat = value[0];
    final Object? lng = value[1];
    if (lat is! num || lng is! num) return (null, null);
    return (lat.toDouble(), lng.toDouble());
  }

  /// Both backends serialise `base_fare` as a string; accepts a raw number
  /// too rather than caring which.
  static double _parseFare(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final double? parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw FormatException(
      'rideOfferAvailable payload has no usable base_fare: $value',
    );
  }

  static String _label(String prefix, double? lat, double? lng) {
    if (lat == null || lng == null) return '$prefix location unavailable';
    return '$prefix @ ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveRideOffer &&
          runtimeType == other.runtimeType &&
          tripId == other.tripId &&
          baseFare == other.baseFare &&
          riderId == other.riderId &&
          pickupLat == other.pickupLat &&
          pickupLng == other.pickupLng &&
          dropoffLat == other.dropoffLat &&
          dropoffLng == other.dropoffLng;

  @override
  int get hashCode => Object.hash(
    tripId,
    baseFare,
    riderId,
    pickupLat,
    pickupLng,
    dropoffLat,
    dropoffLng,
  );

  @override
  String toString() =>
      'ActiveRideOffer('
      'tripId: $tripId, '
      'baseFare: $baseFare, '
      'riderId: $riderId, '
      'pickupLat: $pickupLat, '
      'pickupLng: $pickupLng, '
      'dropoffLat: $dropoffLat, '
      'dropoffLng: $dropoffLng)';
}
