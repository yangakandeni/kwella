import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Rider – Phone Entry Screen
// +27 prefix chip, numeric input, "Send OTP" CTA.
// ─────────────────────────────────────────────────────────────────────────────

class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _sendOtp() {
    if (_ctrl.text.length < 9) return;
    final digits = _ctrl.text.startsWith('0')
        ? _ctrl.text.substring(1)
        : _ctrl.text;
    ref.read(kwellaAuthNotifierProvider.notifier).requestOtp('+27$digits');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<KwellaAuthState>(kwellaAuthNotifierProvider, (previous, next) {
      if (next.status == KwellaAuthStatus.otpRequired) {
        Navigator.pushNamed(context, '/auth/otp');
      } else if (next.status == KwellaAuthStatus.failure && next.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final loading = ref.watch(kwellaAuthNotifierProvider).status ==
        KwellaAuthStatus.authenticating;

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
              // ── Heading ─────────────────────────────────────────────────
              const Text(
                'Verify your phone number',
                style: TextStyle(
                  color: KwellaColors.textPrimary,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'We\'ll send a one-time code to verify it\'s you.',
                style: TextStyle(
                  color: KwellaColors.textSecondary,
                  fontSize: 15,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 36),
              // ── Phone field ──────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: KwellaColors.elevatedCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: KwellaColors.borderDark),
                ),
                child: Row(
                  children: [
                    // +27 prefix chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 16),
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: KwellaColors.borderDark),
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
                              color: KwellaColors.textPrimary,
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
                          color: KwellaColors.textPrimary,
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
                    onPressed:
                        _ctrl.text.length >= 9 && !loading ? _sendOtp : null,
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
