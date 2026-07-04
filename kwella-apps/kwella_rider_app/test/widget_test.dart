import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kwella_rider_app/main.dart';

void main() {
  testWidgets('KwellaRiderApp renders without crashing',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: KwellaRiderApp()),
    );
    // Auth gate renders while checking auth state.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
