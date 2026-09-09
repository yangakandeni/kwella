import 'package:flutter/foundation.dart';

/// Immutable value-object representing a ride offer broadcast from the
/// Kwella marketplace to an active driver via the `rideOfferAvailable`
/// WebSocket event.
///
/// All monetary values are stored as [double] in the base currency unit
/// (e.g. ZAR). [expiresAt] marks the absolute UTC deadline after which
/// the controller must dismiss the offer automatically.
@immutable
class ActiveRideOffer {
  /// The unique server-assigned trip identifier (e.g. `"TRIP#abc-123"`).
  final String tripId;

  /// Human-readable pickup address / coordinate label.
  final String pickupLocation;

  /// Human-readable dropoff address / coordinate label.
  final String dropoffLocation;

  /// Pickup coordinates, when the source payload carried them — the mock
  /// orchestrator's `rideOfferAvailable` frame sends `pickup_location` as a
  /// `[lat, lon]` pair rather than a string label (see
  /// `scripts/mock_orchestrator/contract.py`); the real backend's
  /// string-label payload leaves these null. Needed to draw the pickup
  /// marker/route on [TripNavigationScreen]'s map.
  final double? pickupLat;
  final double? pickupLng;

  /// Dropoff counterpart of [pickupLat]/[pickupLng].
  final double? dropoffLat;
  final double? dropoffLng;

  /// The flat base fare offered by the marketplace in the base currency.
  final double baseFare;

  /// The absolute UTC timestamp at which the offer expires.
  ///
  /// The controller starts a 15-second countdown from [DateTime.now()] and
  /// compares against this field to decide whether to auto-dismiss.
  final DateTime expiresAt;

  /// The unique server-assigned rider identifier who requested this trip, or
  /// [null] when the source payload did not include one. Required by the
  /// backend's `sendBid` route to notify the rider of an incoming bid — see
  /// `kwella-backend/src/lambdas/bidding_engine/handler.py`.
  final String? riderId;

  const ActiveRideOffer({
    required this.tripId,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.baseFare,
    required this.expiresAt,
    this.riderId,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
  });

