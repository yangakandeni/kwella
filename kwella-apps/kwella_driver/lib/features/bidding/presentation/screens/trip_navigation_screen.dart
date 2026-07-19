import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../location/presentation/controllers/kwella_telemetry_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Driver – Trip Navigation Screen
// Full-screen map placeholder, passenger info card, step-by-step nav, slide CTA.
// ─────────────────────────────────────────────────────────────────────────────

class TripNavigationScreen extends ConsumerStatefulWidget {
  const TripNavigationScreen({super.key});

  @override
  ConsumerState<TripNavigationScreen> createState() =>
      _TripNavigationScreenState();
}

class _TripNavigationScreenState extends ConsumerState<TripNavigationScreen>
    with SingleTickerProviderStateMixin {
  double _slideProgress = 0.0; // 0–1 for slide-to-confirm
  bool _arrived = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // ── Dark map placeholder ─────────────────────────────────────
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0D1117),
              child: CustomPaint(
                painter: _NavGridPainter(),
                size: Size.infinite,
              ),
            ),
          ),
          // ── Animated route line ──────────────────────────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: _RoutePainter(_slideProgress),
              size: Size.infinite,
            ),
          ),
          // ── Top passenger card ───────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2C)),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black45,
                          blurRadius: 20,
                          offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFFDFFF00), width: 2),
                          color: const Color(0xFF242424),
                        ),
                        child: const Icon(Icons.person_rounded,
                            color: Color(0xFFA0A0A0), size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Lethabo M.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Outfit',
                              ),
                            ),
                            Text(
                              '📍 23 Buitenkant St, Cape Town CBD',
                              style: TextStyle(
                                color: Color(0xFFA0A0A0),
                                fontSize: 13,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Navigate CTA
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFDFFF00),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.navigation_rounded,
                              color: Color(0xFF1A1A00), size: 22),
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ── Bottom navigation card ────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black45,
                      blurRadius: 24,
                      offset: Offset(0, -4)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Turn-by-turn text
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A00),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0x50DFFF00)),
                            ),
                            child: const Icon(Icons.turn_right_rounded,
                                color: Color(0xFFDFFF00), size: 22),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Turn right onto De Waal Drive',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                                Text(
                                  'in 200 m',
                                  style: TextStyle(
                                    color: Color(0xFFA0A0A0),
                                    fontSize: 13,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF242424),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '1.4 km',
                              style: TextStyle(
                                color: Color(0xFFDFFF00),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Slide-to-confirm
                      if (!_arrived)
                        _buildSlider()
                      else
                        _buildArrivedBadge(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        const thumbSize = 56.0;
        final trackWidth = maxWidth;

        return GestureDetector(
          onHorizontalDragUpdate: (d) {
            setState(() {
              _slideProgress = (_slideProgress +
                      d.delta.dx / (trackWidth - thumbSize))
                  .clamp(0.0, 1.0);
            });
            if (_slideProgress >= 0.95) {
              _onArrived();
            }
          },
          onHorizontalDragEnd: (_) {
            if (_slideProgress < 0.95) {
              setState(() => _slideProgress = 0.0);
            }
          },
          child: Stack(
            children: [
              // Track
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A00),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0x50DFFF00)),
                ),
                child: const Center(
                  child: Text(
                    'Slide to confirm arrival →',
                    style: TextStyle(
                      color: Color(0xFF606060),
                      fontSize: 14,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ),
              ),
              // Fill
              Container(
                height: 56,
                width: thumbSize +
                    _slideProgress * (trackWidth - thumbSize),
                decoration: BoxDecoration(
                  color: const Color(0x30DFFF00),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              // Thumb
              Positioned(
                left: _slideProgress * (trackWidth - thumbSize),
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDFFF00),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Color(0xFF1A1A00), size: 26),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArrivedBadge() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x2000C853),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x5000C853)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded,
              color: Color(0xFF00C853), size: 22),
          SizedBox(width: 8),
          Text(
            'Arrived — awaiting passenger',
            style: TextStyle(
              color: Color(0xFF00C853),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: 'Outfit',
            ),
          ),
        ],
      ),
    );
  }

  void _onArrived() {
    setState(() {
      _arrived = true;
      _slideProgress = 1.0;
    });
    final notifier = ref.read(telemetryControllerProvider.notifier);
    notifier.confirmArrival(
      driverId: 'USR#drv-12345',
      tripId: 'trip-arrived-123',
    );
  }
}

// ── Map grid painter ──────────────────────────────────────────────────────────

class _NavGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF1A1E24)
      ..strokeWidth = 1.0;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Route line painter ────────────────────────────────────────────────────────

class _RoutePainter extends CustomPainter {
  const _RoutePainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFDFFF00)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.5, size.height * 0.85)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.6,
        size.width * 0.5,
        size.height * 0.3,
      );

    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(drawn, paint);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.progress != progress;
}
