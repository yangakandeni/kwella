import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_driver/features/bidding/models/bidding_state.dart';
import 'package:kwella_driver/features/bidding/providers/bidding_provider.dart';

import 'support/fake_kwella_websocket_service.dart';

void main() {
  late FakeKwellaWebSocketService fakeWsService;

  setUp(() {
    fakeWsService = FakeKwellaWebSocketService();
  });

  test('BiddingNotifier starts idle and stays disconnected until connectAndSubscribe is called', () {
    final notifier = BiddingNotifier(wsService: fakeWsService);

    expect(notifier.debugState, isA<BiddingStateInitial>());
    expect(fakeWsService.connectCalled, isFalse);
    expect(fakeWsService.hasListeners, isFalse);

    notifier.dispose();
  });

  test('BiddingNotifier transitions to connecting state and connects to service once connectAndSubscribe is called', () {
    final notifier = BiddingNotifier(wsService: fakeWsService);
    notifier.connectAndSubscribe();

    expect(notifier.debugState, isA<BiddingStateConnecting>());
    expect(fakeWsService.connectCalled, isTrue);
    expect(fakeWsService.hasListeners, isTrue);

    notifier.dispose();
  });

  test('BiddingNotifier processes matching driver bids in camelCase', () async {
    final notifier = BiddingNotifier(wsService: fakeWsService);
    notifier.connectAndSubscribe();

    final payload = {
      'driverId': 'drv_111',
      'riderId': 'rdr_222',
      'amount': '150.00',
      'estimatedPickup': '6 mins',
      'broadcastPk': 'bcast_333',
    };

    fakeWsService.emit(payload);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.debugState, isA<BiddingStateActive>());
    final activeState = notifier.debugState as BiddingStateActive;
    expect(activeState.activeBids.length, equals(1));
    expect(activeState.activeBids.first['driverId'], equals('drv_111'));
    expect(activeState.activeBids.first['riderId'], equals('rdr_222'));
    expect(activeState.activeBids.first['amount'], equals('150.00'));
    expect(activeState.activeBids.first['estimatedPickup'], equals('6 mins'));
    expect(activeState.activeBids.first['broadcastPk'], equals('bcast_333'));

    notifier.dispose();
  });

  test('BiddingNotifier processes matching driver bids in snake_case and normalizes keys', () async {
    final notifier = BiddingNotifier(wsService: fakeWsService);
    notifier.connectAndSubscribe();

    final payload = {
      'driver_id': 'drv_444',
      'rider_id': 'rdr_555',
      'counter_fare': '125.50',
      'estimated_pickup': '3 mins',
      'broadcast_pk': 'bcast_666',
    };

    fakeWsService.emit(payload);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.debugState, isA<BiddingStateActive>());
    final activeState = notifier.debugState as BiddingStateActive;
    expect(activeState.activeBids.length, equals(1));
    // Verify values are unpacked and stored under camelCase keys
    expect(activeState.activeBids.first['driverId'], equals('drv_444'));
    expect(activeState.activeBids.first['riderId'], equals('rdr_555'));
    expect(activeState.activeBids.first['amount'], equals('125.50'));
    expect(activeState.activeBids.first['estimatedPickup'], equals('3 mins'));
    expect(activeState.activeBids.first['broadcastPk'], equals('bcast_666'));

    notifier.dispose();
  });

  test('BiddingNotifier ignores messages that are not driver bids', () async {
    final notifier = BiddingNotifier(wsService: fakeWsService);
    notifier.connectAndSubscribe();

    final payload = {
      'action': 'someOtherAction',
      'message': 'Hello marketplace',
    };

    fakeWsService.emit(payload);
    await Future<void>.delayed(Duration.zero);

    // Should still be in connecting state as payload was ignored
    expect(notifier.debugState, isA<BiddingStateConnecting>());

    notifier.dispose();
  });

  test('BiddingNotifier transitions to error state on stream errors', () async {
    final notifier = BiddingNotifier(wsService: fakeWsService);
    notifier.connectAndSubscribe();

    fakeWsService.emitError('WebSocket failed unexpected connection drop');
    await Future<void>.delayed(Duration.zero);

    expect(notifier.debugState, isA<BiddingStateError>());
    final errorState = notifier.debugState as BiddingStateError;
    expect(errorState.message, contains('WebSocket failed'));

    notifier.dispose();
  });

  test('BiddingNotifier cancels stream subscription on dispose', () {
    final notifier = BiddingNotifier(wsService: fakeWsService);
    notifier.connectAndSubscribe();

    expect(fakeWsService.hasListeners, isTrue);
    notifier.dispose();
    expect(fakeWsService.hasListeners, isFalse);
  });
}
