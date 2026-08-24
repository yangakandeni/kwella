import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kwella_driver/features/bidding/presentation/screens/driver_profile_setup_screen.dart';

void main() {
  testWidgets(
      'submitting the empty form shows a required-field validation error per field and makes no network call',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DriverProfileSetupScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('submit_profile_setup_button')));
    await tester.pump();

    expect(find.text('Full Name is required'), findsOneWidget);
    expect(find.text('CATA Sticker ID is required'), findsOneWidget);
    expect(find.text('Vehicle Make is required'), findsOneWidget);
    expect(find.text('Vehicle Model is required'), findsOneWidget);
    expect(find.text('Vehicle Color is required'), findsOneWidget);
    expect(find.text('License Plate is required'), findsOneWidget);
  });
}