  /// Deserialises an [ActiveRideOffer] from the `rideOfferAvailable` WebSocket
  /// payload map.
  ///
  /// Expected payload schema:
  /// ```json
  /// {
  ///   "action": "rideOfferAvailable",
  ///   "tripId": "TRIP#abc-123",
  ///   "pickupLocation": "Cape Town CBD",
  ///   "dropoffLocation": "V&A Waterfront",
  ///   "baseFare": 45.50,
  ///   "expiresAt": "2024-06-21T06:00:15.000Z"
  /// }
  /// ```
  factory ActiveRideOffer.fromJson(Map<String, dynamic> json) {
    return ActiveRideOffer(
      tripId: json['tripId'] as String,
      pickupLocation: json['pickupLocation'] as String? ??
          'Pickup location unavailable',
      dropoffLocation: json['dropoffLocation'] as String? ??
          'Dropoff location unavailable',
      baseFare: (json['baseFare'] as num).toDouble(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      riderId: json['rider_id'] as String? ?? json['riderId'] as String?,
      pickupLat: _arrayComponent(json['pickup_location'], 0),
      pickupLng: _arrayComponent(json['pickup_location'], 1),
      dropoffLat: _arrayComponent(json['dropoff_location'], 0),
      dropoffLng: _arrayComponent(json['dropoff_location'], 1),
    );
  }

  /// Reads a numeric `[lat, lon]`-shaped list at [index], as sent by the
  /// mock orchestrator's `pickup_location`/`dropoff_location` fields. `null`
  /// for any other shape (including the real backend's string-label
  /// payload, where these keys are absent entirely).
  static double? _arrayComponent(Object? value, int index) {
    if (value is List && value.length > index) {
      final Object? component = value[index];
      if (component is num) return component.toDouble();
    }
    return null;
  }

  /// Deserialises an [ActiveRideOffer] from a push notification payload.
  ///
  /// This supports data payloads with snake_case keys and coordinate-based
  /// fallback labels when address text is not available.
  factory ActiveRideOffer.fromPushNotification(Map<String, dynamic> json) {
    final tripId = json['tripId'] as String? ?? json['trip_id'] as String?;
    if (tripId == null || tripId.isEmpty) {
      throw FormatException('Missing tripId in push notification payload.');
    }

    final baseFareValue = json['baseFare'] ?? json['base_fare'];
    if (baseFareValue == null) {
      throw FormatException(
        'Missing baseFare/base_fare in push notification payload.',
      );
    }

    final baseFare = _parseDouble(baseFareValue);
    final pickupLocation =
        json['pickupLocation'] as String? ??
        json['pickup_location'] as String? ??
        _coordinateLabel(json, prefix: 'pickup') ??
        'Pickup location unavailable';
    final dropoffLocation =
        json['dropoffLocation'] as String? ??
        json['dropoff_location'] as String? ??
        _coordinateLabel(json, prefix: 'dropoff') ??
        'Dropoff location unavailable';

    final expiresAtValue = json['expiresAt'] ?? json['expires_at'];
    final expiresAt = expiresAtValue != null
        ? DateTime.parse(expiresAtValue as String).toUtc()
        : DateTime.now().toUtc().add(const Duration(seconds: 15));

    return ActiveRideOffer(
      tripId: tripId,
      pickupLocation: pickupLocation,
      dropoffLocation: dropoffLocation,
      baseFare: baseFare,
      expiresAt: expiresAt,
      pickupLat: _latitudeOf(json, 'pickup'),
      pickupLng: _longitudeOf(json, 'pickup'),
      dropoffLat: _latitudeOf(json, 'dropoff'),
      dropoffLng: _longitudeOf(json, 'dropoff'),
    );
  }

  /// Builds a coordinate display label (e.g. `"Pickup @ -33.90000, 18.40000"`)
  /// from whichever of [_latitudeOf]/[_longitudeOf]'s key variants are
  /// present, or `null` if either axis is missing/unparseable.
  static String? _coordinateLabel(
    Map<String, dynamic> json, {
    required String prefix,
  }) {
    final double? latitude = _latitudeOf(json, prefix);
    final double? longitude = _longitudeOf(json, prefix);
    if (latitude == null || longitude == null) return null;
    return '${prefix[0].toUpperCase()}${prefix.substring(1)} @ ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }

  static double? _latitudeOf(Map<String, dynamic> json, String prefix) =>
      _parseDoubleOrNull(
        json['${prefix}Latitude'] ??
            json['${prefix}_latitude'] ??
            json['${prefix}Lat'] ??
            json['${prefix}_lat'],
      );

  static double? _longitudeOf(Map<String, dynamic> json, String prefix) =>
      _parseDoubleOrNull(
        json['${prefix}Longitude'] ??
            json['${prefix}_longitude'] ??
            json['${prefix}Lon'] ??
            json['${prefix}_lon'] ??
            json['${prefix}Lng'] ??
            json['${prefix}_lng'],
      );

  static double? _parseDoubleOrNull(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String && value.isNotEmpty) return double.tryParse(value);
    return null;
  }

  static double _parseDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String && value.isNotEmpty) {
      return double.parse(value);
    }
    throw FormatException(
      'Expected numeric value for base fare or coordinate, got: $value',
    );
  }

  /// Serialises this offer back to a plain JSON-encodable [Map].
  Map<String, dynamic> toJson() => {
    'tripId': tripId,
    'pickupLocation': pickupLocation,
    'dropoffLocation': dropoffLocation,
    'baseFare': baseFare,
    'expiresAt': expiresAt.toIso8601String(),
    'riderId': riderId,
    'pickupLat': pickupLat,
    'pickupLng': pickupLng,
    'dropoffLat': dropoffLat,
    'dropoffLng': dropoffLng,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveRideOffer &&
          runtimeType == other.runtimeType &&
          tripId == other.tripId &&
          pickupLocation == other.pickupLocation &&
          dropoffLocation == other.dropoffLocation &&
          baseFare == other.baseFare &&
          expiresAt == other.expiresAt &&
          riderId == other.riderId &&
          pickupLat == other.pickupLat &&
          pickupLng == other.pickupLng &&
          dropoffLat == other.dropoffLat &&
          dropoffLng == other.dropoffLng;

  @override
  int get hashCode => Object.hash(
    tripId,
    pickupLocation,
    dropoffLocation,
    baseFare,
    expiresAt,
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
      'pickupLocation: $pickupLocation, '
      'dropoffLocation: $dropoffLocation, '
      'baseFare: $baseFare, '
      'expiresAt: $expiresAt, '
      'riderId: $riderId, '
      'pickupLat: $pickupLat, '
      'pickupLng: $pickupLng, '
      'dropoffLat: $dropoffLat, '
      'dropoffLng: $dropoffLng)';
}
