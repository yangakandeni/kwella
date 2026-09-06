import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';
import 'package:kwella_rider/features/booking/presentation/screens/active_search_screen.dart';

import '../../../../support/fake_websocket_gateway.dart';

void main() {
  late FakeWebSocketGateway fakeGateway;
  late KwellaRiderController controller;

  setUp(() {
    fakeGateway = FakeWebSocketGateway();
    controller = KwellaRiderController(gateway: fakeGateway);
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Map<String, WidgetBuilder> routes = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ActiveSearchScreen(controller: controller),
        routes: routes,
      ),
    );
    await tester.pump();
  }

  group('Fare +/- and raise fare', () {
    testWidgets('seeds the local offer from state.offeredFare and adjusts it locally',
        (tester) async {
      controller.handleIncomingWebSocketEvent({
        'status': 'TripBroadcast',
        'tripId': 'trip-1',
        'calculated_fare': '50',
      });

      await pumpScreen(tester);

      expect(find.text('R50'), findsOneWidget);

      await tester.tap(find.byKey(const Key('active_search_increase_fare_button')));
      await tester.pump();
      expect(find.text('R55'), findsOneWidget);

      await tester.tap(find.byKey(const Key('active_search_decrease_fare_button')));
      await tester.pump();
      expect(find.text('R50'), findsOneWidget);

      // Controller's own offeredFare is untouched by local adjustments —
      // only raiseFare() commits a new value.
      expect(controller.state.offeredFare, equals(50.0));
    });

    testWidgets(
        'disables Raise fare until the local offer exceeds state.offeredFare, then calls controller.raiseFare',
        (tester) async {
      controller.handleIncomingWebSocketEvent({
        'status': 'TripBroadcast',
        'tripId': 'trip-1',
        'calculated_fare': '50',
      });

      await pumpScreen(tester);

      ElevatedButton raiseButton() => tester
          .widget<ElevatedButton>(find.byKey(const Key('raise_fare_button')));

      expect(raiseButton().onPressed, isNull);

      await tester.tap(find.byKey(const Key('active_search_increase_fare_button')));
      await tester.pump();

      expect(raiseButton().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('raise_fare_button')));
      await tester.pump();

      final Map<String, dynamic> updateFareFrame = fakeGateway.sentPayloads
          .singleWhere((m) => m['action'] == 'updateFare');
      expect(updateFareFrame['tripId'], equals('trip-1'));
      expect(updateFareFrame['new_fare'], equals(55.0));
      expect(controller.state.offeredFare, equals(55.0));

      // Raise fare disables again once the offer has been committed.
      expect(raiseButton().onPressed, isNull);
    });
  });

  group('Nearby driver markers', () {
    testWidgets('renders a marker for each nearby driver on the map',
        (tester) async {
      controller.handleIncomingWebSocketEvent({
        'action': 'nearbyDriverUpdate',
        'driverId': 'driver-idle-1',
        'latitude': -33.91,
        'longitude': 18.42,
        'status': 'idle',
      });

      await pumpScreen(tester);

      final GoogleMap map =
          tester.widget<GoogleMap>(find.byKey(const Key('kwella_map_view')));
      final Marker marker = map.markers
          .singleWhere((m) => m.markerId == const MarkerId('nearby_driver-idle-1'));
      expect(marker.position, const LatLng(-33.91, 18.42));
    });
  });

  group('Bid sheet wiring', () {
    testWidgets('declining the only bid removes it and falls back to the fare +/- sheet',
        (tester) async {
      controller.handleIncomingWebSocketEvent({
        'action': 'driverBidReceived',
        'tripId': 'trip-1',
        'bidMetrics': [
          {'driverId': 'driver-1', 'driverName': 'Sipho', 'bidAmount': 60},
        ],
      });

      await pumpScreen(tester);

      expect(find.byKey(const Key('decline_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('decline_button')));
      await tester.pump();

      expect(controller.state.bidMetrics, isEmpty);
      expect(find.byKey(const Key('active_search_offer_value')), findsOneWidget);
      expect(find.byKey(const Key('decline_button')), findsNothing);
    });

    testWidgets('accepting the bid calls controller.selectBid', (tester) async {
      controller.handleIncomingWebSocketEvent({
        'action': 'driverBidReceived',
        'tripId': 'trip-1',
        'bidMetrics': [
          {'driverId': 'driver-1', 'driverName': 'Sipho', 'bidAmount': 60},
        ],
      });

      await pumpScreen(tester, routes: {
        '/rider/tracking': (_) => const SizedBox(key: Key('tracking_screen')),
      });

      final ElevatedButton acceptButton = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byKey(const Key('accept_button')),
          matching: find.byType(ElevatedButton),
        ),
      );
      acceptButton.onPressed!();
      await tester.pump();

      final Map<String, dynamic> selectBidFrame = fakeGateway.sentPayloads
          .singleWhere((m) => m['action'] == 'selectBid');
      expect(selectBidFrame['driverId'], equals('driver-1'));
      expect(controller.state.status, equals(RiderTripStatus.accepted));

      // The post-frame callback fires the auto-navigation to tracking. Not
      // pumpAndSettle: the outgoing ActiveSearchScreen still has its
      // DriverBidCard's pulsing accept-button animation ticking mid page
      // transition, which never settles — pump past the default
      // MaterialPageRoute transition duration instead.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byKey(const Key('tracking_screen')), findsOneWidget);
    });

    testWidgets(
        'Cancel request resets state and lands back on /rider/home',
        (tester) async {
      controller.handleIncomingWebSocketEvent({
        'action': 'driverBidReceived',
        'tripId': 'trip-1',
        'bidMetrics': [
          {'driverId': 'driver-1', 'driverName': 'Sipho', 'bidAmount': 60},
        ],
      });

      await pumpScreen(tester, routes: {
        '/rider/home': (_) => const SizedBox(key: Key('home_screen')),
      });

      await tester.tap(find.byKey(const Key('cancel_request_button')));
      // Not pumpAndSettle: same pulsing-animation-mid-transition caveat as
      // the accept test above.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(controller.state.status, equals(RiderTripStatus.idle));
      expect(controller.state.bidMetrics, isEmpty);
      expect(find.byKey(const Key('home_screen')), findsOneWidget);
    });
  });

  group('Back button', () {
    testWidgets('cancels the search then pops', (tester) async {
      controller.requestTrip();

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (_) => ActiveSearchScreen(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('back_button')));
      await tester.pump();

      expect(controller.state.status, equals(RiderTripStatus.idle));
    });
  });
}
