import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/booking/presentation/widgets/passenger_stepper.dart';

void main() {
  Future<void> pumpStepper(
    WidgetTester tester, {
    required int count,
    required ValueChanged<int> onChanged,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PassengerStepper(count: count, onChanged: onChanged),
        ),
      ),
    );
  }

  testWidgets('displays the current passenger count', (tester) async {
    await pumpStepper(tester, count: 3, onChanged: (_) {});

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tapping increment reports count + 1', (tester) async {
    int? reported;
    await pumpStepper(tester, count: 1, onChanged: (v) => reported = v);

    await tester.tap(find.byKey(const Key('passenger_increment')));
    await tester.pump();

    expect(reported, equals(2));
  });

  testWidgets('tapping decrement reports count - 1', (tester) async {
    int? reported;
    await pumpStepper(tester, count: 4, onChanged: (v) => reported = v);

    await tester.tap(find.byKey(const Key('passenger_decrement')));
    await tester.pump();

    expect(reported, equals(3));
  });

  testWidgets('increment is disabled at the maximum of 6', (tester) async {
    int? reported;
    await pumpStepper(tester, count: 6, onChanged: (v) => reported = v);

    await tester.tap(find.byKey(const Key('passenger_increment')));
    await tester.pump();

    expect(reported, isNull);
  });

  testWidgets('decrement is disabled at the minimum of 1', (tester) async {
    int? reported;
    await pumpStepper(tester, count: 1, onChanged: (v) => reported = v);

    await tester.tap(find.byKey(const Key('passenger_decrement')));
    await tester.pump();

    expect(reported, isNull);
  });
}
