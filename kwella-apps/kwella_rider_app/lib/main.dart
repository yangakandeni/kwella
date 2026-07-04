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
      KwellaAuthStatus.authenticated => _resolveAuthenticatedScreen(
          context,
          ref,
          authState,
        ),
      _ => const RiderLoginScreen(), // unauthenticated | failure
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
// Rider Login screen
// ---------------------------------------------------------------------------
class RiderLoginScreen extends ConsumerStatefulWidget {
  const RiderLoginScreen({super.key});

  @override
  ConsumerState<RiderLoginScreen> createState() => _RiderLoginScreenState();
}

class _RiderLoginScreenState extends ConsumerState<RiderLoginScreen>
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
                    _buildErrorBanner(authState.error!),

                  // ── Email field ────────────────────────────────────
                  TextFormField(
                    key: const Key('rider_email_field'),
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style:
                        const TextStyle(color: KwellaColors.textOnLight),
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
                    key: const Key('rider_password_field'),
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    style:
                        const TextStyle(color: KwellaColors.textOnLight),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon:
                          const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: KwellaColors.textOnLightMuted,
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
                    key: const Key('rider_login_button'),
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
          'Sign in to access your Kwella account',
          style:
              TextStyle(color: KwellaColors.textOnLightMuted, fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KwellaColors.errorRed.withValues(alpha: 0.10),
        border:
            Border.all(color: KwellaColors.errorRed.withValues(alpha: 0.4)),
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
// Rider Home screen – Phase 2: Booking layout shell
// ---------------------------------------------------------------------------

/// Full-screen booking layout.
///
/// Layout contract:
/// ┌──────────────────────────────────┐
/// │                                  │  ← ~60 % of screen height
/// │   Map placeholder (grey tint)    │
/// │                                  │
/// ├──────────────────────────────────┤
/// │ ╭──────────────────────────────╮ │  ← persistent bottom sheet
/// │ │  Drag handle                 │ │
/// │ │  ─────────────────────────── │ │
/// │ │  Destination input placeholder│ │
/// │ │  ─────────────────────────── │ │
/// │ │  Passenger count selector    │ │
/// │ ╰──────────────────────────────╯ │
/// └──────────────────────────────────┘
class RiderHomeScreen extends ConsumerStatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  ConsumerState<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends ConsumerState<RiderHomeScreen> {
  int _passengerCount = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KwellaColors.communityCream,
      body: _BookingShellLayout(
        mapSection: _MapPlaceholder(
          onSignOut: () =>
              ref.read(kwellaAuthNotifierProvider.notifier).signOut(),
        ),
        sheetContent: _BookingSheetContent(
          passengerCount: _passengerCount,
          onPassengerCountChanged: (v) =>
              setState(() => _passengerCount = v),
        ),
      ),
    );
  }
}

/// Positions the map and the bottom sheet using a [Stack].
class _BookingShellLayout extends StatelessWidget {
  const _BookingShellLayout({
    required this.mapSection,
    required this.sheetContent,
  });

  final Widget mapSection;
  final Widget sheetContent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Map region (60 % of screen) ───────────────────────────────
        Positioned.fill(
          child: Column(
            children: [
              Expanded(flex: 60, child: mapSection),
              // Reserve space so content isn't hidden beneath the sheet.
              // The sheet itself floats above this via the Stack.
              const Expanded(flex: 40, child: SizedBox()),
            ],
          ),
        ),

        // ── Persistent bottom sheet (40 % of screen) ──────────────────
        Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.42, // slightly taller to account for safe area
            widthFactor: 1.0,
            child: _RiderBottomSheet(child: sheetContent),
          ),
        ),
      ],
    );
  }
}

/// Greyed-out map placeholder with a sign-out FAB in the top-right corner.
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Textured map background ───────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFD4E8D0), Color(0xFFBFD8C0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: CustomPaint(
            painter: _MapGridPainter(),
            child: const SizedBox.expand(),
          ),
        ),

        // ── Centre pin ───────────────────────────────────────────────
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_rounded,
                color: KwellaColors.cataTransitGreen,
                size: 48,
              ),
              SizedBox(height: 4),
              Text(
                'Live map coming soon',
                style: TextStyle(
                  color: KwellaColors.deepSlate,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),

        // ── Sign-out button (top-right) ───────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: Material(
            color: KwellaColors.communityCream,
            borderRadius: BorderRadius.circular(12),
            elevation: 3,
            shadowColor: Colors.black12,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onSignOut,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.logout_rounded,
                  size: 20,
                  color: KwellaColors.textOnLight,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The Community Cream container with rounded top corners that holds the
/// booking controls.
class _RiderBottomSheet extends StatelessWidget {
  const _RiderBottomSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: KwellaColors.communityCream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Booking controls rendered inside the bottom sheet.
class _BookingSheetContent extends StatelessWidget {
  const _BookingSheetContent({
    required this.passengerCount,
    required this.onPassengerCountChanged,
  });

  final int passengerCount;
  final ValueChanged<int> onPassengerCountChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Drag handle ─────────────────────────────────────────────
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: KwellaColors.creamBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Section label ────────────────────────────────────────────
            const Text(
              'Where to?',
              style: TextStyle(
                color: KwellaColors.textOnLight,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),

            // ── Destination input placeholder ────────────────────────────
            _DestinationInputPlaceholder(),
            const SizedBox(height: 16),

            // ── Divider ──────────────────────────────────────────────────
            const Divider(
              color: KwellaColors.creamBorder,
              height: 1,
            ),
            const SizedBox(height: 16),

            // ── Passenger count selector ─────────────────────────────────
            _PassengerSelector(
              count: passengerCount,
              onChanged: onPassengerCountChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable destination input placeholder.
class _DestinationInputPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: KwellaColors.creamCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const Key('rider_destination_field'),
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // TODO: open destination search overlay
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KwellaColors.creamBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KwellaColors.cataTransitGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.search_rounded,
                  color: KwellaColors.cataTransitGreen,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Enter destination…',
                  style: TextStyle(
                    color: KwellaColors.textOnLightMuted,
                    fontSize: 15,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: KwellaColors.textOnLightMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline passenger count stepper (− count +).
class _PassengerSelector extends StatelessWidget {
  const _PassengerSelector({
    required this.count,
    required this.onChanged,
  });

  final int count;
  final ValueChanged<int> onChanged;

  static const int _min = 1;
  static const int _max = 6;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── Label side ────────────────────────────────────────────────
        const Icon(
          Icons.people_outline_rounded,
          color: KwellaColors.textOnLightMuted,
          size: 22,
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Passengers',
            style: TextStyle(
              color: KwellaColors.textOnLight,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // ── Stepper controls ─────────────────────────────────────────
        _StepperButton(
          key: const Key('rider_passenger_decrement'),
          icon: Icons.remove_rounded,
          enabled: count > _min,
          onPressed: () => onChanged(count - 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            '$count',
            style: const TextStyle(
              color: KwellaColors.textOnLight,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _StepperButton(
          key: const Key('rider_passenger_increment'),
          icon: Icons.add_rounded,
          enabled: count < _max,
          onPressed: () => onChanged(count + 1),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.35,
      duration: const Duration(milliseconds: 150),
      child: Material(
        color: KwellaColors.cataTransitGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 18,
              color: KwellaColors.cataTransitGreen,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map grid painter – lightweight grid lines to simulate a map backdrop
// ---------------------------------------------------------------------------
class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;

    const step = 40.0;

    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_MapGridPainter oldDelegate) => false;
}
