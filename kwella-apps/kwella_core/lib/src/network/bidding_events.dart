import '../models/driver_bid.dart';

abstract class KwellaBiddingEvent {
  const KwellaBiddingEvent();

  factory KwellaBiddingEvent.fromJson(Map<String, dynamic> json) {
    final action = json['action'] as String?;
    final payload =
        (json['payload'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};

    switch (action) {
      // ── Client-facing action names (e.g., from unit tests / mocks) ─────────
      case 'RideRequestReceived':
        return RideRequestReceivedEvent(
          riderName: payload['riderName'] as String,
          destination: payload['destination'] as String,
          estimatedPayout: (payload['estimatedPayout'] as num).toDouble(),
        );
      case 'BidReceived':
        return BidReceivedEvent(DriverBid.fromJson(payload));
      case 'RideAccepted':
        return RideAcceptedEvent(
          rideId: payload['rideId'] as String,
          driverId: payload['driverId'] as String,
          finalPrice: payload['finalPrice'] as String,
        );
      case 'RideCancelled':
        return RideCancelledEvent(
          rideId: payload['rideId'] as String,
          reason: payload['reason'] as String?,
        );
      case 'driverArrived':
        return DriverArrivedEvent(rideId: payload['rideId'] as String);
      case 'tripStarted':
        return TripStartedEvent(rideId: payload['rideId'] as String);
      case 'tripCompleted':
        return TripCompletedEvent(rideId: payload['rideId'] as String);

      // ── Backend (AWS Lambda) native action labels ──────────────────────────
      //
      // The bidding_engine Lambda emits these action strings over the live
      // API Gateway WebSocket.  We alias them here so the multiplexer can
      // decode real production frames without requiring a schema migration.

      /// `requestTrip` response: the backend broadcasts `rideOfferAvailable`
      /// to nearby drivers.  We surface it as [RideRequestReceivedEvent] so
      /// the Driver's [DriverBiddingNotifier] can transition to `.offerReceived`.
      case 'rideOfferAvailable':
        return RideRequestReceivedEvent(
          riderName: (payload['rider_id'] as String?) ?? 'Rider',
          destination: _coordinatesToString(payload['dropoff_location']),
          estimatedPayout: _parseFare(payload['base_fare']),
          pickupLatitude: _coordinateAt(payload['pickup_location'], 0),
          pickupLongitude: _coordinateAt(payload['pickup_location'], 1),
        );

      /// `sendBid` response: the backend pushes `driverBidReceived` to the
      /// rider's WebSocket.  We surface it as [BidReceivedEvent] so the
      /// Rider's [RiderBiddingNotifier] can append the incoming bid.
      case 'driverBidReceived':
        final driverId = (payload['driverId'] as String?) ?? 'driver-unknown';
        final amount = payload['amount'];
        return BidReceivedEvent(
          DriverBid(
            id: driverId,
            driverName:
                'Driver ${driverId.substring(driverId.length > 6 ? driverId.length - 6 : 0)}',
            rating: 'N/A',
            eta: 'N/A',
            price: 'R ${amount ?? '0.00'}',
          ),
        );

      /// The Driver app's `TelematicsBufferManager` flushes a batch of GPS
      /// samples every 3 seconds under this action. We surface it as a
      /// [DriverLocationUpdateEvent] so the Rider's live tracking notifier
      /// can project the driver's position onto the map.
      case 'TelemetryBatch':
        final pointsRaw = (payload['points'] as List?) ?? const [];
        final points = pointsRaw
            .whereType<Map>()
            .map((p) => TelemetryPoint.fromJson(p.cast<String, dynamic>()))
            .toList();
        return DriverLocationUpdateEvent(points);

      default:
        throw FormatException('Unknown KwellaBiddingEvent action: $action');
    }
  }
}

// ── Private parsing helpers ────────────────────────────────────────────────

/// Converts a coordinate list `[lat, lng]` from the backend offer payload
/// into a human-readable string.  Falls back gracefully when the value is
/// absent or malformed.
String _coordinatesToString(dynamic coords) {
  if (coords is List && coords.length >= 2) {
    final lat = coords[0];
    final lng = coords[1];
    return '${lat.toString()}, ${lng.toString()}';
  }
  return coords?.toString() ?? 'Unknown destination';
}

/// Reads the numeric value at [index] from a `[lat, lng]` coordinate pair,
/// returning `null` when the field is absent or malformed.
double? _coordinateAt(dynamic coords, int index) {
  if (coords is List && coords.length > index) {
    final value = coords[index];
    if (value is num) return value.toDouble();
  }
  return null;
}

/// Parses the `base_fare` field from the backend payload, which may arrive
/// as a `num`, `String`, or `null`.  Returns `0.0` for unparseable values.
double _parseFare(dynamic fare) {
  if (fare == null) return 0.0;
  if (fare is num) return fare.toDouble();
  return double.tryParse(fare.toString()) ?? 0.0;
}

class RideRequestReceivedEvent extends KwellaBiddingEvent {
  final String riderName;
  final String destination;
  final double estimatedPayout;

