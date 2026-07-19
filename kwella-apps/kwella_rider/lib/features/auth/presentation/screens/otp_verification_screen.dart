import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Rider – OTP Verification Screen
// 6 auto-advancing digit boxes, 60-second countdown resend, success push.
// ─────────────────────────────────────────────────────────────────────────────

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const int _codeLength = 6;
  final List<TextEditingController> _ctrlList =
      List.generate(_codeLength, (_) => TextEditingController());
  final List<FocusNode> _focusList =
      List.generate(_codeLength, (_) => FocusNode());

  int _secondsLeft = 60;
  Timer? _timer;
  bool _loading = false;

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

  String get _otpValue =>
      _ctrlList.map((c) => c.text).join();

  bool get _isComplete => _otpValue.length == _codeLength;

  void _verify() {
    if (!_isComplete) return;
    setState(() => _loading = true);
    // In production: KwellaAuthNotifier.verifyOtp(_otpValue)
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _loading = false);
        // Navigate to home and clear auth stack
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/rider/home',
          (route) => false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
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
                'Verify your\nnumber',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Enter the 6-digit code sent to your number.',
                style: TextStyle(
                  color: Color(0xFFA0A0A0),
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
                        onPressed: _startTimer,
                        child: const Text(
                          'Resend code',
                          style: TextStyle(
                            color: Color(0xFFDFFF00),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDFFF00),
                      foregroundColor: const Color(0xFF1A1A00),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isComplete && !_loading ? _verify : null,
                    child: _loading
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
        color: filled ? const Color(0xFF1A1A00) : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: filled ? const Color(0xFFDFFF00) : const Color(0xFF2C2C2C),
          width: filled ? 2 : 1,
        ),
      ),
      child: Center(
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: Color(0xFFDFFF00),
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
