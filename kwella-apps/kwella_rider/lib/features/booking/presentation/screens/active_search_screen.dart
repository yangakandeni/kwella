import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../location/services/directions_service.dart';
import '../controllers/kwella_rider_controller.dart';
import '../controllers/rider_trip_state.dart';
import '../widgets/driver_bid_card.dart';
import '../widgets/kwella_map_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Rider – Active Search Screen
// Dedicated searching/bidding view shown after "Find Drivers" is tapped on
// RideFareOfferScreen: a full-bleed map (fed nearby idle-driver markers) with
// a bottom sheet that switches on RiderTripStatus — fare +/- + raise-fare +
// auto-accept toggle while searching with no bids yet, the single incoming
// bid (Decline/Accept) once bidding opens, and an auto-navigate to the
// tracking screen once a driver has been accepted.
// ─────────────────────────────────────────────────────────────────────────────

class ActiveSearchScreen extends ConsumerStatefulWidget {
  const ActiveSearchScreen({
    super.key,
    this.controller,
    this.directionsService,
  });

  final KwellaRiderController? controller;
  final DirectionsService? directionsService;

  @override
  ConsumerState<ActiveSearchScreen> createState() =>
      _ActiveSearchScreenState();
}

class _ActiveSearchScreenState extends ConsumerState<ActiveSearchScreen> {
  static const double _step = 5.0;
  static const double _minFare = 30.0;
  static const double _maxFare = 500.0;

  // Null until the rider taps +/-, at which point the fare +/- row starts
  // tracking its own value rather than following `state.offeredFare` — the
  // same "touched" pattern RideFareOfferScreen uses for its own offer field.
  double? _userAdjustedFare;
  bool _autoAcceptDisplay = false;
  bool _autoAcceptDisplaySeeded = false;
  bool _navigatedToTracking = false;

  double _displayedFare(RiderTripState state) =>
      _userAdjustedFare ?? (state.offeredFare ?? 0);

  void _adjustLocalFare(RiderTripState state, double delta) {
    setState(() {
      _userAdjustedFare =
          (_displayedFare(state) + delta).clamp(_minFare, _maxFare);
    });
  }

