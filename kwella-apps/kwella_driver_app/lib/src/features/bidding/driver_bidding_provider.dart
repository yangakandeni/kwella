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
  inTransit,
  completed,
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

  ProviderSubscription<AsyncValue<KwellaBiddingEvent>>? _eventSubscription;

  DriverBiddingNotifier(this.ref) : super(const DriverBiddingState()) {
    _initStream();
  }

  void _initStream() {
    _eventSubscription = ref.listen<AsyncValue<KwellaBiddingEvent>>(
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
        'payload': {'price': counterPrice},
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
        'payload': {'rideId': rideId},
      });
      gateway.send(payload);
    }
    state = state.copyWith(
      status: DriverJobStatus.waitingForPassenger,
      rideId: rideId,
    );
  }

  /// Notifies the rider that the trip has begun, dispatching a `tripStarted`
  /// event over the WebSocket gateway and transitioning local state into
  /// `.inTransit`.
  void startTrip(String rideId) {
    final gateway = ref.read(kwellaWebSocketGatewayProvider);
    if (gateway.isConnected) {
      final payload = jsonEncode({
        'action': 'tripStarted',
        'payload': {'rideId': rideId},
      });
      gateway.send(payload);
    }
    state = state.copyWith(status: DriverJobStatus.inTransit, rideId: rideId);
  }

  /// Notifies the rider that the trip has ended, dispatching a
  /// `tripCompleted` event over the WebSocket gateway, then tearing down
  /// this provider's local state and closing its gateway subscription.
  void endTrip(String rideId) {
    final gateway = ref.read(kwellaWebSocketGatewayProvider);
    if (gateway.isConnected) {
      final payload = jsonEncode({
        'action': 'tripCompleted',
        'payload': {'rideId': rideId},
      });
      gateway.send(payload);
    }
    state = state.copyWith(status: DriverJobStatus.completed, rideId: rideId);
    _teardown();
  }

  /// Resets local state to idle and gracefully closes the subscription to
  /// the shared event stream, ready for the driver's next job.
  void _teardown() {
    _eventSubscription?.close();
    _eventSubscription = null;
    state = const DriverBiddingState();
  }

  @override
  void dispose() {
    _eventSubscription?.close();
    super.dispose();
  }
}

final driverBiddingProvider =
    StateNotifierProvider<DriverBiddingNotifier, DriverBiddingState>((ref) {
      return DriverBiddingNotifier(ref);
    });
