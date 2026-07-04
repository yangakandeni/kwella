import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

enum DriverJobStatus {
  idle,
  offerReceived,
  bidding,
  bidSubmitted,
  jobAccepted,
  waitingForPassenger,
  jobDeclined,
}

class DriverBiddingState {
  final DriverJobStatus status;
  final String? riderName;
  final String? destination;
  final double? estimatedPayout;
  final String? error;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final String? rideId;

  const DriverBiddingState({
    this.status = DriverJobStatus.idle,
    this.riderName,
    this.destination,
    this.estimatedPayout,
    this.error,
    this.pickupLatitude,
    this.pickupLongitude,
    this.rideId,
  });

  DriverBiddingState copyWith({
    DriverJobStatus? status,
    String? riderName,
    String? destination,
    double? estimatedPayout,
    String? error,
    double? pickupLatitude,
    double? pickupLongitude,
    String? rideId,
  }) {
    return DriverBiddingState(
      status: status ?? this.status,
      riderName: riderName ?? this.riderName,
      destination: destination ?? this.destination,
      estimatedPayout: estimatedPayout ?? this.estimatedPayout,
      error: error ?? this.error,
      pickupLatitude: pickupLatitude ?? this.pickupLatitude,
      pickupLongitude: pickupLongitude ?? this.pickupLongitude,
      rideId: rideId ?? this.rideId,
    );
  }
}

class DriverBiddingNotifier extends StateNotifier<DriverBiddingState> {
  final Ref ref;

  DriverBiddingNotifier(this.ref) : super(const DriverBiddingState()) {
    _initStream();
  }

  void _initStream() {
    ref.listen<AsyncValue<KwellaBiddingEvent>>(
      kwellaEventMultiplexerProvider,
      (previous, next) {
        next.whenData((event) {
          if (event is RideRequestReceivedEvent) {
            state = state.copyWith(
              status: DriverJobStatus.offerReceived,
              riderName: event.riderName,
              destination: event.destination,
              estimatedPayout: event.estimatedPayout,
              pickupLatitude: event.pickupLatitude,
              pickupLongitude: event.pickupLongitude,
            );
          } else if (event is RideAcceptedEvent) {
            state = state.copyWith(
              status: DriverJobStatus.jobAccepted,
              rideId: event.rideId,
            );
          } else if (event is RideCancelledEvent) {
            state = const DriverBiddingState();
          }
        });
      },
      fireImmediately: true,
    );
  }

  void submitBid(double counterPrice) {
    state = state.copyWith(status: DriverJobStatus.bidSubmitted);
    final gateway = ref.read(kwellaWebSocketGatewayProvider);
    if (gateway.isConnected) {
      final payload = jsonEncode({
        'action': 'SubmitBid',
        'payload': {
          'price': counterPrice,
        }
      });
      gateway.send(payload);
    }
  }

  /// Notifies the rider that the driver has reached the pickup point,
  /// dispatching a `driverArrived` event over the WebSocket gateway and
  /// transitioning the local state into `.waitingForPassenger`.
  void arriveAtPickup(String rideId) {
    final gateway = ref.read(kwellaWebSocketGatewayProvider);
    if (gateway.isConnected) {
      final payload = jsonEncode({
        'action': 'driverArrived',
        'payload': {
          'rideId': rideId,
        }
      });
      gateway.send(payload);
    }
    state = state.copyWith(
      status: DriverJobStatus.waitingForPassenger,
      rideId: rideId,
    );
  }
}

final driverBiddingProvider =
    StateNotifierProvider<DriverBiddingNotifier, DriverBiddingState>((ref) {
  return DriverBiddingNotifier(ref);
});