  /// Decimal-degree WGS-84 pickup coordinates, when the backend included a
  /// `pickup_location` field on the offer. `null` when absent/malformed.
  final double? pickupLatitude;
  final double? pickupLongitude;

  const RideRequestReceivedEvent({
    required this.riderName,
    required this.destination,
    required this.estimatedPayout,
    this.pickupLatitude,
    this.pickupLongitude,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideRequestReceivedEvent &&
          runtimeType == other.runtimeType &&
          riderName == other.riderName &&
          destination == other.destination &&
          estimatedPayout == other.estimatedPayout &&
          pickupLatitude == other.pickupLatitude &&
          pickupLongitude == other.pickupLongitude;

  @override
  int get hashCode =>
      riderName.hashCode ^
      destination.hashCode ^
      estimatedPayout.hashCode ^
      pickupLatitude.hashCode ^
      pickupLongitude.hashCode;
}

class BidReceivedEvent extends KwellaBiddingEvent {
  final DriverBid bid;
  const BidReceivedEvent(this.bid);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BidReceivedEvent &&
          runtimeType == other.runtimeType &&
          bid == other.bid;

  @override
  int get hashCode => bid.hashCode;
}

class RideAcceptedEvent extends KwellaBiddingEvent {
  final String rideId;
  final String driverId;
  final String finalPrice;

  const RideAcceptedEvent({
    required this.rideId,
    required this.driverId,
    required this.finalPrice,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideAcceptedEvent &&
          runtimeType == other.runtimeType &&
          rideId == other.rideId &&
          driverId == other.driverId &&
          finalPrice == other.finalPrice;

  @override
  int get hashCode => rideId.hashCode ^ driverId.hashCode ^ finalPrice.hashCode;
}

class RideCancelledEvent extends KwellaBiddingEvent {
  final String rideId;
  final String? reason;

  const RideCancelledEvent({required this.rideId, this.reason});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideCancelledEvent &&
          runtimeType == other.runtimeType &&
          rideId == other.rideId &&
          reason == other.reason;

  @override
  int get hashCode => rideId.hashCode ^ (reason?.hashCode ?? 0);
}

/// Sent by the Driver app when the driver's [SlideToConfirmButton] confirms
/// they've reached the pickup point. The gateway relays this to the rider so
/// their UI can transition into `.driverArrived`.
class DriverArrivedEvent extends KwellaBiddingEvent {
  final String rideId;

  const DriverArrivedEvent({required this.rideId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DriverArrivedEvent &&
          runtimeType == other.runtimeType &&
          rideId == other.rideId;

  @override
  int get hashCode => rideId.hashCode;
}

/// Sent by the Driver app when the driver begins the trip after the
/// passenger has boarded. Relayed to the rider so their UI can transition
/// into `.inTransit`.
class TripStartedEvent extends KwellaBiddingEvent {
  final String rideId;

  const TripStartedEvent({required this.rideId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripStartedEvent &&
          runtimeType == other.runtimeType &&
          rideId == other.rideId;

  @override
  int get hashCode => rideId.hashCode;
}

/// Sent by the Driver app when the driver ends the trip at the destination.
/// Relayed to the rider so their UI can transition into `.tripCompleted` and
/// tear down the active tracking session.
class TripCompletedEvent extends KwellaBiddingEvent {
  final String rideId;

  const TripCompletedEvent({required this.rideId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripCompletedEvent &&
          runtimeType == other.runtimeType &&
          rideId == other.rideId;

  @override
  int get hashCode => rideId.hashCode;
}

/// A single GPS sample as broadcast by the Driver app's telematics buffer.
///
/// Mirrors the wire shape `{lat, lng, spd, ts}` sent by
/// `TelematicsBufferManager`. The buffer batches several of these together
/// and flushes them under the `TelemetryBatch` action every 3 seconds.
class TelemetryPoint {
  final double latitude;
  final double longitude;
  final double speed;
  final DateTime timestamp;

  const TelemetryPoint({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.timestamp,
  });

  factory TelemetryPoint.fromJson(Map<String, dynamic> json) {
    return TelemetryPoint(
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      speed: (json['spd'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['ts'] as num).toInt(),
        isUtc: true,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TelemetryPoint &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          speed == other.speed &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      latitude.hashCode ^
      longitude.hashCode ^
      speed.hashCode ^
      timestamp.hashCode;
}

/// A batch of [TelemetryPoint]s relayed from a driver's device, decoded from
/// a `TelemetryBatch` frame.
class DriverLocationUpdateEvent extends KwellaBiddingEvent {
  final List<TelemetryPoint> points;

  const DriverLocationUpdateEvent(this.points);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DriverLocationUpdateEvent &&
          runtimeType == other.runtimeType &&
          points == other.points;

  @override
  int get hashCode => points.hashCode;
}
