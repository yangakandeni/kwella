import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kwella_rider/main.dart';

void main() {
  testWidgets('RiderBookingScreen compile and render smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: KwellaRiderApp()));

    // Verify that WelcomeScreen displays the Get Started button.
    expect(find.text('Get Started'), findsOneWidget);
  });
}
