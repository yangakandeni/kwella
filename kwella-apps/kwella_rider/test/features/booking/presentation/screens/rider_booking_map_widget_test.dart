import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/screens/rider_booking_screen.dart';

void main() {
  late KwellaRiderController controller;

  setUp(() {
    controller = KwellaRiderController();
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets(
    'live driver location updates render the tracking marker without layout exceptions',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kwellaRiderControllerProvider.overrideWithValue(controller),
          ],
          child: const MaterialApp(home: RiderBookingScreen()),
        ),
      );

      expect(find.text('Map placeholder'), findsOneWidget);
      expect(find.byKey(const Key('driver_marker')), findsNothing);

      controller.handleIncomingWebSocketEvent({
        'action': 'tripMatchConfirmed',
        'tripId': 'trip-001',
      });
      controller.handleIncomingWebSocketEvent({
        'action': 'liveDriverLocation',
        'latitude': -34.0123,
        'longitude': 18.6123,
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));

      expect(find.byKey(const Key('driver_marker')), findsOneWidget);
      expect(
        find.textContaining('Tracking driver at -34.0123, 18.6123'),
        findsOneWidget,
      );

      controller.handleIncomingWebSocketEvent({
        'action': 'liveDriverLocation',
        'latitude': -34.0100,
        'longitude': 18.6200,
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));

      expect(
        find.textContaining('Tracking driver at -34.0100, 18.6200'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('driver_marker')), findsOneWidget);
    },
  );

  testWidgets(
    'arrival banner renders instantly when geofence ARRIVED event occurs',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kwellaRiderControllerProvider.overrideWithValue(controller),
          ],
          child: const MaterialApp(home: RiderBookingScreen()),
        ),
      );

      controller.handleIncomingWebSocketEvent({
        'action': 'tripMatchConfirmed',
        'tripId': 'trip-002',
      });
      controller.handleIncomingWebSocketEvent({
        'action': 'geofenceTrigger',
        'geofence_status': 'ARRIVED',
      });

      await tester.pump();

      expect(
        find.text('Your driver has arrived! Meet them at the pickup point.'),
        findsOneWidget,
      );
    },
  );
}
