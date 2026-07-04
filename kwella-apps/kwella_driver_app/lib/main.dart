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
// Driver Home screen  –  Phase 3 high-fidelity layout
// ---------------------------------------------------------------------------

/// Transit-route background painter.
///
/// Draws a simulated multi-stop route on the dark map canvas using
/// [KwellaColors.cataTransitGreen] as the primary route colour.
class _TransitRoutePainter extends CustomPainter {
  const _TransitRoutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Background grid (street-map effect) ──────────────────────────────
    final gridPaint = Paint()
      ..color = const Color(0xFF272D36)
      ..strokeWidth = 1.0;

    // Horizontal grid lines
    for (double y = 0; y < h; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }
    // Vertical grid lines
    for (double x = 0; x < w; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }

    // ── Off-route secondary roads ─────────────────────────────────────────
    final secondaryPaint = Paint()
      ..color = const Color(0xFF323A47)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
        Offset(w * 0.1, 0), Offset(w * 0.3, h * 0.5), secondaryPaint);
    canvas.drawLine(
        Offset(w * 0.3, h * 0.5), Offset(w * 0.6, h * 0.9), secondaryPaint);
    canvas.drawLine(
        Offset(w * 0.85, 0), Offset(w * 0.7, h * 0.45), secondaryPaint);
    canvas.drawLine(
        Offset(w * 0.7, h * 0.45), Offset(w * 0.55, h), secondaryPaint);

    // ── Primary CATA transit route ────────────────────────────────────────
    final routePath = Path()
      ..moveTo(w * 0.15, h * 0.85)
      ..cubicTo(w * 0.25, h * 0.65, w * 0.35, h * 0.60, w * 0.45, h * 0.48)
      ..cubicTo(w * 0.55, h * 0.36, w * 0.60, h * 0.28, w * 0.72, h * 0.20)
      ..lineTo(w * 0.85, h * 0.12);

    // Glow/halo layer
    canvas.drawPath(
      routePath,
      Paint()
        ..color = KwellaColors.cataTransitGreen.withValues(alpha: 0.15)
        ..strokeWidth = 18
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    // Main route line
    canvas.drawPath(
      routePath,
      Paint()
        ..color = KwellaColors.cataTransitGreen.withValues(alpha: 0.85)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // ── Route stop markers ────────────────────────────────────────────────
    final stopPositions = <Offset>[
      Offset(w * 0.15, h * 0.85),
      Offset(w * 0.45, h * 0.48),
      Offset(w * 0.72, h * 0.20),
      Offset(w * 0.85, h * 0.12),
    ];
    final stopRingPaint = Paint()
      ..color = KwellaColors.cataTransitGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final stopFillPaint = Paint()
      ..color = KwellaColors.deepSlate
      ..style = PaintingStyle.fill;

    for (final pos in stopPositions) {
      canvas.drawCircle(pos, 8, stopFillPaint);
      canvas.drawCircle(pos, 8, stopRingPaint);
    }

    // ── Current driver position marker ────────────────────────────────────
    final driverPos = Offset(w * 0.45, h * 0.48);
    canvas.drawCircle(
      driverPos,
      16,
      Paint()..color = KwellaColors.cataTransitGreen.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      driverPos,
      9,
      Paint()..color = KwellaColors.cataTransitGreen,
    );
    canvas.drawCircle(
      driverPos,
      5,
      Paint()..color = KwellaColors.deepSlate,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Pulsing streaming-status dot
// ---------------------------------------------------------------------------
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.3).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: KwellaColors.cataTransitGreen,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Telematics header overlay
// ---------------------------------------------------------------------------
class _TelematicsHeader extends StatelessWidget {
  const _TelematicsHeader();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            // ── Speed badge ───────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: KwellaColors.deepSlateCard.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: KwellaColors.deepSlateBorder, width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.speed_rounded,
                      color: KwellaColors.cataTransitGreen, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '45 km/h',
                    style: TextStyle(
                      color: KwellaColors.textOnDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // ── GPS streaming status pill ──────────────────────────────────
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: KwellaColors.deepSlateCard.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: KwellaColors.deepSlateBorder, width: 1.0),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    _PulsingDot(),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Streaming GPS Deltas to AWS...',
                        style: TextStyle(
                          color: KwellaColors.textOnDarkMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide-to-Confirm button
// ---------------------------------------------------------------------------
class SlideToConfirmButton extends StatefulWidget {
  const SlideToConfirmButton({
    super.key,
    required this.label,
    required this.onConfirmed,
  });

  /// Text label shown inside the track.
  final String label;

  /// Called once when the driver successfully slides to the end.
  final VoidCallback onConfirmed;

  @override
  State<SlideToConfirmButton> createState() => _SlideToConfirmButtonState();
}

class _SlideToConfirmButtonState extends State<SlideToConfirmButton>
    with SingleTickerProviderStateMixin {
  // Width of the circular handle.
  static const double _handleDiameter = 56.0;
  // Horizontal padding inside the track.
  static const double _trackPadding = 6.0;
  // Fraction of track width that counts as "confirmed".
  static const double _confirmThreshold = 0.82;

  double _dragOffset = 0.0; // normalised 0.0 → 1.0
  bool _confirmed = false;

  late final AnimationController _snapCtrl;
  late final Animation<double> _snapAnim;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _snapAnim = CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double trackWidth) {
    if (_confirmed) return;
    final maxOffset = trackWidth - _handleDiameter - _trackPadding * 2;
    setState(() {
      _dragOffset =
          (_dragOffset + details.delta.dx / maxOffset).clamp(0.0, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails _, double trackWidth) {
    if (_confirmed) return;
    if (_dragOffset >= _confirmThreshold) {
      setState(() {
        _dragOffset = 1.0;
        _confirmed = true;
      });
      widget.onConfirmed();
    } else {
      // Snap back
      final startOffset = _dragOffset;
      _snapCtrl.reset();
      _snapAnim.addListener(() {
        if (!mounted) return;
        setState(() {
          _dragOffset = startOffset * (1.0 - _snapAnim.value);
        });
      });
      _snapCtrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          final maxOffset =
              trackWidth - _handleDiameter - _trackPadding * 2;
          final handleLeft = _trackPadding + _dragOffset * maxOffset;

          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // ── Track container ─────────────────────────────────────────
              Container(
                height: 68,
                width: trackWidth,
                decoration: BoxDecoration(
                  color: KwellaColors.deepSlateCard.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(
                    color: _confirmed
                        ? KwellaColors.cataTransitGreen
                        : KwellaColors.deepSlateBorder,
                    width: _confirmed ? 1.5 : 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                // ── Progress fill ──────────────────────────────────────────
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(34),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _dragOffset,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              KwellaColors.cataTransitGreen
                                  .withValues(alpha: 0.18),
                              KwellaColors.cataTransitGreen
                                  .withValues(alpha: 0.06),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Track label ─────────────────────────────────────────────
              Center(
                child: AnimatedOpacity(
                  opacity: _confirmed ? 0.0 : (1.0 - _dragOffset * 1.8).clamp(0.0, 1.0),
                  duration: const Duration(milliseconds: 150),
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: KwellaColors.textOnDarkMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              // ── Confirmed label ─────────────────────────────────────────
              if (_confirmed)
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.check_circle_rounded,
                          color: KwellaColors.cataTransitGreen, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Arrived at Destination',
                        style: TextStyle(
                          color: KwellaColors.cataTransitGreen,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Draggable handle ────────────────────────────────────────
              AnimatedPositioned(
                duration: const Duration(milliseconds: 0),
                left: handleLeft,
                child: GestureDetector(
                  onHorizontalDragUpdate: _confirmed
                      ? null
                      : (d) => _onDragUpdate(d, trackWidth),
                  onHorizontalDragEnd: _confirmed
                      ? null
                      : (d) => _onDragEnd(d, trackWidth),
                  child: Container(
                    width: _handleDiameter,
                    height: _handleDiameter,
                    margin: EdgeInsets.symmetric(vertical: _trackPadding),
                    decoration: BoxDecoration(
                      color: _confirmed
                          ? KwellaColors.successGreen
                          : KwellaColors.cataTransitGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: KwellaColors.cataTransitGreen
                              .withValues(alpha: 0.45),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      _confirmed
                          ? Icons.check_rounded
                          : Icons.chevron_right_rounded,
                      color: KwellaColors.deepSlate,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Driver Home screen – full-screen navigation layout
// ---------------------------------------------------------------------------
class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  bool _arrived = false;

  void _handleArrival() {
    setState(() => _arrived = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KwellaColors.deepSlate,
      // No AppBar – full bleed immersive map layout.
      body: Stack(
        children: [
          // ── Layer 0 : Map background with transit route ─────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: const _TransitRoutePainter(),
              child: const SizedBox.expand(),
            ),
          ),

          // ── Layer 1 : Sign-out button (top-right corner) ─────────────────
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 12),
                child: Material(
                  color: KwellaColors.deepSlateCard.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => ref
                        .read(kwellaAuthNotifierProvider.notifier)
                        .signOut(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.logout_rounded,
                        color: KwellaColors.textOnDarkMuted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Layer 2 : Telematics header ──────────────────────────────────
          const Positioned(
            top: 0,
            left: 0,
            right: 60, // leave room for sign-out button
            child: _TelematicsHeader(),
          ),

          // ── Layer 3 : Arrival status banner ──────────────────────────────
          if (_arrived)
            Positioned(
              left: 16,
              right: 16,
              bottom: 132,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: KwellaColors.successGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: KwellaColors.successGreen.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.place_rounded,
                        color: KwellaColors.successGreen, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Arrived at Destination',
                        style: TextStyle(
                          color: KwellaColors.successGreen,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Layer 4 : Slide-to-Confirm at the bottom ──────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SlideToConfirmButton(
              label: _arrived ? 'Trip Complete' : 'Slide to Confirm Arrival',
              onConfirmed: _arrived ? () {} : _handleArrival,
            ),
          ),
        ],
      ),
    );
  }
}

// Local KwellaTheme stub removed – all tokens are now sourced from
// kwella_core via KwellaColors and KwellaTheme.
