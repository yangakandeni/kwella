import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:kwella_rider_app/src/features/bidding/bidding_provider.dart';

void main() {
  group('RiderBiddingNotifier Unit Tests', () {
    late ProviderContainer container;
    late StreamController<KwellaBiddingEvent> mockStreamController;

    setUp(() {
      mockStreamController = StreamController<KwellaBiddingEvent>.broadcast();
      container = ProviderContainer(
        overrides: [
          kwellaEventMultiplexerProvider.overrideWith((ref) {
            return mockStreamController.stream;
          }),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      mockStreamController.close();
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

    test('stream broadcast populates bids on BidReceivedEvent', () async {
      final notifier = container.read(riderBiddingProvider.notifier);
      
      notifier.startBroadcast();
      
      expect(container.read(riderBiddingProvider).status, equals(BiddingStatus.searching));

      final bid1 = const DriverBid(
        id: 'driver_1',
        driverName: 'Sipho Dlamini',
        rating: '4.9',
        eta: '3 min away',
        price: 'R 75.00',
      );

      mockStreamController.add(BidReceivedEvent(bid1));
      
      // Wait for stream to process
      await Future<void>.delayed(Duration.zero);
      
      var state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.activeBids));
      expect(state.bids.length, equals(1));
      expect(state.bids.first.driverName, equals('Sipho Dlamini'));

      final bid2 = const DriverBid(
        id: 'driver_2',
        driverName: 'Lwazi Ndlovu',
        rating: '4.8',
        eta: '5 min away',
        price: 'R 82.00',
      );

      mockStreamController.add(BidReceivedEvent(bid2));
      await Future<void>.delayed(Duration.zero);
      
      state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.activeBids));
      expect(state.bids.length, equals(2));
      expect(state.bids[1].driverName, equals('Lwazi Ndlovu'));
    });

    test('stream broadcast transitions to accepted on RideAcceptedEvent', () async {
      final notifier = container.read(riderBiddingProvider.notifier);
      notifier.startBroadcast();
      
      final bid1 = const DriverBid(
        id: 'driver_1',
        driverName: 'Sipho Dlamini',
        rating: '4.9',
        eta: '3 min away',
        price: 'R 75.00',
      );

      mockStreamController.add(BidReceivedEvent(bid1));
      await Future<void>.delayed(Duration.zero);

      mockStreamController.add(const RideAcceptedEvent(
        rideId: 'ride_1',
        driverId: 'driver_1',
        finalPrice: 'R 75.00',
      ));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.accepted));
      expect(state.acceptedBid, equals(bid1));
    });

    test('stream broadcast transitions to cancelled on RideCancelledEvent', () async {
      final notifier = container.read(riderBiddingProvider.notifier);
      notifier.startBroadcast();

      mockStreamController.add(const RideCancelledEvent(
        rideId: 'ride_1',
        reason: 'No drivers available',
      ));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.cancelled));
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
      
      final bid1 = const DriverBid(
        id: 'driver_1',
        driverName: 'Sipho Dlamini',
        rating: '4.9',
        eta: '3 min away',
        price: 'R 75.00',
      );

      mockStreamController.add(BidReceivedEvent(bid1));
      await Future<void>.delayed(Duration.zero);
      
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
      
      final bid1 = const DriverBid(
        id: 'driver_1',
        driverName: 'Sipho Dlamini',
        rating: '4.9',
        eta: '3 min away',
        price: 'R 75.00',
      );

      mockStreamController.add(BidReceivedEvent(bid1));
      await Future<void>.delayed(Duration.zero);
      
      expect(container.read(riderBiddingProvider).bids.length, equals(1));

      notifier.reset();

      final state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.idle));
      expect(state.bids, isEmpty);
      expect(state.acceptedBid, isNull);
    });
  });
}

