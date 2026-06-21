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
  });
}
