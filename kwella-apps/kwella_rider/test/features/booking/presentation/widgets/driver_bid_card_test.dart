import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/booking/presentation/widgets/driver_bid_card.dart';

void main() {
  testWidgets('DriverBidCard renders driver info, vehicle, and fare price', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverBidCard(
            driverId: 'driver-001',
            driverName: 'Sipho',
            driverRating: '4.9 ★',
            vehicleDescription: 'White Suzuki Ertiga',
            licensePlate: 'CAA 123-456',
            cataSticker: 'M02356',
            fareLabel: 'Accept R135.0',
            onAccept: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('driver_name')), findsOneWidget);
    expect(find.text('Sipho'), findsOneWidget);
    expect(find.byKey(const Key('driver_rating')), findsOneWidget);
    expect(find.text('4.9 ★'), findsOneWidget);
    expect(find.byKey(const Key('vehicle_description')), findsOneWidget);
    expect(find.text('White Suzuki Ertiga'), findsOneWidget);
    expect(find.byKey(const Key('license_plate')), findsOneWidget);
    expect(find.text('License: CAA 123-456'), findsOneWidget);
    expect(find.byKey(const Key('cata_sticker')), findsOneWidget);
    expect(find.text('CATA Sticker: M02356'), findsOneWidget);
    expect(find.byKey(const Key('fare_label')), findsOneWidget);
    expect(find.text('Accept R135.0'), findsOneWidget);

    // No onDecline supplied — the Decline button must not render, and the
    // pre-existing Accept-only layout is untouched.
    expect(find.byKey(const Key('decline_button')), findsNothing);
    expect(find.byKey(const Key('eta_label')), findsNothing);
  });

  testWidgets('DriverBidCard renders the ETA label when supplied', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverBidCard(
            driverId: 'driver-001',
            driverName: 'Sipho',
            driverRating: '4.9 ★',
            vehicleDescription: 'White Suzuki Ertiga',
            licensePlate: 'CAA 123-456',
            cataSticker: 'M02356',
            fareLabel: 'Accept R135.0',
            onAccept: () {},
            etaLabel: 'ETA: 5 min',
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('eta_label')), findsOneWidget);
    expect(find.text('ETA: 5 min'), findsOneWidget);
  });

  testWidgets(
      'DriverBidCard renders a Decline button that fires onDecline, alongside Accept',
      (WidgetTester tester) async {
    bool declined = false;
    bool accepted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverBidCard(
            driverId: 'driver-001',
            driverName: 'Sipho',
            driverRating: '4.9 ★',
            vehicleDescription: 'White Suzuki Ertiga',
            licensePlate: 'CAA 123-456',
            cataSticker: 'M02356',
            fareLabel: 'Accept R135.0',
            onAccept: () => accepted = true,
            onDecline: () => declined = true,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('decline_button')), findsOneWidget);
    expect(find.byKey(const Key('accept_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('decline_button')));
    await tester.pump();
    expect(declined, isTrue);
    expect(accepted, isFalse);
  });
}
