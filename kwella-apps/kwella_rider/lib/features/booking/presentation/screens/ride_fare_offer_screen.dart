import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kwella_core/kwella_core.dart';

import '../../../location/utils/location_display_formatter.dart';
import '../controllers/kwella_rider_controller.dart';
import '../controllers/rider_trip_state.dart';
import '../widgets/kwella_map_view.dart';
import 'active_search_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Rider – Ride Offer Screen
// Final confirmation step: shows the pickup → dropoff route on the map, the
// ride details carried over from the booking flow, and lets the rider set
// their fare offer against the system-recommended fare before finding
// drivers.
// ─────────────────────────────────────────────────────────────────────────────

class RideFareOfferScreen extends ConsumerStatefulWidget {
  const RideFareOfferScreen({
    super.key,
    this.controller,
    this.directionsService,
  });

  final KwellaRiderController? controller;
  final DirectionsService? directionsService;

  @override
  ConsumerState<RideFareOfferScreen> createState() =>
      _RideFareOfferScreenState();
}

class _RideFareOfferScreenState extends ConsumerState<RideFareOfferScreen> {
  static const double _step = 5.0;
  static const double _minFare = 30.0;
  static const double _maxFare = 500.0;

  // Simple distance-based estimate — kept in sync with the fare the app
  // sends as `suggested_base_fare` on requestTrip so the rider isn't shown
  // one number and asked to bid against another.
  static const double _baseFare = 25.0;
  static const double _perKmRate = 6.5;
  static const double _fallbackRecommendedFare = 60.0;

  late final DirectionsService _directionsService;

  double _offeredFare = _fallbackRecommendedFare;
  bool _offerTouchedByUser = false;
  bool _autoAccept = false;
  List<LatLng>? _routePoints;
  int? _routeDistanceMeters;

  @override
  void initState() {
    super.initState();
    _directionsService = widget.directionsService ?? DirectionsService();
    final KwellaRiderController controller =
        widget.controller ?? ref.read(kwellaRiderControllerProvider);
    _loadRoute(controller.state);
  }

  Future<void> _loadRoute(RiderTripState state) async {
    final double? pickupLat = state.pickupLat;
    final double? pickupLng = state.pickupLng;
    final double? dropoffLat = state.dropoffLat;
    final double? dropoffLng = state.dropoffLng;
    if (pickupLat == null ||
        pickupLng == null ||
        dropoffLat == null ||
        dropoffLng == null) {
      return;
    }

    final RouteResult? route = await _directionsService.getRoute(
      origin: LatLng(pickupLat, pickupLng),
      destination: LatLng(dropoffLat, dropoffLng),
    );
    if (!mounted || route == null) return;

    setState(() {
      _routePoints = route.points;
      _routeDistanceMeters = route.distanceMeters;
      if (!_offerTouchedByUser) {
        _offeredFare = _recommendedFare;
      }
    });
  }

  double get _recommendedFare {
    final int? distanceMeters = _routeDistanceMeters;
    if (distanceMeters == null) return _fallbackRecommendedFare;
    final double km = distanceMeters / 1000;
    final double raw = _baseFare + km * _perKmRate;
    return ((raw / _step).round()) * _step;
  }

  /// Handles a rider dragging the pickup/dropoff pin to a new spot: updates
  /// the controller state (reverse-geocoding the dropped point) then reloads
  /// the route/fare from the new coordinates — mirroring what [initState]
  /// does once up front, since [_loadRoute] isn't otherwise re-triggered by
  /// controller state changes.
  Future<void> _onPinDragged(
    KwellaRiderController controller, {
    required bool isPickup,
    required LatLng position,
  }) async {
    if (isPickup) {
      await controller.updatePickupFromMapPin(
        position.latitude,
        position.longitude,
      );
    } else {
      await controller.updateDropoffFromMapPin(
        position.latitude,
        position.longitude,
      );
    }
    if (!mounted) return;
    await _loadRoute(controller.state);
  }

  void _adjust(double delta) {
    setState(() {
      _offerTouchedByUser = true;
      _offeredFare = (_offeredFare + delta).clamp(_minFare, _maxFare);
    });
  }

