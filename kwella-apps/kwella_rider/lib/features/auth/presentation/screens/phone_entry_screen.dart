import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Rider – Phone Entry Screen
// +27 prefix chip, numeric input, "Send OTP" CTA.
// ─────────────────────────────────────────────────────────────────────────────

class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _sendOtp() {
    if (_ctrl.text.length < 9) return;
    setState(() => _loading = true);
    // In production: fire KwellaAuthNotifier.sendOtp('+27${_ctrl.text}')
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _loading = false);
        Navigator.pushNamed(context, '/auth/otp');
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
              // ── Heading ─────────────────────────────────────────────────
              const Text(
                'Enter your\nphone number',
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
                'We\'ll send a one-time code to verify it\'s you.',
                style: TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 15,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 36),
              // ── Phone field ──────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: Row(
                  children: [
                    // +27 prefix chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 16),
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: Color(0xFF2C2C2C)),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            '🇿🇦',
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '+27',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Number input
                    Expanded(
                      child: TextField(
                        key: const Key('phone_input'),
                        controller: _ctrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          letterSpacing: 1.5,
                          fontFamily: 'Outfit',
                        ),
                        decoration: const InputDecoration(
                          hintText: '81 234 5678',
                          hintStyle: TextStyle(
                            color: Color(0xFF606060),
                            letterSpacing: 0.5,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // ── Send OTP CTA ─────────────────────────────────────────────
              AnimatedOpacity(
                opacity: _ctrl.text.length >= 9 ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    key: const Key('send_otp_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDFFF00),
                      foregroundColor: const Color(0xFF1A1A00),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _ctrl.text.length >= 9 && !_loading
                        ? _sendOtp
                        : null,
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
                            'Send OTP',
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
