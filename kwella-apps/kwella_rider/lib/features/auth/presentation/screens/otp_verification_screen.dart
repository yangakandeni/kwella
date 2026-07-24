import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Rider – OTP Verification Screen
// 6 auto-advancing digit boxes, 60-second countdown resend, success push.
// ─────────────────────────────────────────────────────────────────────────────

class OtpVerificationScreen extends ConsumerStatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  static const int _codeLength = 6;
  final List<TextEditingController> _ctrlList =
      List.generate(_codeLength, (_) => TextEditingController());
  final List<FocusNode> _focusList =
      List.generate(_codeLength, (_) => FocusNode());

  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _ctrlList) {
      c.dispose();
    }
    for (final f in _focusList) {
      f.dispose();
    }
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

  String get _otpValue => _ctrlList.map((c) => c.text).join();

  bool get _isComplete => _otpValue.length == _codeLength;

  void _verify() {
    if (!_isComplete) return;
    ref.read(kwellaAuthNotifierProvider.notifier).verifyOtp(_otpValue);
  }

  void _resend() {
    final phoneNumber =
        ref.read(kwellaAuthNotifierProvider).pendingPhoneNumber;
    if (phoneNumber != null) {
      ref.read(kwellaAuthNotifierProvider.notifier).requestOtp(phoneNumber);
    }
    _startTimer();
  }

  void _clearCode() {
    for (final c in _ctrlList) {
      c.clear();
    }
    _focusList.first.requestFocus();
    setState(() {});
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

      if (next.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }

      // An incorrect-but-retryable answer re-issues the challenge rather
      // than failing outright — clear the boxes so the user can retry.
      if (previous?.status == KwellaAuthStatus.authenticating &&
          next.status == KwellaAuthStatus.otpRequired) {
        _clearCode();
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
              // ── OTP boxes ───────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_codeLength, (i) {
                  return _OtpBox(
                    controller: _ctrlList[i],
                    focusNode: _focusList[i],
                    onChanged: (val) {
                      if (val.length == 1 && i < _codeLength - 1) {
                        FocusScope.of(context).requestFocus(_focusList[i + 1]);
                      }
                      if (val.isEmpty && i > 0) {
                        FocusScope.of(context).requestFocus(_focusList[i - 1]);
                      }
                      setState(() {});
                    },
                  );
                }),
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

// ── Single OTP digit box ────────────────────────────────────────────────────

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool filled = controller.text.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 48,
      height: 56,
      decoration: BoxDecoration(
        color: filled ? const Color(0xFF1A1A00) : KwellaColors.elevatedCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: filled ? KwellaColors.electricLime : KwellaColors.borderDark,
          width: filled ? 2 : 1,
        ),
      ),
      child: Center(
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          obscureText: true,
          obscuringCharacter: '●',
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: KwellaColors.electricLime,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            fontFamily: 'Outfit',
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
