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

  const ActiveRideOffer({
    required this.tripId,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.baseFare,
    required this.expiresAt,
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
    );
  }

  /// Serialises this offer back to a plain JSON-encodable [Map].
  Map<String, dynamic> toJson() => {
        'tripId': tripId,
        'pickupLocation': pickupLocation,
        'dropoffLocation': dropoffLocation,
        'baseFare': baseFare,
        'expiresAt': expiresAt.toIso8601String(),
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
          expiresAt == other.expiresAt;

  @override
  int get hashCode => Object.hash(
        tripId,
        pickupLocation,
        dropoffLocation,
        baseFare,
        expiresAt,
      );

  @override
  String toString() => 'ActiveRideOffer('
      'tripId: $tripId, '
      'pickupLocation: $pickupLocation, '
      'dropoffLocation: $dropoffLocation, '
      'baseFare: $baseFare, '
      'expiresAt: $expiresAt)';
}
