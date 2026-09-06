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
      pickupLocation: json['pickupLocation'] as String,
      dropoffLocation: json['dropoffLocation'] as String,
      baseFare: (json['baseFare'] as num).toDouble(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      riderId: json['rider_id'] as String? ?? json['riderId'] as String?,
    );
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
    );
  }

  static String? _coordinateLabel(
    Map<String, dynamic> json, {
    required String prefix,
  }) {
    final latitude = _parseDouble(
      json['${prefix}Latitude'] ??
          json['${prefix}_latitude'] ??
          json['${prefix}Lat'] ??
          json['${prefix}_lat'],
    );
    final longitude = _parseDouble(
      json['${prefix}Longitude'] ??
          json['${prefix}_longitude'] ??
          json['${prefix}Lon'] ??
          json['${prefix}_lon'] ??
          json['${prefix}Lng'] ??
          json['${prefix}_lng'],
    );

    return '${prefix[0].toUpperCase()}${prefix.substring(1)} @ ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
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
          riderId == other.riderId;

  @override
  int get hashCode => Object.hash(
    tripId,
    pickupLocation,
    dropoffLocation,
    baseFare,
    expiresAt,
    riderId,
  );

  @override
  String toString() =>
      'ActiveRideOffer('
      'tripId: $tripId, '
      'pickupLocation: $pickupLocation, '
      'dropoffLocation: $dropoffLocation, '
      'baseFare: $baseFare, '
      'expiresAt: $expiresAt, '
      'riderId: $riderId)';
}
