import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

import 'src/features/home/rider_home_screen.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: KwellaRiderApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// App root – theme sourced entirely from kwella_core
// ---------------------------------------------------------------------------
class KwellaRiderApp extends StatelessWidget {
  const KwellaRiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kwella Rider',
      debugShowCheckedModeBanner: false,
      // ── Consume the global light theme from kwella_core ───────────────
      theme: KwellaTheme.lightTheme,
      home: const RiderAuthGate(),
    );
  }
}

// ---------------------------------------------------------------------------
// Auth gate – reactive router driven by kwellaAuthNotifierProvider
// ---------------------------------------------------------------------------
class RiderAuthGate extends ConsumerWidget {
  const RiderAuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(kwellaAuthNotifierProvider);

    return switch (authState.status) {
      KwellaAuthStatus.authenticating => const _SplashScreen(),
      KwellaAuthStatus.otpRequired => const RiderOtpScreen(),
      KwellaAuthStatus.authenticated => _resolveAuthenticatedScreen(
          context,
          ref,
          authState,
        ),
      _ => const RiderPhoneEntryScreen(), // unauthenticated | failure
    };
  }

  Widget _resolveAuthenticatedScreen(
    BuildContext context,
    WidgetRef ref,
    KwellaAuthState authState,
  ) {
    if (authState.role == 'rider') {
      return const RiderHomeScreen();
    }

    // Wrong role – sign out and show an informational dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(kwellaAuthNotifierProvider.notifier).signOut();
      if (context.mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Access Denied'),
            content: Text(
              'This account (role: ${authState.role ?? 'unknown'}) is not '
              'authorized to use the Kwella Rider app.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });

    return const _SplashScreen();
  }
}

// ---------------------------------------------------------------------------
// Splash / loading screen
// ---------------------------------------------------------------------------
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KwellaColors.communityCream,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Brand mark
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: KwellaColors.cataTransitGreen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.directions_car_rounded,
                color: KwellaColors.deepSlate,
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'KWELLA',
              style: TextStyle(
                color: KwellaColors.textOnLight,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Rider',
              style: TextStyle(
                color: KwellaColors.cataTransitGreen,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(KwellaColors.cataTransitGreen),
              strokeWidth: 2.5,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rider Phone Entry screen
// ---------------------------------------------------------------------------
class RiderPhoneEntryScreen extends ConsumerStatefulWidget {
  const RiderPhoneEntryScreen({super.key});

  @override
  ConsumerState<RiderPhoneEntryScreen> createState() =>
      _RiderPhoneEntryScreenState();
}

class _RiderPhoneEntryScreenState extends ConsumerState<RiderPhoneEntryScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  // Pre-filled with a test number for the current testing phase (OTP
  // delivery is not yet wired to real SMS) — still editable for real numbers.
  final _phoneCtrl = TextEditingController(text: '+27821234567');
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSendCode() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref
        .read(kwellaAuthNotifierProvider.notifier)
        .requestOtp(_phoneCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(kwellaAuthNotifierProvider);
    final isLoading = authState.status == KwellaAuthStatus.authenticating;

    return Scaffold(
      backgroundColor: KwellaColors.communityCream,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ─────────────────────────────────────────
                  _buildHeader(),
                  const SizedBox(height: 48),

                  // ── Error banner ───────────────────────────────────
                  if (authState.status == KwellaAuthStatus.failure &&
                      authState.error != null)
                    buildAuthErrorBanner(authState.error!),

                  // ── Phone number field ──────────────────────────────
                  TextFormField(
                    key: const Key('rider_phone_field'),
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style:
                        const TextStyle(color: KwellaColors.textOnLight),
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+27821234567',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your phone number';
                      }
                      if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(v.trim())) {
                        return 'Enter a valid phone number, e.g. +27821234567';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // ── Send code button ────────────────────────────────
                  ElevatedButton(
                    key: const Key('rider_send_code_button'),
                    onPressed: isLoading ? null : _handleSendCode,
                    child: isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: KwellaColors.deepSlate,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text('Send code'),
                  ),
                  const SizedBox(height: 24),

                  // ── Footer ─────────────────────────────────────────
                  Center(
                    child: Text(
                      'Kwella Rider · v1.0',
                      style: TextStyle(
                        color: KwellaColors.textOnLightMuted
                            .withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: KwellaColors.cataTransitGreen,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.directions_car_rounded,
            color: KwellaColors.deepSlate,
            size: 28,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Welcome back,\nRider',
          style: TextStyle(
            color: KwellaColors.textOnLight,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Enter your phone number and we'll send you a one-time code",
          style:
              TextStyle(color: KwellaColors.textOnLightMuted, fontSize: 15),
        ),
      ],
    );
  }
}

/// Shared error banner styling for the phone-entry and OTP screens.
Widget buildAuthErrorBanner(String error) {
  return Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: KwellaColors.errorRed.withValues(alpha: 0.10),
      border: Border.all(color: KwellaColors.errorRed.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded,
            color: KwellaColors.errorRed, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            error,
            style: const TextStyle(color: KwellaColors.errorRed, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Rider OTP Verification screen
// ---------------------------------------------------------------------------
class RiderOtpScreen extends ConsumerStatefulWidget {
  const RiderOtpScreen({super.key});

  @override
  ConsumerState<RiderOtpScreen> createState() => _RiderOtpScreenState();
}

class _RiderOtpScreenState extends ConsumerState<RiderOtpScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  // Pre-filled with the fixed testing-phase code issued by the
  // CreateAuthChallenge Lambda — still editable once real SMS delivery lands.
  final _otpCtrl = TextEditingController(text: '123456');
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref
        .read(kwellaAuthNotifierProvider.notifier)
        .verifyOtp(_otpCtrl.text.trim());
  }

  Future<void> _handleResendCode() async {
    final phoneNumber = ref.read(kwellaAuthNotifierProvider).pendingPhoneNumber;
    if (phoneNumber == null) return;
    await ref.read(kwellaAuthNotifierProvider.notifier).requestOtp(phoneNumber);
  }

  Future<void> _handleUseDifferentNumber() async {
    await ref.read(kwellaAuthNotifierProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(kwellaAuthNotifierProvider);
    final isLoading = authState.status == KwellaAuthStatus.authenticating;
    final phoneNumber = authState.pendingPhoneNumber ?? 'your phone';

    return Scaffold(
      backgroundColor: KwellaColors.communityCream,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ─────────────────────────────────────────
                  Text(
                    'Enter your code',
                    style: TextStyle(
                      color: KwellaColors.textOnLight,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a code to $phoneNumber',
                    style: TextStyle(
                        color: KwellaColors.textOnLightMuted, fontSize: 15),
                  ),
                  const SizedBox(height: 48),

                  // ── Error banner ───────────────────────────────────
                  if (authState.status == KwellaAuthStatus.otpRequired &&
                      authState.error != null)
                    buildAuthErrorBanner(authState.error!),

                  // ── OTP field ────────────────────────────────────────
                  TextFormField(
                    key: const Key('rider_otp_field'),
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    style:
                        const TextStyle(color: KwellaColors.textOnLight),
                    decoration: const InputDecoration(
                      labelText: 'One-time code',
                      prefixIcon: Icon(Icons.password_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter the code';
                      }
                      if (!RegExp(r'^\d{6}$').hasMatch(v.trim())) {
                        return 'Enter the 6-digit code';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // ── Verify button ───────────────────────────────────
                  ElevatedButton(
                    key: const Key('rider_otp_submit_button'),
                    onPressed: isLoading ? null : _handleVerify,
                    child: isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: KwellaColors.deepSlate,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text('Verify'),
                  ),
                  const SizedBox(height: 16),

                  // ── Resend / change number actions ──────────────────
                  Center(
                    child: TextButton(
                      onPressed: isLoading ? null : _handleResendCode,
                      child: const Text('Resend code'),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: isLoading ? null : _handleUseDifferentNumber,
                      child: const Text('Use a different number'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

