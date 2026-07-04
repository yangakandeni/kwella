import '../models/driver_bid.dart';

abstract class KwellaBiddingEvent {
  const KwellaBiddingEvent();

  factory KwellaBiddingEvent.fromJson(Map<String, dynamic> json) {
    final action = json['action'] as String?;
    final payload = (json['payload'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    switch (action) {
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
      default:
        throw FormatException('Unknown KwellaBiddingEvent action: $action');
    }
  }
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
