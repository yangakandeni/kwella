import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';
import 'package:kwella_rider/features/booking/presentation/screens/rider_booking_screen.dart';

void main() {
  testWidgets(
    'booking screen starts collapsed, expands on search bar tap, and dispatches request ride',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();

      await tester.pumpWidget(
        MaterialApp(home: RiderBookingScreen(controller: controller)),
      );

      // Idle state shows the collapsed search sheet, not the full editor.
      expect(find.byKey(const Key('search_bar')), findsOneWidget);
      expect(find.byKey(const Key('pickup_input')), findsNothing);
      expect(find.byKey(const Key('dropoff_input')), findsNothing);

      await tester.tap(find.byKey(const Key('search_bar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pickup_input')), findsOneWidget);
      expect(find.byKey(const Key('dropoff_input')), findsOneWidget);
      expect(find.byKey(const Key('passenger_1')), findsOneWidget);
      expect(find.text('Request Ride'), findsOneWidget);

      await tester.tap(find.byKey(const Key('passenger_4')));
      await tester.pumpAndSettle();
      expect(controller.state.passengerCount, equals(4));

      await tester.tap(find.byKey(const Key('request_ride_button')));
      await tester.pumpAndSettle();

      expect(controller.state.status, equals(RiderTripStatus.searching));
      controller.dispose();
    },
  );

  testWidgets(
    'tapping a quick destination prefills dropoff and expands the editor',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();

      await tester.pumpWidget(
        MaterialApp(home: RiderBookingScreen(controller: controller)),
      );

      await tester.tap(find.text('Zevenwacht Mall'));
      await tester.pumpAndSettle();

      expect(controller.state.dropoffLocation, equals('Zevenwacht Mall'));
      expect(find.byKey(const Key('dropoff_input')), findsOneWidget);
      controller.dispose();
    },
  );
}
