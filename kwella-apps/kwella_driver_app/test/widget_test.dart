import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kwella_driver_app/main.dart';

void main() {
  testWidgets('KwellaDriverApp renders without crashing',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: KwellaDriverApp()),
    );
    // Auth gate renders while checking auth state.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
