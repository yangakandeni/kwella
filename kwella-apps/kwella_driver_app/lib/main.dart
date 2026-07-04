import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: KwellaDriverApp(),
    ),
  );
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------
class KwellaDriverApp extends StatelessWidget {
  const KwellaDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kwella Driver',
      debugShowCheckedModeBanner: false,
      // ── Consume the global dark theme from kwella_core ────────────────
      theme: KwellaTheme.darkTheme,
      home: const DriverAuthGate(),
    );
  }
}

// ---------------------------------------------------------------------------
// Auth gate – reactive router driven by kwellaAuthNotifierProvider
// ---------------------------------------------------------------------------
class DriverAuthGate extends ConsumerWidget {
  const DriverAuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(kwellaAuthNotifierProvider);

    return switch (authState.status) {
      KwellaAuthStatus.authenticating => const _SplashScreen(),
      KwellaAuthStatus.authenticated => _resolveAuthenticatedScreen(
          context,
          ref,
          authState,
        ),
      _ => const DriverLoginScreen(), // unauthenticated | failure
    };
  }

  Widget _resolveAuthenticatedScreen(
    BuildContext context,
    WidgetRef ref,
    KwellaAuthState authState,
  ) {
    if (authState.role == 'driver') {
      return const DriverHomeScreen();
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
              'authorized to use the Kwella Driver app.',
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
      backgroundColor: KwellaColors.deepSlate,
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
                Icons.local_shipping_rounded,
                color: KwellaColors.deepSlate,
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'KWELLA',
              style: TextStyle(
                color: KwellaColors.textOnDark,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Driver',
              style: TextStyle(
                color: KwellaColors.cataTransitGreen,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                  KwellaColors.cataTransitGreen),
              strokeWidth: 2.5,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Driver Login screen
// ---------------------------------------------------------------------------
class DriverLoginScreen extends ConsumerStatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  ConsumerState<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends ConsumerState<DriverLoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
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
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref
        .read(kwellaAuthNotifierProvider.notifier)
        .signInWithEmailAndPassword(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(kwellaAuthNotifierProvider);
    final isLoading =
        authState.status == KwellaAuthStatus.authenticating;

    return Scaffold(
      backgroundColor: KwellaColors.deepSlate,
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
                    _buildErrorBanner(authState.error!),

                  // ── Email field ────────────────────────────────────
                  TextFormField(
                    key: const Key('driver_email_field'),
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: KwellaColors.textOnDark),
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Password field ─────────────────────────────────
                  TextFormField(
                    key: const Key('driver_password_field'),
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: KwellaColors.textOnDark),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: KwellaColors.textOnDarkMuted,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Please enter your password';
                      }
                      if (v.length < 6) return 'Password too short';
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // ── Login button ───────────────────────────────────
                  ElevatedButton(
                    key: const Key('driver_login_button'),
                    onPressed: isLoading ? null : _handleLogin,
                    child: isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: KwellaColors.deepSlate,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text('Login'),
                  ),
                  const SizedBox(height: 24),

                  // ── Footer ─────────────────────────────────────────
                  Center(
                    child: Text(
                      'Kwella Driver · v1.0',
                      style: TextStyle(
                        color: KwellaColors.textOnDarkMuted
                            .withValues(alpha: 0.5),
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
            Icons.local_shipping_rounded,
            color: KwellaColors.deepSlate,
            size: 28,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Welcome back,\nDriver',
          style: TextStyle(
            color: KwellaColors.textOnDark,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sign in to access your Kwella Driver account',
          style:
              TextStyle(color: KwellaColors.textOnDarkMuted, fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KwellaColors.errorRed.withValues(alpha: 0.12),
        border: Border.all(
            color: KwellaColors.errorRed.withValues(alpha: 0.4)),
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
              style: const TextStyle(
                  color: KwellaColors.errorRed, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Driver Home screen (placeholder)
// ---------------------------------------------------------------------------
class DriverHomeScreen extends ConsumerWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(kwellaAuthNotifierProvider);

    return Scaffold(
      backgroundColor: KwellaColors.deepSlate,
      appBar: AppBar(
        title: const Text(
          'Driver Dashboard',
          style: TextStyle(
            color: KwellaColors.textOnDark,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: KwellaColors.textOnDarkMuted,
            ),
            tooltip: 'Sign out',
            onPressed: () =>
                ref.read(kwellaAuthNotifierProvider.notifier).signOut(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: KwellaColors.cataTransitGreen,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: KwellaColors.deepSlate,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Driver Dashboard Active',
              style: TextStyle(
                color: KwellaColors.textOnDark,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              authState.email ?? '',
              style: const TextStyle(
                  color: KwellaColors.textOnDarkMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// Local KwellaTheme stub removed – all tokens are now sourced from
// kwella_core via KwellaColors and KwellaTheme.
