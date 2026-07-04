import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:kwella_rider_app/src/features/bidding/bidding_provider.dart';

void main() {
  group('RiderBiddingNotifier Unit Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is idle and has empty bids list', () {
      final state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.idle));
      expect(state.bids, isEmpty);
      expect(state.acceptedBid, isNull);
    });

    test('startBroadcast transitions state to searching immediately', () {
      final notifier = container.read(riderBiddingProvider.notifier);
      
      notifier.startBroadcast();
      
      final state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.searching));
      expect(state.bids, isEmpty);
      expect(state.acceptedBid, isNull);
    });

    test('simulated broadcast populates bids one by one over time', () async {
      final notifier = container.read(riderBiddingProvider.notifier);
      
      notifier.startBroadcast();
      
      // Initially searching, no bids
      expect(container.read(riderBiddingProvider).status, equals(BiddingStatus.searching));
      expect(container.read(riderBiddingProvider).bids, isEmpty);

      // Wait 1.1 seconds (should trigger first bid)
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      var state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.activeBids));
      expect(state.bids.length, equals(1));
      expect(state.bids.first.driverName, equals('Sipho Dlamini'));

      // Wait another 1.5 seconds (total 2.6 seconds, should trigger second bid)
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.activeBids));
      expect(state.bids.length, equals(2));
      expect(state.bids[1].driverName, equals('Lwazi Ndlovu'));

      // Wait another 1.5 seconds (total 4.1 seconds, should trigger third bid)
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.activeBids));
      expect(state.bids.length, equals(3));
      expect(state.bids[2].driverName, equals('Thabo Mbeki'));
    });

    test('acceptBid transitions status to accepted and preserves accepted bid', () {
      final notifier = container.read(riderBiddingProvider.notifier);
      final bid = const DriverBid(
        id: 'test_bid',
        driverName: 'Test Driver',
        rating: '5.0',
        eta: '1 min away',
        price: 'R 50.00',
      );

      notifier.acceptBid(bid);

      final state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.accepted));
      expect(state.acceptedBid, equals(bid));
    });

    test('cancelBroadcast transitions status to cancelled and clears bids', () async {
      final notifier = container.read(riderBiddingProvider.notifier);
      
      notifier.startBroadcast();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      
      expect(container.read(riderBiddingProvider).bids.length, equals(1));

      notifier.cancelBroadcast();

      final state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.cancelled));
      expect(state.bids, isEmpty);
      expect(state.acceptedBid, isNull);
    });

    test('reset transitions status to idle and clears bids', () async {
      final notifier = container.read(riderBiddingProvider.notifier);
      
      notifier.startBroadcast();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      
      expect(container.read(riderBiddingProvider).bids.length, equals(1));

      notifier.reset();

      final state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.idle));
      expect(state.bids, isEmpty);
      expect(state.acceptedBid, isNull);
    });
  });
}
