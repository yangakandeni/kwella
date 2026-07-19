import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Driver – Post Trip Screen
// Fare earned badge, rating row, submit CTA.
// ─────────────────────────────────────────────────────────────────────────────

class PostTripScreen extends StatefulWidget {
  const PostTripScreen({
    super.key,
    this.fareEarned = 120.0,
    this.passengerName = 'Lethabo M.',
    this.tripId,
  });

  final double fareEarned;
  final String passengerName;
  final String? tripId;

  @override
  State<PostTripScreen> createState() => _PostTripScreenState();
}

class _PostTripScreenState extends State<PostTripScreen>
    with SingleTickerProviderStateMixin {
  int _starRating = 0;
  late final AnimationController _fareCtrl;
  late final Animation<double> _fareAnim;

  @override
  void initState() {
    super.initState();
    _fareCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fareAnim = CurvedAnimation(parent: _fareCtrl, curve: Curves.elasticOut);
    _fareCtrl.forward();
  }

  @override
  void dispose() {
    _fareCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    // In production: send submitRating WebSocket action
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              // ── Animated fare badge ────────────────────────────────────
              ScaleTransition(
                scale: _fareAnim,
                child: Column(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A00),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFFDFFF00), width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x50DFFF00),
                            blurRadius: 40,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Center(
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(children: [
                            const TextSpan(
                              text: 'R',
                              style: TextStyle(
                                color: Color(0xFFDFFF00),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Outfit',
                              ),
                            ),
                            TextSpan(
                              text: widget.fareEarned
                                  .toStringAsFixed(0),
                              style: const TextStyle(
                                color: Color(0xFFDFFF00),
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'Outfit',
                                height: 1.0,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Trip Complete!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You earned R${widget.fareEarned.toStringAsFixed(2)}\nfrom ${widget.passengerName}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFA0A0A0),
                        fontSize: 15,
                        fontFamily: 'Outfit',
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // ── Divider ────────────────────────────────────────────────
              Container(
                height: 1,
                color: const Color(0xFF2C2C2C),
              ),
              const SizedBox(height: 32),
              // ── Star rating ────────────────────────────────────────────
              const Text(
                'Rate your passenger',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your rating helps keep the platform safe for everyone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF606060),
                  fontSize: 13,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < _starRating;
                  return GestureDetector(
                    onTap: () => setState(() => _starRating = i + 1),
                    child: AnimatedScale(
                      scale: filled ? 1.2 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          filled ? Icons.star_rounded : Icons.star_border_rounded,
                          color: filled
                              ? const Color(0xFFDFFF00)
                              : const Color(0xFF2C2C2C),
                          size: 42,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const Spacer(),
              // ── Submit CTA ─────────────────────────────────────────────
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  key: const Key('submit_rating_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDFFF00),
                    foregroundColor: const Color(0xFF1A1A00),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _submit,
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _submit,
                child: const Text(
                  'Skip rating',
                  style: TextStyle(
                    color: Color(0xFF606060),
                    fontSize: 14,
                    fontFamily: 'Outfit',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
