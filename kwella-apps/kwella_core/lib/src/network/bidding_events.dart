import '../models/driver_bid.dart';

abstract class KwellaBiddingEvent {
  const KwellaBiddingEvent();

  factory KwellaBiddingEvent.fromJson(Map<String, dynamic> json) {
    final action = json['action'] as String?;
    final payload = (json['payload'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

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
          destination: _coordinatesToString(
            payload['dropoff_location'],
          ),
          estimatedPayout: _parseFare(payload['base_fare']),
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
            driverName: 'Driver ${driverId.substring(driverId.length > 6 ? driverId.length - 6 : 0)}',
            rating: 'N/A',
            eta: 'N/A',
            price: 'R ${amount ?? '0.00'}',
          ),
        );

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

  const RideRequestReceivedEvent({
    required this.riderName,
    required this.destination,
    required this.estimatedPayout,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideRequestReceivedEvent &&
          runtimeType == other.runtimeType &&
          riderName == other.riderName &&
          destination == other.destination &&
          estimatedPayout == other.estimatedPayout;

  @override
  int get hashCode =>
      riderName.hashCode ^ destination.hashCode ^ estimatedPayout.hashCode;
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

  const RideCancelledEvent({
    required this.rideId,
    this.reason,
  });

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
