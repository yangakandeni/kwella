import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

/// Enum representing the phases of a rider's bidding lifecycle.
enum BiddingStatus {
  idle,
  searching,
  activeBids,
  accepted,
  cancelled,
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

/// Notifier simulating a real-time stream of incoming driver bids.
class RiderBiddingNotifier extends StateNotifier<RiderBiddingState> {
  RiderBiddingNotifier()
      : super(const RiderBiddingState(status: BiddingStatus.idle, bids: []));

  final List<Timer> _simulationTimers = [];

  static const List<DriverBid> _mockBids = [
    DriverBid(
      id: 'bid_1',
      driverName: 'Sipho Dlamini',
      rating: '4.9',
      eta: '3 min away',
      price: 'R 75.00',
    ),
    DriverBid(
      id: 'bid_2',
      driverName: 'Lwazi Ndlovu',
      rating: '4.8',
      eta: '5 min away',
      price: 'R 82.00',
    ),
    DriverBid(
      id: 'bid_3',
      driverName: 'Thabo Mbeki',
      rating: '4.7',
      eta: '2 min away',
      price: 'R 69.00',
    ),
  ];

  /// Starts broadcasting a booking request, transitioning status to `.searching`
  /// and delivering bids asynchronously one by one.
  void startBroadcast() {
    _cancelSimulation();
    
    state = const RiderBiddingState(
      status: BiddingStatus.searching,
      bids: [],
    );

    // Simulate Sipho Dlamini bidding after 1 second
    _simulationTimers.add(
      Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        state = RiderBiddingState(
          status: BiddingStatus.activeBids,
          bids: [_mockBids[0]],
        );
      }),
    );

    // Simulate Lwazi Ndlovu bidding after 2.5 seconds
    _simulationTimers.add(
      Timer(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        state = RiderBiddingState(
          status: BiddingStatus.activeBids,
          bids: [_mockBids[0], _mockBids[1]],
        );
      }),
    );

    // Simulate Thabo Mbeki bidding after 4 seconds
    _simulationTimers.add(
      Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        state = RiderBiddingState(
          status: BiddingStatus.activeBids,
          bids: [_mockBids[0], _mockBids[1], _mockBids[2]],
        );
      }),
    );
  }

  /// Transitions status to `.accepted` and preserves the selected bid.
  void acceptBid(DriverBid bid) {
    _cancelSimulation();
    state = RiderBiddingState(
      status: BiddingStatus.accepted,
      bids: state.bids,
      acceptedBid: bid,
    );
  }

  /// Transitions status to `.cancelled` and clears active timers and bids.
  void cancelBroadcast() {
    _cancelSimulation();
    state = const RiderBiddingState(
      status: BiddingStatus.cancelled,
      bids: [],
    );
  }

  /// Resets the bidding notifier to initial idle state.
  void reset() {
    _cancelSimulation();
    state = const RiderBiddingState(
      status: BiddingStatus.idle,
      bids: [],
    );
  }

  void _cancelSimulation() {
    for (final timer in _simulationTimers) {
      timer.cancel();
    }
    _simulationTimers.clear();
  }

  @override
  void dispose() {
    _cancelSimulation();
    super.dispose();
  }
}

/// Global provider for the Rider Bidding state machine.
final riderBiddingProvider =
    StateNotifierProvider<RiderBiddingNotifier, RiderBiddingState>((ref) {
  return RiderBiddingNotifier();
});
