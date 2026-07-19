import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../location/presentation/controllers/kwella_telemetry_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Driver – Earnings Dashboard Screen
// Weekly total, 7-day bar chart (CustomPainter), stats chips.
// ─────────────────────────────────────────────────────────────────────────────

class EarningsDashboardScreen extends ConsumerWidget {
  const EarningsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(telemetryControllerProvider);
    final today = telemetry.dailyEarningsTotal;

    // Demo weekly data — replaces today's slot with live value
    final List<double> weeklyEarnings = [
      210.0, 340.0, 185.0, 460.0, 290.0, 520.0,
      today > 0 ? today : 150.0,
    ];
    final double weeklyTotal = weeklyEarnings.fold(0.0, (a, b) => a + b);
    const List<String> dayLabels = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ];

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
          'Earnings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Outfit',
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded,
                color: Color(0xFFA0A0A0), size: 22),
            onPressed: () {},
          ),
        ],
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // ── Weekly total card ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A00), Color(0xFF141400)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2C2C00)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'THIS WEEK',
                  style: TextStyle(
                    color: Color(0xFF808000),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'R',
                        style: TextStyle(
                          color: Color(0xFFDFFF00),
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      weeklyTotal.toStringAsFixed(0),
                      style: const TextStyle(
                        color: Color(0xFFDFFF00),
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Outfit',
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '↑ 12% vs last week',
                  style: TextStyle(
                    color: Color(0xFF69FF47),
                    fontSize: 13,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // ── 7-day bar chart ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2C2C2C)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daily breakdown',
                  style: TextStyle(
                    color: Color(0xFFA0A0A0),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 140,
                  child: CustomPaint(
                    painter: _BarChartPainter(
                      values: weeklyEarnings,
                      labels: dayLabels,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // ── Stats chips row ───────────────────────────────────────────
          Row(
            children: [
              _StatCard(
                icon: Icons.access_time_rounded,
                label: 'Online',
                value: '6h 42m',
                color: const Color(0xFFDFFF00),
              ),
              const SizedBox(width: 12),
              _StatCard(
                icon: Icons.directions_car_rounded,
                label: 'Trips',
                value: '14',
                color: const Color(0xFF69FF47),
              ),
              const SizedBox(width: 12),
              _StatCard(
                icon: Icons.star_rounded,
                label: 'Rating',
                value: '4.87',
                color: const Color(0xFFFFAB40),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── Today's earnings ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2C2C2C)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TODAY',
                  style: TextStyle(
                    color: Color(0xFF606060),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'R ${today.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0x20DFFF00),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        today > 0 ? 'Active' : 'No trips yet',
                        style: const TextStyle(
                          color: Color(0xFFDFFF00),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Bar chart CustomPainter ───────────────────────────────────────────────────

class _BarChartPainter extends CustomPainter {
  const _BarChartPainter({required this.values, required this.labels});
  final List<double> values;
  final List<String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = values.reduce(math.max);
    const labelHeight = 20.0;
    final chartHeight = size.height - labelHeight;
    final barWidth = size.width / (values.length * 1.6);
    final gap = size.width / values.length;

    final barPaint = Paint()
      ..color = const Color(0xFF242424)
      ..style = PaintingStyle.fill;
    final activePaint = Paint()
      ..shader = LinearGradient(
        colors: const [Color(0xFFDFFF00), Color(0xFFCCFF00)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, 1, size.height))
      ..style = PaintingStyle.fill;
    const labelStyle = TextStyle(
      color: Color(0xFF606060),
      fontSize: 11,
      fontFamily: 'Outfit',
    );

    for (int i = 0; i < values.length; i++) {
      final x = gap * i + (gap - barWidth) / 2;
      final barH = (values[i] / maxValue) * chartHeight * 0.9;
      final y = chartHeight - barH;
      final rRect = RRect.fromLTRBR(
          x, y, x + barWidth, chartHeight, const Radius.circular(4));
      // Highlight today (last bar) with Electric Lime
      canvas.drawRRect(rRect, i == values.length - 1 ? activePaint : barPaint);

      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas, Offset(x + (barWidth - tp.width) / 2, chartHeight + 4));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Stats card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2C2C2C)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                fontFamily: 'Outfit',
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF606060),
                fontSize: 11,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
