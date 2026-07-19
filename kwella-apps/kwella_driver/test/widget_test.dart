import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kwella_driver/main.dart';

void main() {
  testWidgets('KwellaDriverApp compile and offline screen smoke test',
      (WidgetTester tester) async {
    // Provide a finite display size so CustomPaint with Size.infinite
    // resolves against a bounded parent in the test environment.
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.resetPhysicalSize);

    // Build our app and allow Riverpod providers + AnimatedSwitcher to settle.
    await tester.pumpWidget(const ProviderScope(child: KwellaDriverApp()));
    await tester.pump();

    // Verify that the offline layout is active (GO puck visible).
    expect(find.text('GO'), findsOneWidget);
    expect(find.text('You are offline'), findsOneWidget);
  });
}
