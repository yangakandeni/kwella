import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

/// Enum representing the phases of a rider's bidding lifecycle.
enum BiddingStatus {
  idle,
  searching,
  activeBids,
  tripConfirmed,
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

  const RiderBiddingState({
    required this.status,
    required this.bids,
    this.acceptedBid,
  });

  RiderBiddingState copyWith({
    BiddingStatus? status,
    List<DriverBid>? bids,
    DriverBid? acceptedBid,
  }) {
    return RiderBiddingState(
      status: status ?? this.status,
      bids: bids ?? this.bids,
      acceptedBid: acceptedBid ?? this.acceptedBid,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiderBiddingState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          bids == other.bids &&
          acceptedBid == other.acceptedBid;

  @override
  int get hashCode => status.hashCode ^ bids.hashCode ^ acceptedBid.hashCode;

  @override
  String toString() {
    return 'RiderBiddingState(status: $status, bidsCount: ${bids.length}, acceptedBid: ${acceptedBid?.driverName})';
  }
}

class RiderBiddingNotifier extends StateNotifier<RiderBiddingState> {
  RiderBiddingNotifier(this._ref)
      : super(const RiderBiddingState(status: BiddingStatus.idle, bids: []));

  final Ref _ref;
  ProviderSubscription<AsyncValue<KwellaBiddingEvent>>? _subscription;

  /// Starts broadcasting a booking request, transitioning status to `.searching`
  /// and subscribing to incoming bids.
  void startBroadcast() {
    _cancelSubscription();
    
    state = const RiderBiddingState(
      status: BiddingStatus.searching,
      bids: [],
    );

    _subscription = _ref.listen<AsyncValue<KwellaBiddingEvent>>(
      kwellaEventMultiplexerProvider,
      (previous, next) {
        if (next is AsyncData<KwellaBiddingEvent>) {
          _handleEvent(next.value);
        }
      },
    );
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
    } else if (event is RideCancelledEvent) {
      state = state.copyWith(
        status: BiddingStatus.cancelled,
      );
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
      gateway.send(jsonEncode({
        'action': 'acceptBid',
        'payload': {'bidId': bidId},
      }));
    }

    _cancelSubscription();
    state = RiderBiddingState(
      status: BiddingStatus.tripConfirmed,
      bids: state.bids,
      acceptedBid: bid,
    );
  }

  /// Transitions status to `.cancelled` and clears active timers and bids.
  void cancelBroadcast() {
    _cancelSubscription();
    state = const RiderBiddingState(
      status: BiddingStatus.cancelled,
      bids: [],
    );
  }

  /// Resets the bidding notifier to initial idle state.
  void reset() {
    _cancelSubscription();
    state = const RiderBiddingState(
      status: BiddingStatus.idle,
      bids: [],
    );
  }

  void _cancelSubscription() {
    _subscription?.close();
    _subscription = null;
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
