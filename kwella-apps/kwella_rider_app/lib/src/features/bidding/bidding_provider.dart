import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

/// Enum representing the phases of a rider's bidding lifecycle.
enum BiddingStatus {
  idle,
  searching,
  activeBids,
  tripConfirmed,
  driverArrived,
  inTransit,
  tripCompleted,
  cancelled,
}

/// Extracts the numeric amount from a [DriverBid.price] string such as
/// `'R 75.00'` so bids can be ranked cheapest-first. Unparseable prices sort
/// to the end rather than crashing the aggregator.
double _parseBidPrice(String price) {
  final match = RegExp(r'[\d.]+').firstMatch(price);
  if (match == null) return double.infinity;
  return double.tryParse(match.group(0)!) ?? double.infinity;
}

/// Immutable state containing the status, incoming offers, and the accepted offer if any.
class RiderBiddingState {
  final BiddingStatus status;
  final List<DriverBid> bids;
  final DriverBid? acceptedBid;
  final String? tripId;

  const RiderBiddingState({
    required this.status,
    required this.bids,
    this.acceptedBid,
    this.tripId,
  });

  RiderBiddingState copyWith({
    BiddingStatus? status,
    List<DriverBid>? bids,
    DriverBid? acceptedBid,
    String? tripId,
  }) {
    return RiderBiddingState(
      status: status ?? this.status,
      bids: bids ?? this.bids,
      acceptedBid: acceptedBid ?? this.acceptedBid,
      tripId: tripId ?? this.tripId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiderBiddingState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          bids == other.bids &&
          acceptedBid == other.acceptedBid &&
          tripId == other.tripId;

  @override
  int get hashCode =>
      status.hashCode ^ bids.hashCode ^ acceptedBid.hashCode ^ tripId.hashCode;

  @override
  String toString() {
    return 'RiderBiddingState(status: $status, bidsCount: ${bids.length}, acceptedBid: ${acceptedBid?.driverName}, tripId: $tripId)';
  }
}

class RiderBiddingNotifier extends StateNotifier<RiderBiddingState> {
  RiderBiddingNotifier(this._ref)
    : super(const RiderBiddingState(status: BiddingStatus.idle, bids: []));

  final Ref _ref;
  ProviderSubscription<AsyncValue<KwellaBiddingEvent>>? _subscription;
  StreamSubscription<String>? _rawFrameSubscription;

  /// Starts broadcasting a booking request, transitioning status to `.searching`,
  /// subscribing to incoming bids, and — when pickup/dropoff coordinates are
  /// supplied — dispatching a `requestTrip` frame to the backend so it can
  /// match nearby drivers.
  void startBroadcast({
    double? pickupLatitude,
    double? pickupLongitude,
    double? dropoffLatitude,
    double? dropoffLongitude,
  }) {
    _cancelSubscription();

    state = const RiderBiddingState(status: BiddingStatus.searching, bids: []);

    _subscription = _ref.listen<AsyncValue<KwellaBiddingEvent>>(
      kwellaEventMultiplexerProvider,
      (previous, next) {
        if (next is AsyncData<KwellaBiddingEvent>) {
          _handleEvent(next.value);
        }
      },
    );

    final gateway = _ref.read(kwellaWebSocketGatewayProvider);
    if (!gateway.isConnected ||
        pickupLatitude == null ||
        pickupLongitude == null ||
        dropoffLatitude == null ||
        dropoffLongitude == null) {
      return;
    }

    final riderId = _ref.read(kwellaAuthNotifierProvider).userId;

    _rawFrameSubscription = gateway.dataStream.listen(_handleRawFrame);

    gateway.send(
      jsonEncode({
        'action': 'requestTrip',
        'riderId': riderId,
        'pickup_latitude': pickupLatitude,
        'pickup_longitude': pickupLongitude,
        'dropoff_latitude': dropoffLatitude,
        'dropoff_longitude': dropoffLongitude,
      }),
    );
  }

  /// Handles raw WebSocket frames looking for the synchronous `requestTrip`
  /// response (`{"status": "TripBroadcast", "tripId": ...}`), which arrives
  /// outside the `action`-keyed [KwellaBiddingEvent] pipeline.
  void _handleRawFrame(String rawFrame) {
    if (!mounted) return;

    try {
      final decoded = jsonDecode(rawFrame);
      if (decoded is Map<String, dynamic> &&
          decoded['status'] == 'TripBroadcast') {
        final tripId = decoded['tripId'];
        if (tripId is String) {
          state = state.copyWith(tripId: tripId);
        }
      }
    } catch (_) {
      // Malformed/unrelated frame — ignored, matches the multiplexer's
      // own tolerance for non-JSON or unrecognised payloads.
    }
  }

  void _handleEvent(KwellaBiddingEvent event) {
    if (!mounted) return;

    if (event is BidReceivedEvent) {
      final updatedBids = List<DriverBid>.from(state.bids)..add(event.bid);
      updatedBids.sort(
        (a, b) => _parseBidPrice(a.price).compareTo(_parseBidPrice(b.price)),
      );
      state = state.copyWith(
        status: BiddingStatus.activeBids,
        bids: updatedBids,
      );
    } else if (event is RideAcceptedEvent) {
      // Find the accepted bid
      final bid = state.bids.firstWhere(
        (b) => b.id == event.driverId,
        orElse: () => DriverBid(
          id: event.driverId,
          driverName: 'Driver',
          rating: 'N/A',
          eta: 'N/A',
          price: event.finalPrice,
        ),
      );

      state = state.copyWith(
        status: BiddingStatus.tripConfirmed,
        acceptedBid: bid,
      );
    } else if (event is DriverArrivedEvent) {
      state = state.copyWith(status: BiddingStatus.driverArrived);
    } else if (event is TripStartedEvent) {
      state = state.copyWith(status: BiddingStatus.inTransit);
    } else if (event is TripCompletedEvent) {
      state = state.copyWith(status: BiddingStatus.tripCompleted);
      // Deferred so the UI has a chance to observe `.tripCompleted` before
      // the session is torn down back to `.idle`.
      Future.microtask(reset);
    } else if (event is RideCancelledEvent) {
      state = state.copyWith(status: BiddingStatus.cancelled);
      _cancelSubscription();
    }
  }

  /// Dispatches an `acceptBid` payload for [bidId] over the WebSocket
  /// gateway and transitions the local state into `.tripConfirmed`,
  /// preserving the accepted bid's details for the confirmation UI.
  void acceptBid(String bidId) {
    final bid = state.bids.firstWhere(
      (b) => b.id == bidId,
      orElse: () => DriverBid(
        id: bidId,
        driverName: 'Driver',
        rating: 'N/A',
        eta: 'N/A',
        price: 'N/A',
      ),
    );

    final gateway = _ref.read(kwellaWebSocketGatewayProvider);
    if (gateway.isConnected) {
      gateway.send(
        jsonEncode({
          'action': 'acceptBid',
          'payload': {'bidId': bidId},
        }),
      );
    }

    // Keep the subscription open past acceptance – the driver's later
    // `driverArrived` event still needs to reach this notifier.
    state = state.copyWith(
      status: BiddingStatus.tripConfirmed,
      acceptedBid: bid,
    );
  }

  /// Transitions status to `.cancelled` and clears active timers and bids.
  void cancelBroadcast() {
    _cancelSubscription();
    state = const RiderBiddingState(status: BiddingStatus.cancelled, bids: []);
  }

  /// Resets the bidding notifier to initial idle state, cleanly tearing
  /// down the active tracking session and closing the socket channel.
  void reset() {
    _cancelSubscription();
    state = const RiderBiddingState(status: BiddingStatus.idle, bids: []);

    final gateway = _ref.read(kwellaWebSocketGatewayProvider);
    if (gateway.isConnected) {
      gateway.disconnect();
    }
  }

  void _cancelSubscription() {
    _subscription?.close();
    _subscription = null;
    _rawFrameSubscription?.cancel();
    _rawFrameSubscription = null;
  }

  @override
  void dispose() {
    _cancelSubscription();
    super.dispose();
  }
}

/// Global provider for the Rider Bidding state machine.
final riderBiddingProvider =
    StateNotifierProvider<RiderBiddingNotifier, RiderBiddingState>((ref) {
      return RiderBiddingNotifier(ref);
    });
