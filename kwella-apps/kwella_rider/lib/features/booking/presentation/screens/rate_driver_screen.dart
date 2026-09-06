import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/kwella_rider_controller.dart';
import '../controllers/rider_trip_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RateDriverScreen
// Shown after a trip completes (RiderTripStatus.completed). Lets the rider
// leave a 1-5 star rating for the driver, or skip without rating.
// ─────────────────────────────────────────────────────────────────────────────

class RateDriverScreen extends ConsumerStatefulWidget {
  const RateDriverScreen({super.key, this.controller});

  final KwellaRiderController? controller;

  @override
  ConsumerState<RateDriverScreen> createState() => _RateDriverScreenState();
}

class _RateDriverScreenState extends ConsumerState<RateDriverScreen> {
  int _starRating = 0;

  void _returnHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _submit(KwellaRiderController controller) {
    if (_starRating <= 0) return;
    controller.submitRating(_starRating);
    _returnHome();
  }

  @override
  Widget build(BuildContext context) {
    final KwellaRiderController controller =
        widget.controller ?? ref.read(kwellaRiderControllerProvider);
    final RiderTripState state = widget.controller != null
        ? controller.state
        : ref.watch(riderTripStateProvider).asData?.value ?? controller.state;
    final String? driverName = state.driverName;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFFDFFF00),
                size: 56,
              ),
              const SizedBox(height: 20),
              Text(
                driverName != null && driverName.isNotEmpty
                    ? 'Rate your driver, $driverName'
                    : 'Rate your driver',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your trip has ended. How was your ride?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 14,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final int starValue = index + 1;
                  final bool filled = starValue <= _starRating;
                  return GestureDetector(
                    key: Key('star_$starValue'),
                    onTap: () => setState(() => _starRating = starValue),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: const Color(0xFFDFFF00),
                        size: 40,
                      ),
                    ),
                  );
                }),
              ),
              const Spacer(),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  key: const Key('submit_rating_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDFFF00),
                    foregroundColor: const Color(0xFF1A1A00),
                    disabledBackgroundColor: const Color(0xFF2C2C2C),
                    disabledForegroundColor: const Color(0xFF606060),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed:
                      _starRating > 0 ? () => _submit(controller) : null,
                  child: const Text(
                    'Submit Rating',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('skip_rating_button'),
                onPressed: _returnHome,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFA0A0A0),
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Outfit',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
