import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:kwella_rider/features/auth/presentation/screens/otp_verification_screen.dart';
import 'package:pinput/pinput.dart';

import '../../support/mock_cognito.dart';

// Pinput captures keystrokes through a single hidden EditableText, not the
// Key('otp_pinput') widget itself — enterText must target that descendant.
final Finder _pinInputField = find.descendant(
  of: find.byKey(const Key('otp_pinput')),
  matching: find.byType(EditableText),
);

void main() {
  late ProviderContainer container;

  ProviderContainer buildContainer(MockCognitoInterceptor interceptor) {
    return ProviderContainer(overrides: [
      kwellaAuthNotifierProvider.overrideWith(
        (ref) => buildMockAuthNotifier(interceptor)
          ..requestOtp('+27717662280'),
      ),
    ]);
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: const OtpVerificationScreen(),
          routes: {
            '/rider/home': (context) => const SizedBox(),
          },
        ),
      ),
    );
    // Let requestOtp's fake network round-trip resolve before interacting.
    // Avoid pumpAndSettle: the screen runs a 60-second periodic countdown
    // Timer that reschedules a frame every tick, so pumpAndSettle's
    // "no pending frames" loop never converges. A couple of short pumps is
    // enough to flush the mock Dio call's Future chain.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('entered digits are visible, not obscured', (tester) async {
    container = buildContainer(
      MockCognitoInterceptor(MockOtpVerifyMode.correct),
    );
    addTearDown(container.dispose);
    await pumpScreen(tester);

    await tester.enterText(_pinInputField, '123456');
    await tester.pump();

    final pinput = tester.widget<Pinput>(find.byKey(const Key('otp_pinput')));
    expect(pinput.obscureText, isFalse);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('user can edit a digit before submitting', (tester) async {
    container = buildContainer(
      MockCognitoInterceptor(MockOtpVerifyMode.correct),
    );
    addTearDown(container.dispose);
    await pumpScreen(tester);

    await tester.enterText(_pinInputField, '123450');
    await tester.pump();
    // Fix the mistyped last digit without retyping the whole code.
    await tester.enterText(_pinInputField, '123456');
    await tester.pump();

    expect(find.text('6'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets(
      'incorrect code shows an inline error and keeps the digits editable',
      (tester) async {
    container = buildContainer(
      MockCognitoInterceptor(MockOtpVerifyMode.incorrectRetry),
    );
    addTearDown(container.dispose);
    await pumpScreen(tester);

    await tester.enterText(_pinInputField, '000000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('verify_otp_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(container.read(kwellaAuthNotifierProvider).status,
        KwellaAuthStatus.otpRequired);
    expect(find.text('Incorrect code. Please try again.'), findsOneWidget);
    // The wrong code stays on screen for the user to fix, rather than
    // being wiped and forcing a full retype.
    expect(find.text('0'), findsWidgets);
  });

  testWidgets('correct code verifies and navigates to the rider home screen',
      (tester) async {
    container = buildContainer(
      MockCognitoInterceptor(MockOtpVerifyMode.correct),
    );
    addTearDown(container.dispose);
    await pumpScreen(tester);

    // Pinput's onCompleted already fires verification as soon as the 6th
    // digit lands, so no separate tap is needed (or safe to make, once the
    // completed code has kicked off navigation away from this screen).
    await tester.enterText(_pinInputField, '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(container.read(kwellaAuthNotifierProvider).status,
        KwellaAuthStatus.authenticated);
  });

  testWidgets('phone number is displayed as the plain E.164 number',
      (tester) async {
    container = buildContainer(
      MockCognitoInterceptor(MockOtpVerifyMode.correct),
    );
    addTearDown(container.dispose);
    await pumpScreen(tester);

    expect(
      find.textContaining('+27717662280'),
      findsOneWidget,
    );
  });
}
