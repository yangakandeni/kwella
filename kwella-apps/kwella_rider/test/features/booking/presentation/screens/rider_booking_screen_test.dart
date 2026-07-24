import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';
import 'package:kwella_rider/features/booking/presentation/screens/rider_booking_screen.dart';

void main() {
  testWidgets(
    'idle state shows the collapsed search sheet, without pickup/dropoff inputs',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();

      await tester.pumpWidget(
        MaterialApp(home: RiderBookingScreen(controller: controller)),
      );

      expect(find.byKey(const Key('search_bar')), findsOneWidget);
      expect(find.byKey(const Key('pickup_input')), findsNothing);
      expect(find.byKey(const Key('dropoff_input')), findsNothing);
      expect(find.byKey(const Key('profile_avatar')), findsNothing);
      expect(find.text('Set your destination to get started'), findsNothing);

      controller.dispose();
    },
  );

  testWidgets(
    'tapping the search bar navigates to the destination selection screen',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/rider/destination': (_) =>
                const Scaffold(body: Text('Destination Screen')),
          },
          home: RiderBookingScreen(controller: controller),
        ),
      );

      await tester.tap(find.byKey(const Key('search_bar')));
      await tester.pumpAndSettle();

      expect(find.text('Destination Screen'), findsOneWidget);

      controller.dispose();
    },
  );

  testWidgets(
    'tapping a quick destination navigates to the destination screen with it pre-filled',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/rider/destination': (context) => Scaffold(
                  body: Text(
                    'Destination: ${ModalRoute.of(context)!.settings.arguments}',
                  ),
                ),
          },
          home: RiderBookingScreen(controller: controller),
        ),
      );

      await tester.tap(find.text('Zevenwacht Mall'));
      await tester.pumpAndSettle();

      expect(find.text('Destination: Zevenwacht Mall'), findsOneWidget);

      controller.dispose();
    },
  );

  testWidgets(
    'once a trip is active, the pickup/dropoff editor and passenger selector become visible and interactive',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();
      controller.handleIncomingWebSocketEvent({
        'action': 'tripMatchConfirmed',
        'tripId': 'trip-001',
      });

      await tester.pumpWidget(
        MaterialApp(home: RiderBookingScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pickup_input')), findsOneWidget);
      expect(find.byKey(const Key('dropoff_input')), findsOneWidget);
      expect(find.byKey(const Key('passenger_1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('passenger_4')));
      await tester.pumpAndSettle();
      expect(controller.state.passengerCount, equals(4));

      await tester.tap(find.byKey(const Key('request_ride_button')));
      await tester.pumpAndSettle();
      expect(controller.state.status, equals(RiderTripStatus.searching));

      controller.dispose();
    },
  );
}
