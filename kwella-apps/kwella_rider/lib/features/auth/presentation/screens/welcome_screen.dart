import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Rider – Welcome Screen
// Dark-mode-first onboarding gateway with animated wordmark and dual CTAs.
// ─────────────────────────────────────────────────────────────────────────────

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isSmallScreen = constraints.maxHeight < 680;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: isSmallScreen ? 24 : 60),
                        FadeTransition(
                          opacity: _fade,
                          child: SlideTransition(
                            position: _slide,
                            child: Column(
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDFFF00),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x50DFFF00),
                                        blurRadius: 32,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.directions_car_rounded,
                                      color: Color(0xFF1A1A00),
                                      size: 38,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  'kwella',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 48,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'Outfit',
                                    letterSpacing: -2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FadeTransition(
                          opacity: _fade,
                          child: const Text(
                            'Your ride,\nyour price.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFFA0A0A0),
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ),
                        const Spacer(),
                        FadeTransition(
                          opacity: _fade,
                          child: SizedBox(
                            height: isSmallScreen ? 120 : 200,
                            child: CustomPaint(painter: _CitylinePainter()),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 20 : 40),
                        FadeTransition(
                          opacity: _fade,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 54,
                                child: ElevatedButton(
                                  key: const Key('welcome_get_started'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFDFFF00),
                                    foregroundColor: const Color(0xFF1A1A00),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: () =>
                                      Navigator.pushNamed(context, '/auth/phone'),
                                  child: const Text(
                                    'Get Started',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: 54,
                                child: OutlinedButton(
                                  key: const Key('welcome_sign_in'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFDFFF00),
                                    side: const BorderSide(
                                      color: Color(0x4DDFFF00),
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () =>
                                      Navigator.pushNamed(context, '/auth/phone'),
                                  child: const Text(
                                    'Sign In',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'By continuing you agree to our Terms & Privacy Policy.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF606060),
                                  fontSize: 12,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CitylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final buildingPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..style = PaintingStyle.fill;
    final rimePaint = Paint()
      ..color = const Color(0x30DFFF00)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.85, size.width, size.height * 0.15),
      buildingPaint,
    );

    final buildings = [
      [0.03, 0.45, 0.10, 0.40],
      [0.14, 0.30, 0.09, 0.55],
      [0.24, 0.50, 0.07, 0.35],
      [0.32, 0.25, 0.10, 0.60],
      [0.43, 0.38, 0.08, 0.47],
      [0.52, 0.20, 0.12, 0.65],
      [0.65, 0.40, 0.09, 0.45],
      [0.75, 0.33, 0.08, 0.52],
      [0.84, 0.55, 0.07, 0.30],
      [0.92, 0.42, 0.07, 0.43],
    ];

    for (final b in buildings) {
      final x = b[0] * size.width;
      final y = b[1] * size.height;
      final w = b[2] * size.width;
      final h = b[3] * size.height;
      canvas.drawRRect(
        RRect.fromLTRBR(x, y, x + w, y + h, const Radius.circular(2)),
        buildingPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(x + w * 0.2, y + h * 0.1, w * 0.25, h * 0.08),
        rimePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
