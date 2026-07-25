import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:kwella_rider/features/auth/presentation/screens/phone_entry_screen.dart';

import '../../support/mock_cognito.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(overrides: [
      kwellaAuthNotifierProvider.overrideWith(
        (ref) => buildMockAuthNotifier(
          MockCognitoInterceptor(MockOtpVerifyMode.correct),
        ),
      ),
    ]);
    addTearDown(container.dispose);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: const PhoneEntryScreen(),
          routes: {
            '/auth/otp': (context) => const SizedBox(),
          },
        ),
      ),
    );
  }

  testWidgets('Send OTP button is disabled until a valid number is entered',
      (tester) async {
    await pumpScreen(tester);

    final button =
        tester.widget<ElevatedButton>(find.byKey(const Key('send_otp_button')));
    expect(button.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('phone_input')), '071766228');
    await tester.pump();
    final stillIncomplete =
        tester.widget<ElevatedButton>(find.byKey(const Key('send_otp_button')));
    expect(stillIncomplete.onPressed, isNull,
        reason: '9 raw digits with a leading 0 is one short of a valid '
            '9-digit subscriber number');

    await tester.enterText(find.byKey(const Key('phone_input')), '0717662280');
    await tester.pump();
    final complete =
        tester.widget<ElevatedButton>(find.byKey(const Key('send_otp_button')));
    expect(complete.onPressed, isNotNull);
  });

  testWidgets(
      'local format (leading 0) normalizes to +27 E.164 and requests OTP',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byKey(const Key('phone_input')), '0717662280');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_otp_button')));
    await tester.pumpAndSettle();

    expect(
      container.read(kwellaAuthNotifierProvider).pendingPhoneNumber,
      '+27717662280',
    );
  });

  testWidgets(
      'international format without + does not duplicate the country code '
      'or truncate the final digit', (tester) async {
    await pumpScreen(tester);

    // Regression: this used to be truncated to 10 raw digits ("2771766228")
    // and then re-prefixed with "+27", producing "+272771766228".
    await tester.enterText(find.byKey(const Key('phone_input')), '27717662280');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_otp_button')));
    await tester.pumpAndSettle();

    expect(
      container.read(kwellaAuthNotifierProvider).pendingPhoneNumber,
      '+27717662280',
    );
  });

  testWidgets('bare subscriber number (no prefix) also normalizes correctly',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byKey(const Key('phone_input')), '717662280');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_otp_button')));
    await tester.pumpAndSettle();

    expect(
      container.read(kwellaAuthNotifierProvider).pendingPhoneNumber,
      '+27717662280',
    );
  });

  testWidgets('shows a live plain-E.164 preview of the normalized number',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('phone_preview_text')), findsNothing);

    await tester.enterText(find.byKey(const Key('phone_input')), '0717662280');
    await tester.pump();

    expect(find.text('We\'ll text +27717662280'), findsOneWidget);
  });
}
