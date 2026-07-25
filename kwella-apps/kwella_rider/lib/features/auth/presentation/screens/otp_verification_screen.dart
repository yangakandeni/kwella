import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:pinput/pinput.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Rider – OTP Verification Screen
// Pinput-driven 6-digit code (visible, editable), 60-second countdown
// resend, success push.
// ─────────────────────────────────────────────────────────────────────────────

class OtpVerificationScreen extends ConsumerStatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  static const int _codeLength = 6;
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  int _secondsLeft = 60;
  Timer? _timer;

  /// True right after an incorrect-code retry, so Pinput renders its error
  /// theme and error text. The wrong digits stay on screen — cleared only
  /// once the user edits them — so the user can fix a mistyped digit
  /// rather than retyping the whole code from scratch.
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  bool get _isComplete => _pinController.text.length == _codeLength;

  void _verify() {
    if (!_isComplete) return;
    ref.read(kwellaAuthNotifierProvider.notifier).verifyOtp(_pinController.text);
  }

  void _resend() {
    final phoneNumber =
        ref.read(kwellaAuthNotifierProvider).pendingPhoneNumber;
    if (phoneNumber != null) {
      ref.read(kwellaAuthNotifierProvider.notifier).requestOtp(phoneNumber);
    }
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<KwellaAuthState>(kwellaAuthNotifierProvider, (previous, next) {
      if (next.status == KwellaAuthStatus.authenticated) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/rider/home',
          (route) => false,
        );
        return;
      }

      // An incorrect-but-retryable answer re-issues the challenge rather
      // than failing outright — show it as an inline Pinput error instead
      // of a snackbar, and leave the wrong digits in place so the user can
      // edit just the mistyped one rather than retyping the whole code.
      final bool isRetryableError =
          previous?.status == KwellaAuthStatus.authenticating &&
              next.status == KwellaAuthStatus.otpRequired &&
              next.error != null;
      if (isRetryableError) {
        setState(() => _hasError = true);
        return;
      }

      if (next.status == KwellaAuthStatus.failure && next.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final authState = ref.watch(kwellaAuthNotifierProvider);
    final loading = authState.status == KwellaAuthStatus.authenticating;
    final phoneNumber = authState.pendingPhoneNumber;

    return Scaffold(
      backgroundColor: KwellaColors.canvas,
      appBar: AppBar(
        backgroundColor: KwellaColors.canvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: KwellaColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text(
                'Enter the code',
                style: TextStyle(
                  color: KwellaColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                phoneNumber != null
                    ? 'We have sent you a verification code to $phoneNumber'
                    : 'Enter the 6-digit code sent to your number.',
                style: const TextStyle(
                  color: KwellaColors.textSecondary,
                  fontSize: 15,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 40),
              // ── OTP input ────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: Pinput(
                  key: const Key('otp_pinput'),
                  length: _codeLength,
                  controller: _pinController,
                  focusNode: _focusNode,
                  autofocus: true,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  closeKeyboardWhenCompleted: false,
                  pinAnimationType: PinAnimationType.fade,
                  forceErrorState: _hasError,
                  errorText: _hasError ? authState.error : null,
                  errorTextStyle: const TextStyle(
                    color: KwellaColors.errorRed,
                    fontSize: 13,
                    fontFamily: 'Outfit',
                  ),
                  defaultPinTheme: PinTheme(
                    width: 48,
                    height: 56,
                    textStyle: const TextStyle(
                      color: KwellaColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Outfit',
                    ),
                    decoration: BoxDecoration(
                      color: KwellaColors.elevatedCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KwellaColors.borderDark),
                    ),
                  ),
                  focusedPinTheme: PinTheme(
                    width: 48,
                    height: 56,
                    textStyle: const TextStyle(
                      color: KwellaColors.electricLime,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Outfit',
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A00),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: KwellaColors.electricLime, width: 2),
                    ),
                  ),
                  submittedPinTheme: PinTheme(
                    width: 48,
                    height: 56,
                    textStyle: const TextStyle(
                      color: KwellaColors.electricLime,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Outfit',
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A00),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: KwellaColors.electricLime, width: 2),
                    ),
                  ),
                  errorPinTheme: PinTheme(
                    width: 48,
                    height: 56,
                    textStyle: const TextStyle(
                      color: KwellaColors.errorRed,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Outfit',
                    ),
                    decoration: BoxDecoration(
                      color: KwellaColors.elevatedCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KwellaColors.errorRed, width: 2),
                    ),
                  ),
                  onChanged: (_) {
                    if (_hasError) {
                      setState(() => _hasError = false);
                    } else {
                      setState(() {});
                    }
                  },
                  onCompleted: (_) => _verify(),
                ),
              ),
              const SizedBox(height: 28),
              // ── Resend timer ─────────────────────────────────────────────
              Center(
                child: _secondsLeft > 0
                    ? Text(
                        'Resend code in ${_secondsLeft}s',
                        style: const TextStyle(
                          color: Color(0xFF606060),
                          fontSize: 14,
                          fontFamily: 'Outfit',
                        ),
                      )
                    : TextButton(
                        key: const Key('resend_otp_button'),
                        onPressed: _resend,
                        child: const Text(
                          'Resend code',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ),
              ),
              const Spacer(),
              // ── Verify CTA ───────────────────────────────────────────────
              AnimatedOpacity(
                opacity: _isComplete ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    key: const Key('verify_otp_button'),
                    onPressed: _isComplete && !loading ? _verify : null,
                    child: loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF1A1A00),
                            ),
                          )
                        : const Text(
                            'Verify',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Outfit',
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
