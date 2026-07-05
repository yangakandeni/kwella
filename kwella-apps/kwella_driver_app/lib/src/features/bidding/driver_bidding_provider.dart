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

  /// Backend trip identifier (`TRP#<uuid>`) for the active offer/job.
  final String? tripId;

  /// The authenticated local driver's own id, threaded into every outgoing
  /// action payload so the backend can resolve this connection.
  final String? driverId;

  /// The rider's id for the active trip. Not present on the initial
  /// `rideOfferAvailable` frame — populated once the backend supplies it
  /// (e.g. on bid selection).
  final String? riderId;

  const DriverBiddingState({
    this.status = DriverJobStatus.idle,
    this.riderName,
    this.destination,
    this.estimatedPayout,
    this.error,
    this.pickupLatitude,
    this.pickupLongitude,
    this.tripId,
    this.driverId,
    this.riderId,
  });

  DriverBiddingState copyWith({
    DriverJobStatus? status,
    String? riderName,
    String? destination,
    double? estimatedPayout,
    String? error,
    double? pickupLatitude,
    double? pickupLongitude,
    String? tripId,
    String? driverId,
    String? riderId,
  }) {
    return DriverBiddingState(
      status: status ?? this.status,
      riderName: riderName ?? this.riderName,
      destination: destination ?? this.destination,
      estimatedPayout: estimatedPayout ?? this.estimatedPayout,
      error: error ?? this.error,
      pickupLatitude: pickupLatitude ?? this.pickupLatitude,
      pickupLongitude: pickupLongitude ?? this.pickupLongitude,
      tripId: tripId ?? this.tripId,
      driverId: driverId ?? this.driverId,
      riderId: riderId ?? this.riderId,
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
              tripId: event.tripId,
              driverId: ref.read(kwellaAuthNotifierProvider).userId,
            );
          } else if (event is RideAcceptedEvent) {
            state = state.copyWith(
              status: DriverJobStatus.jobAccepted,
              tripId: event.rideId,
              driverId: event.driverId,
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
        'action': 'sendBid',
        'tripId': state.tripId,
        'driverId': state.driverId,
        'riderId': state.riderId,
        'amount': counterPrice,
      });
      gateway.send(payload);
    }
  }

  /// Notifies the rider that the driver has reached the pickup point,
  /// dispatching a `driverArrived` event over the WebSocket gateway and
  /// transitioning the local state into `.waitingForPassenger`.
  void driverArrived(String tripId) {
    final gateway = ref.read(kwellaWebSocketGatewayProvider);
    if (gateway.isConnected) {
      final payload = jsonEncode({
        'action': 'driverArrived',
        'tripId': tripId,
        'driverId': state.driverId,
      });
      gateway.send(payload);
    }
    state = state.copyWith(
      status: DriverJobStatus.waitingForPassenger,
      tripId: tripId,
    );
  }

  /// Notifies the rider that the trip has begun, dispatching a `startTrip`
  /// event over the WebSocket gateway and transitioning local state into
  /// `.inTransit`.
  void startTrip(String tripId) {
    final gateway = ref.read(kwellaWebSocketGatewayProvider);
    if (gateway.isConnected) {
      final payload = jsonEncode({
        'action': 'startTrip',
        'tripId': tripId,
        'driverId': state.driverId,
      });
      gateway.send(payload);
    }
    state = state.copyWith(status: DriverJobStatus.inTransit, tripId: tripId);
  }

  /// Notifies the backend that the trip has ended, dispatching a
  /// `confirmArrival` event over the WebSocket gateway to settle the
  /// driver's payout, then tearing down this provider's local state and
  /// closing its gateway subscription.
  void confirmArrival(String tripId, double finalBidAmount) {
    final gateway = ref.read(kwellaWebSocketGatewayProvider);
    if (gateway.isConnected) {
      final payload = jsonEncode({
        'action': 'confirmArrival',
        'tripId': tripId,
        'driverId': state.driverId,
        'final_bid_amount': finalBidAmount,
      });
      gateway.send(payload);
    }
    state = state.copyWith(status: DriverJobStatus.completed, tripId: tripId);
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