  void _cancelAndPop(KwellaRiderController controller) {
    controller.cancelSearch();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller != null) {
      final controller = widget.controller!;
      return StreamBuilder<RiderTripState>(
        stream: controller.stateStream,
        initialData: controller.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? controller.state;
          return _buildScaffold(context, controller, state);
        },
      );
    }

    final controller = ref.watch(kwellaRiderControllerProvider);
    final stateAsync = ref.watch(riderTripStateProvider);
    final RiderTripState state = stateAsync.asData?.value ?? controller.state;
    return _buildScaffold(context, controller, state);
  }

  Widget _buildScaffold(
    BuildContext context,
    KwellaRiderController controller,
    RiderTripState state,
  ) {
    // The auto-accept toggle's real enable-at-request-time decision already
    // happened on the fare-offer screen; this display-only toggle just seeds
    // once from that decision so it isn't stuck showing "off" for a request
    // that opted in.
    if (!_autoAcceptDisplaySeeded) {
      _autoAcceptDisplaySeeded = true;
      _autoAcceptDisplay = state.autoAcceptEnabled;
    }

    if (state.status == RiderTripStatus.accepted && !_navigatedToTracking) {
      _navigatedToTracking = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/rider/tracking');
      });
    }

    // Driven purely by whether a bid is currently on hand, not `status` —
    // declining the only open bid clears `bidMetrics` without moving
    // `status` back off `biddingOpen`, and this sheet must fall back to the
    // fare +/- view in that case rather than rendering an empty bid card.
    final bool showBidding = state.bidMetrics.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          Positioned.fill(
            child: KwellaMapView(
              driverLocation: state.currentDriverLocation,
              nearbyDrivers: state.nearbyDrivers,
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: GestureDetector(
                key: const Key('back_button'),
                onTap: () => _cancelAndPop(controller),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: showBidding
                      ? _buildBiddingSheet(controller, state)
                      : _buildSearchingSheet(controller, state),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchingSheet(
    KwellaRiderController controller,
    RiderTripState state,
  ) {
    final double displayedFare = _displayedFare(state);
    final bool canRaise = displayedFare > (state.offeredFare ?? 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFDFFF00),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Finding drivers…',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'Your offer',
          style: TextStyle(
            color: Color(0xFFA0A0A0),
            fontSize: 13,
            fontFamily: 'Outfit',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _StepButton(
              key: const Key('active_search_decrease_fare_button'),
              icon: Icons.remove_rounded,
              onTap: displayedFare > _minFare
                  ? () => _adjustLocalFare(state, -_step)
                  : null,
            ),
            Expanded(
              child: Center(
                child: Text(
                  'R${displayedFare.toStringAsFixed(0)}',
                  key: const Key('active_search_offer_value'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Outfit',
                  ),
                ),
              ),
            ),
            _StepButton(
              key: const Key('active_search_increase_fare_button'),
              icon: Icons.add_rounded,
              onTap: displayedFare < _maxFare
                  ? () => _adjustLocalFare(state, _step)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            key: const Key('raise_fare_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDFFF00),
              foregroundColor: const Color(0xFF1A1A00),
              disabledBackgroundColor: const Color(0xFF242424),
              disabledForegroundColor: const Color(0xFF606060),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            onPressed: canRaise ? () => controller.raiseFare(displayedFare) : null,
            child: const Text(
              'Raise fare',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFamily: 'Outfit',
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFFDFFF00), size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Auto-accept first matching bid',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Outfit',
                ),
              ),
            ),
            Switch(
              key: const Key('active_search_auto_accept_toggle'),
              value: _autoAcceptDisplay,
              onChanged: (v) => setState(() => _autoAcceptDisplay = v),
              activeThumbColor: const Color(0xFF1A1A00),
              activeTrackColor: const Color(0xFFDFFF00),
              inactiveThumbColor: const Color(0xFFA0A0A0),
              inactiveTrackColor: const Color(0xFF242424),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBiddingSheet(
    KwellaRiderController controller,
    RiderTripState state,
  ) {
    final Map<String, dynamic> bid = state.bidMetrics.first;
    final String driverId = bid['driverId'] as String? ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // DriverBidCard relies on a bounded height (its Column ends in a
        // Spacer) — the existing bid carousel in rider_booking_screen.dart
        // gives it one via a fixed-height SizedBox; this sheet does the
        // same rather than letting it inherit this Column's shrink-wrapped
        // (unbounded) height.
        SizedBox(
          height: 260,
          child: Center(
            child: DriverBidCard(
              driverId: driverId,
              driverName: bid['driverName'] as String? ?? 'Unknown',
              driverRating: bid['rating'] != null ? '${bid['rating']}' : '—',
              vehicleDescription:
                  '${bid['vehicleColor'] ?? 'White'} ${bid['vehicleModel'] ?? 'Suzuki Ertiga'}',
              licensePlate: bid['licensePlate'] as String? ?? 'CAA 123-456',
              cataSticker: bid['cataSticker'] as String? ?? 'M02356',
              fareLabel: bid['fare'] ?? bid['bidAmount'] ?? 0,
              etaLabel: bid['etaMinutes'] != null
                  ? '${bid['etaMinutes']} min away'
                  : null,
              onAccept: () => controller.selectBid(driverId),
              onDecline: () => controller.declineBid(driverId),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextButton(
          key: const Key('cancel_request_button'),
          onPressed: () {
            controller.cancelSearch();
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/rider/home', (route) => false);
          },
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF5370)),
          child: const Text(
            'Cancel request',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFamily: 'Outfit',
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step button ───────────────────────────────────────────────────────────────

class _StepButton extends StatelessWidget {
  const _StepButton({super.key, required this.icon, required this.onTap});

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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF242424),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2C2C2C)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