  void _findDrivers(KwellaRiderController controller) {
    controller.requestTrip(
      offeredFare: _offeredFare,
      autoAccept: _autoAccept,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ActiveSearchScreen(
          controller: widget.controller,
          directionsService: _directionsService,
        ),
      ),
    );
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
    final double mapHeight = MediaQuery.of(context).size.height * 0.4;
    final LatLng? pickup = (state.pickupLat != null && state.pickupLng != null)
        ? LatLng(state.pickupLat!, state.pickupLng!)
        : null;
    final LatLng? dropoff =
        (state.dropoffLat != null && state.dropoffLng != null)
            ? LatLng(state.dropoffLat!, state.dropoffLng!)
            : null;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Map section ─────────────────────────────────────────────
          SizedBox(
            height: mapHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: KwellaMapView(
                    pickupLocation: pickup,
                    dropoffLocation: dropoff,
                    routePoints: _routePoints,
                    onPickupDragEnd: (LatLng position) => _onPinDragged(
                      controller,
                      isPickup: true,
                      position: position,
                    ),
                    onDropoffDragEnd: (LatLng position) => _onPinDragged(
                      controller,
                      isPickup: false,
                      position: position,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: SafeArea(
                    child: GestureDetector(
                      key: const Key('back_button'),
                      onTap: () => Navigator.pop(context),
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
              ],
            ),
          ),
          // ── Ride details card ───────────────────────────────────────
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildRouteSummary(state),
                    const SizedBox(height: 18),
                    const Divider(color: Color(0xFF2C2C2C), height: 1),
                    const SizedBox(height: 16),
                    _buildPassengerRow(state),
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFF2C2C2C), height: 1),
                    const SizedBox(height: 18),
                    _buildFareSection(),
                    const SizedBox(height: 8),
                    _buildFareComparisonHint(),
                    const SizedBox(height: 18),
                    _buildAutoAcceptRow(),
                    const SizedBox(height: 20),
                    _buildFindDriversButton(controller, state),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSummary(RiderTripState state) {
    final String pickupLabel = state.pickupLocation.isNotEmpty
        ? formatLocationLabel(state.pickupLocation)
        : 'Pickup point not set';
    final LocationLabelParts destinationParts = splitLocationLabel(
      state.dropoffLocation.isNotEmpty
          ? formatLocationLabel(state.dropoffLocation)
          : 'Destination not set',
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFDFFF00),
              ),
            ),
            Container(
              width: 2,
              height: 30,
              color: const Color(0xFF3C3C3C),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFF5370),
              ),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pickupLabel,
                key: const Key('pickup_location_label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 20),
              Text(
                destinationParts.primary,
                key: const Key('destination_primary_label'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Outfit',
                ),
              ),
              if (destinationParts.secondary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    destinationParts.secondary,
                    key: const Key('destination_secondary_label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFA0A0A0),
                      fontSize: 12,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPassengerRow(RiderTripState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Passengers',
          style: TextStyle(
            color: Color(0xFFA0A0A0),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'Outfit',
          ),
        ),
        Row(
          children: [
            const Icon(Icons.person_rounded, color: Color(0xFFDFFF00), size: 18),
            const SizedBox(width: 6),
            Text(
              '${state.passengerCount}',
              key: const Key('passenger_count_label'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'Outfit',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFareSection() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Offer',
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
                      key: const Key('decrease_fare_button'),
                      icon: Icons.remove_rounded,
                      onTap: _offeredFare > _minFare
                          ? () => _adjust(-_step)
                          : null,
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'R${_offeredFare.toStringAsFixed(0)}',
                          key: const Key('your_offer_value'),
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
                      key: const Key('increase_fare_button'),
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
          const SizedBox(width: 16),
          const VerticalDivider(color: Color(0xFF2C2C2C), width: 1),
          const SizedBox(width: 16),
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recommended',
                  style: TextStyle(
                    color: Color(0xFFA0A0A0),
                    fontSize: 13,
                    fontFamily: 'Outfit',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'R${_recommendedFare.toStringAsFixed(0)}',
                  key: const Key('recommended_fare_value'),
                  style: const TextStyle(
                    color: Color(0xFFDFFF00),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Outfit',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFareComparisonHint() {
    final double recommended = _recommendedFare;
    final double delta = _offeredFare - recommended;
    final double tolerance = recommended * 0.05;

    String message;
    Color color;
    if (delta.abs() <= tolerance) {
      message = 'Matches the recommended fare';
      color = const Color(0xFFDFFF00);
    } else if (delta > 0) {
      message = 'Above recommended — drivers may accept faster';
      color = const Color(0xFF69FF47);
    } else {
      message = 'Below recommended — may take longer to match';
      color = const Color(0xFFFF5370);
    }

    return Text(
      message,
      key: const Key('fare_comparison_hint'),
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        fontFamily: 'Outfit',
      ),
    );
  }

  Widget _buildAutoAcceptRow() {
    return Row(
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
          key: const Key('auto_accept_toggle'),
          value: _autoAccept,
          onChanged: (v) => setState(() => _autoAccept = v),
          activeThumbColor: const Color(0xFF1A1A00),
          activeTrackColor: const Color(0xFFDFFF00),
          inactiveThumbColor: const Color(0xFFA0A0A0),
          inactiveTrackColor: const Color(0xFF242424),
        ),
      ],
    );
  }

  Widget _buildFindDriversButton(
    KwellaRiderController controller,
    RiderTripState state,
  ) {
    final bool searching = state.status == RiderTripStatus.searching;
    return SizedBox(
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
        onPressed: searching ? null : () => _findDrivers(controller),
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
