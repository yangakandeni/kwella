import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:kwella_rider_app/src/features/bidding/bidding_provider.dart';

/// A [KwellaWebSocketGateway] stand-in that reports itself connected and
/// records outbound payloads without opening a real socket.
class _FakeConnectedGateway extends KwellaWebSocketGateway {
  _FakeConnectedGateway() : super(endpointUrl: 'wss://example.invalid/test');

  @override
  bool get isConnected => true;

  @override
  void send(String payload) {
    sentMessages.add(payload);
  }
}

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

    test('stream broadcast transitions to tripConfirmed on RideAcceptedEvent', () async {
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
      expect(state.status, equals(BiddingStatus.tripConfirmed));
      expect(state.acceptedBid, equals(bid1));
    });

    test('bids are kept sorted cheapest-first as they arrive', () async {
      final notifier = container.read(riderBiddingProvider.notifier);
      notifier.startBroadcast();

      const expensiveBid = DriverBid(
        id: 'driver_expensive',
        driverName: 'Lwazi Ndlovu',
        rating: '4.8',
        eta: '5 min away',
        price: 'R 150.00',
      );
      const cheapBid = DriverBid(
        id: 'driver_cheap',
        driverName: 'Sipho Dlamini',
        rating: '4.9',
        eta: '3 min away',
        price: 'R 75.00',
      );

      mockStreamController.add(const BidReceivedEvent(expensiveBid));
      await Future<void>.delayed(Duration.zero);
      mockStreamController.add(const BidReceivedEvent(cheapBid));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(riderBiddingProvider);
      expect(state.bids.map((b) => b.id).toList(),
          equals(['driver_cheap', 'driver_expensive']));
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

    test('acceptBid transitions status to tripConfirmed and preserves accepted bid',
        () async {
      final notifier = container.read(riderBiddingProvider.notifier);
      notifier.startBroadcast();

      const bid = DriverBid(
        id: 'test_bid',
        driverName: 'Test Driver',
        rating: '5.0',
        eta: '1 min away',
        price: 'R 50.00',
      );

      mockStreamController.add(const BidReceivedEvent(bid));
      await Future<void>.delayed(Duration.zero);

      notifier.acceptBid('test_bid');

      final state = container.read(riderBiddingProvider);
      expect(state.status, equals(BiddingStatus.tripConfirmed));
      expect(state.acceptedBid, equals(bid));
    });

    test('acceptBid dispatches an acceptBid JSON payload over the WebSocket gateway',
        () async {
      final gateway = _FakeConnectedGateway();
      final connectedContainer = ProviderContainer(
        overrides: [
          kwellaWebSocketGatewayProvider.overrideWithValue(gateway),
          kwellaEventMultiplexerProvider.overrideWith((ref) {
            return mockStreamController.stream;
          }),
        ],
      );
      addTearDown(connectedContainer.dispose);

      final notifier = connectedContainer.read(riderBiddingProvider.notifier);
      notifier.startBroadcast();

      const bid = DriverBid(
        id: 'driver_dispatch',
        driverName: 'Dispatch Driver',
        rating: '4.7',
        eta: '2 min away',
        price: 'R 60.00',
      );
      mockStreamController.add(const BidReceivedEvent(bid));
      await Future<void>.delayed(Duration.zero);

      notifier.acceptBid('driver_dispatch');

      expect(gateway.sentMessages, isNotEmpty);
      final decoded =
          jsonDecode(gateway.sentMessages.last) as Map<String, dynamic>;
      expect(decoded['action'], 'acceptBid');
      expect(
        (decoded['payload'] as Map<String, dynamic>)['bidId'],
        'driver_dispatch',
      );
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

