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
                                const SizedBox(height: 30),
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
                        FadeTransition(
                          opacity: _fade,
                          child: const Text(
                            'Let\'s GO.',
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
                        SizedBox(height: isSmallScreen ? 20 : 40),
                        FadeTransition(
                          opacity: _fade,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 54,
                                child: ElevatedButton(
                                  key: const Key('welcome_continue'),
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
                                    'Continue',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
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
