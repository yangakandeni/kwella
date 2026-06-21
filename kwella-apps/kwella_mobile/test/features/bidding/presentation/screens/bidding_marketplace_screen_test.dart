import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_mobile/features/bidding/models/bidding_state.dart';
import 'package:kwella_mobile/features/bidding/presentation/screens/bidding_marketplace_screen.dart';
import 'package:kwella_mobile/features/bidding/providers/bidding_provider.dart';
import 'package:kwella_mobile/features/bidding/services/kwella_websocket_service.dart';

class FakeKwellaWebSocketService implements KwellaWebSocketService {
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  bool connectCalled = false;
  bool disposeCalled = false;
  bool hasListeners = false;

  FakeKwellaWebSocketService() {
    _controller.onListen = () => hasListeners = true;
    _controller.onCancel = () => hasListeners = false;
  }

  @override
  void connect() {
    connectCalled = true;
  }

  @override
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  @override
  Stream<Map<String, dynamic>> get bidStream => _controller.stream;

  @override
  bool get isConnected => connectCalled && !disposeCalled;

  @override
  Future<void> sendDriverBid({
    required String driverId,
    required String riderId,
    required double amount,
    required String estimatedPickup,
    required String broadcastPk,
  }) async {
    // No-op
  }

  @override
  void dispose() {
    disposeCalled = true;
    _controller.close();
  }
}

class MockBiddingNotifier extends BiddingNotifier {
  MockBiddingNotifier(KwellaWebSocketService wsService, [BiddingState initialState = const BiddingState.initial()])
      : super(wsService: wsService) {
    state = initialState;
  }

  @override
  void _connectAndSubscribe() {
    // Prevent auto-connecting during tests to avoid async stream timing issues
  }
}

void main() {
  late FakeKwellaWebSocketService fakeWsService;

  setUp(() {
    fakeWsService = FakeKwellaWebSocketService();
  });

  testWidgets('displays loading layout when state is connecting or initial',
      (WidgetTester tester) async {
    final biddingNotifier = MockBiddingNotifier(fakeWsService, const BiddingState.connecting());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biddingProvider.overrideWith((ref) => biddingNotifier),
        ],
        child: const MaterialApp(
          home: BiddingMarketplaceScreen(),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text('Connecting to Kwella live bidding marketplace...'),
      findsOneWidget,
    );
  });

  testWidgets('displays active list of bids when state is active',
      (WidgetTester tester) async {
    final biddingNotifier = MockBiddingNotifier(
      fakeWsService,
      const BiddingState.active(activeBids: [
        {
          'driverId': 'drv_test_1',
          'riderId': 'rdr_123',
          'amount': '150.00',
          'estimatedPickup': '5 mins',
          'broadcastPk': 'bcast_1',
        },
        {
          'driverId': 'drv_test_2',
          'riderId': 'rdr_123',
          'amount': 120.50,
          'estimatedPickup': '12 mins',
          'broadcastPk': 'bcast_2',
        }
      ]),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biddingProvider.overrideWith((ref) => biddingNotifier),
        ],
        child: const MaterialApp(
          home: BiddingMarketplaceScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify widgets
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('drv_test_1'), findsOneWidget);
    expect(find.text('\$150.00'), findsOneWidget);
    expect(find.text('5 mins'), findsOneWidget);

    expect(find.text('drv_test_2'), findsOneWidget);
    expect(find.text('\$120.50'), findsOneWidget);
    expect(find.text('12 mins'), findsOneWidget);

    expect(find.text('Accept Bid'), findsNWidgets(2));

    // Tap the first "Accept Bid" button
    await tester.tap(find.text('Accept Bid').first);
    await tester.pump();

    // Verify SnackBar message appears
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('Accepted bid from drv_test_1 for \$150.00'),
      findsOneWidget,
    );
  });

  testWidgets('displays clean error message when state is error',
      (WidgetTester tester) async {
    final biddingNotifier = MockBiddingNotifier(
      fakeWsService,
      const BiddingState.error(message: 'WebSocket connection dropped'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biddingProvider.overrideWith((ref) => biddingNotifier),
        ],
        child: const MaterialApp(
          home: BiddingMarketplaceScreen(),
        ),
      ),
    );

    await tester.pump();

    // Verify error UI components
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('Connection Failure'), findsOneWidget);
    expect(find.text('WebSocket connection dropped'), findsOneWidget);
  });
}
