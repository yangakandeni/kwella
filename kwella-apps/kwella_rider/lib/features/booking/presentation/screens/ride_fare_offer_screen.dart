import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/kwella_rider_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Rider – Fare Offer Screen
// Rider sets offered fare (R format), toggles auto-accept, then finds drivers.
// ─────────────────────────────────────────────────────────────────────────────

class RideFareOfferScreen extends ConsumerStatefulWidget {
  const RideFareOfferScreen({super.key});

  @override
  ConsumerState<RideFareOfferScreen> createState() =>
      _RideFareOfferScreenState();
}

class _RideFareOfferScreenState extends ConsumerState<RideFareOfferScreen> {
  double _offeredFare = 80.0;
  bool _autoAccept = false;
  static const double _step = 5.0;
  static const double _minFare = 30.0;
  static const double _maxFare = 500.0;

  void _adjust(double delta) {
    setState(() {
      _offeredFare = (_offeredFare + delta).clamp(_minFare, _maxFare);
    });
  }

  void _findDrivers() {
    final controller = ref.read(kwellaRiderControllerProvider);
    controller.requestTrip();
    Navigator.pop(context); // Return to booking screen (searching state)
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
        title: const Text(
          'Set Your Fare',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Outfit',
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              // ── Fare display card ───────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Your offered fare',
                      style: TextStyle(
                        color: Color(0xFFA0A0A0),
                        fontSize: 14,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Large fare display
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'R',
                            style: TextStyle(
                              color: Color(0xFFDFFF00),
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _offeredFare.toStringAsFixed(0),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Outfit',
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    // +/- stepper
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StepButton(
                          icon: Icons.remove_rounded,
                          onTap: _offeredFare > _minFare
                              ? () => _adjust(-_step)
                              : null,
                        ),
                        const SizedBox(width: 40),
                        const Text(
                          'R5 steps',
                          style: TextStyle(
                            color: Color(0xFF606060),
                            fontSize: 13,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(width: 40),
                        _StepButton(
                          icon: Icons.add_rounded,
                          onTap: _offeredFare < _maxFare
                              ? () => _adjust(_step)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // ── Auto-accept toggle ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded,
                        color: Color(0xFFDFFF00), size: 22),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto-accept first bid',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          Text(
                            'Instantly accept the first driver who matches.',
                            style: TextStyle(
                              color: Color(0xFFA0A0A0),
                              fontSize: 12,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      key: const Key('auto_accept_toggle'),
                      value: _autoAccept,
                      onChanged: (v) => setState(() => _autoAccept = v),
                      activeColor: const Color(0xFF1A1A00),
                      activeTrackColor: const Color(0xFFDFFF00),
                      inactiveThumbColor: const Color(0xFFA0A0A0),
                      inactiveTrackColor: const Color(0xFF242424),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // ── Hint text ───────────────────────────────────────────────
              const Text(
                'Drivers will see your offer and can bid. You choose who takes your ride.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF606060),
                  fontSize: 13,
                  fontFamily: 'Outfit',
                  height: 1.5,
                ),
              ),
              const Spacer(),
              // ── Find Drivers CTA ─────────────────────────────────────────
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  key: const Key('find_drivers_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDFFF00),
                    foregroundColor: const Color(0xFF1A1A00),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _findDrivers,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.search_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Find Drivers',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ],
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

// ── Step button ───────────────────────────────────────────────────────────────

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap != null ? 1.0 : 0.3,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2C2C2C)),
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}
