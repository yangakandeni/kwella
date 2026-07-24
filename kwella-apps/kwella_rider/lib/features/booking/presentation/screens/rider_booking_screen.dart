import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../location/services/places_autocomplete_service.dart';
import '../../../location/utils/location_display_formatter.dart';
import '../controllers/kwella_rider_controller.dart';
import '../controllers/rider_trip_state.dart';
import '../models/previous_destination.dart';
import '../widgets/destination_editor_panel.dart';
import '../widgets/driver_bid_card.dart';
import '../widgets/kwella_map_view.dart';
import '../widgets/location_input_field.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RiderBookingScreen — v2 Electric Lime Dark Mode
// Preserves full RiderTripStatus state machine & all Riverpod wiring.
// ─────────────────────────────────────────────────────────────────────────────

// Service category options shown in the horizontal chip row.
enum _ServiceCategory { ride }

extension _ServiceCategoryLabel on _ServiceCategory {
  String get label {
    switch (this) {
      case _ServiceCategory.ride:
        return 'GO';
      // case _ServiceCategory.xl:
      //   return 'XL';
      // case _ServiceCategory.freight:
      //   return 'Freight';
      // case _ServiceCategory.courier:
      //   return 'Courier';
      // case _ServiceCategory.cityToCity:
      //   return 'City to City';
    }
  }

  IconData get icon {
    switch (this) {
      case _ServiceCategory.ride:
        return Icons.directions_car_rounded;
      // case _ServiceCategory.xl:
      //   return Icons.airport_shuttle_rounded;
      // case _ServiceCategory.freight:
      //   return Icons.local_shipping_rounded;
      // case _ServiceCategory.courier:
      //   return Icons.pedal_bike_rounded;
      // case _ServiceCategory.cityToCity:
      //   return Icons.route_rounded;
    }
  }
}

class RiderBookingScreen extends ConsumerStatefulWidget {
  const RiderBookingScreen({
    super.key,
    this.controller,
    this.placesService,
    this.previousDestinations = mockPreviousDestinations,
  });

  final KwellaRiderController? controller;
  final PlacesAutocompleteService? placesService;
  final List<PreviousDestination> previousDestinations;

  @override
  ConsumerState<RiderBookingScreen> createState() => _RiderBookingScreenState();
}

class _RiderBookingScreenState extends ConsumerState<RiderBookingScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _panelExpandDuration = Duration(milliseconds: 350);

  // Keeps the collapsed sheet's previous-destinations list compact: about
  // six rows are visible at once, with the rest reachable by scrolling.
  static const double _previousDestinationItemHeight = 40;
  static const int _visiblePreviousDestinations = 5;

  late final TextEditingController _pickupController;
  late final TextEditingController _dropoffController;
  late final AnimationController _sheetAnimCtrl;
  late final Animation<double> _sheetFade;
  late final ScrollController _previousDestinationsScrollController;

  _ServiceCategory _selectedCategory = _ServiceCategory.ride;
  bool _isDestinationPanelExpanded = false;

  @override
  void initState() {
    super.initState();
    _pickupController = TextEditingController();
    _dropoffController = TextEditingController();
    _previousDestinationsScrollController = ScrollController();
    _sheetAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _sheetFade = CurvedAnimation(
      parent: _sheetAnimCtrl,
      curve: Curves.easeOutCubic,
    );
    _sheetAnimCtrl.forward();

    // Default the pickup point to the device's (or emulator's mocked) live
    // location as soon as the screen opens. Only reach for the riverpod
    // controller when one wasn't injected via DI — touching `ref` otherwise
    // requires a ProviderScope ancestor that test/DI callers don't provide.
    final KwellaRiderController controller =
        widget.controller ?? ref.read(kwellaRiderControllerProvider);
    controller.resolvePickupLocation();
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _previousDestinationsScrollController.dispose();
    _sheetAnimCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _expandDestinationPanel() {
    setState(() => _isDestinationPanelExpanded = true);
  }

  void _collapseDestinationPanel() {
    setState(() => _isDestinationPanelExpanded = false);
  }

  Widget _buildLocationStatusBadge(RiderTripState state) {
    final DriverLocation? location = state.currentDriverLocation;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2C2C2C)),
          ),
          child: Text(
            location != null
                ? 'Tracking driver at ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}'
                : _mapStatusLabel(state.status),
            style: const TextStyle(
              color: Color(0xFFA0A0A0),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  String _mapStatusLabel(RiderTripStatus status) {
    switch (status) {
      case RiderTripStatus.idle:
        return 'Set your destination to get started';
      case RiderTripStatus.searching:
        return 'Searching for nearby drivers…';
      case RiderTripStatus.biddingOpen:
        return 'Drivers are placing bids!';
      case RiderTripStatus.accepted:
        return 'Driver en route to you';
      case RiderTripStatus.arrived:
        return 'Driver has arrived';
      case RiderTripStatus.completed:
        return 'Trip completed — great ride!';
    }
  }

  Widget _buildHamburgerButton() {
    return GestureDetector(
      key: const Key('menu_button'),
      onTap: () => Navigator.pushNamed(context, '/rider/profile'),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildPickupPill(RiderTripState state) {
    final bool isLoading =
        state.pickupLocationStatus == PickupLocationStatus.loading;
    final bool hasPickup = state.pickupLocation.isNotEmpty;
    final String displayLabel = isLoading
        ? 'Locating you…'
        : hasPickup
            ? formatLocationLabel(state.pickupLocation)
            : 'Set your pickup point';
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: const Offset(0, -56),
        // Caps the pill's width so a long address wraps/truncates instead of
        // pushing the card wider — the Row/Column below are all
        // MainAxisSize.min and would otherwise hug however wide the label is.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          child: GestureDetector(
            key: const Key('pickup_pill'),
            onTap: _expandDestinationPanel,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Pickup point',
                          style: TextStyle(
                            color: Color(0xFFA0A0A0),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          key: const Key('pickup_pill_label'),
                          displayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (isLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: TickerMode(
                        enabled: false,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFDFFF00),
                        ),
                      ),
                    )
                  else
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFA0A0A0),
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return GestureDetector(
      key: const Key('search_bar'),
      onTap: _expandDestinationPanel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: Color(0xFF808080), size: 20),
            const SizedBox(width: 10),
            const Text(
              'Where to & for how much?',
              style: TextStyle(
                color: Color(0xFF808080),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickDestinations(KwellaRiderController controller) {
    final List<PreviousDestination> destinations = widget.previousDestinations;
    final int visibleCount = destinations.length < _visiblePreviousDestinations
        ? destinations.length
        : _visiblePreviousDestinations;

    return SizedBox(
      height: _previousDestinationItemHeight * visibleCount,
      child: Scrollbar(
        controller: _previousDestinationsScrollController,
        thumbVisibility: true,
        child: ListView.builder(
          key: const Key('previous_destinations_list'),
          controller: _previousDestinationsScrollController,
          physics: const ClampingScrollPhysics(),
          itemExtent: _previousDestinationItemHeight,
          itemCount: destinations.length,
          itemBuilder: (context, index) {
            final PreviousDestination destination = destinations[index];
            return GestureDetector(
              key: Key('previous_destination_${destination.placeId}'),
              onTap: () {
                controller.updateDropoffLocation(
                  destination.description,
                  lat: destination.lat,
                  lng: destination.lng,
                );
                _expandDestinationPanel();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: Color(0xFF808080),
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        destination.shortName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPassengerSelector(
    RiderTripState state,
    KwellaRiderController controller,
  ) {
    return Row(
      children: List.generate(6, (index) {
        final int count = index + 1;
        final bool selected = state.passengerCount == count;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
            child: GestureDetector(
              key: Key('passenger_$count'),
              onTap: () => controller.setPassengerCount(count),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF1A1A00)
                      : const Color(0xFF242424),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFDFFF00)
                        : const Color(0xFF2C2C2C),
                    width: selected ? 1.5 : 1.0,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFFDFFF00)
                          : const Color(0xFFA0A0A0),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildServiceCategoryRow() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _ServiceCategory.values.map((cat) {
          final selected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF1A1A00)
                      : const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFDFFF00)
                        : const Color(0xFF2C2C2C),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      cat.icon,
                      size: 16,
                      color: selected
                          ? const Color(0xFFDFFF00)
                          : const Color(0xFF808080),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      cat.label,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFFDFFF00)
                            : const Color(0xFF808080),
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGeofenceBanner() {
    return Positioned(
      left: 16,
      right: 16,
      top: 60,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutBack,
        builder: (context, v, child) => Transform.translate(
          offset: Offset(0, (1 - v) * -30),
          child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A00),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDFFF00), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40DFFF00),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: Color(0xFFDFFF00), size: 22),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Your driver has arrived! Meet them at the pickup point.',
                  style: TextStyle(
                    color: Color(0xFFDFFF00),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBidCarousel(AsyncValue<List<Map<String, dynamic>>> bidsAsync,
      KwellaRiderController controller) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFDFFF00),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Live bids coming in',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: bidsAsync.when(
              data: (bids) {
                if (bids.isEmpty) {
                  return const Center(
                    child: Text(
                      'Waiting for drivers to bid…',
                      style: TextStyle(color: Color(0xFF606060)),
                    ),
                  );
                }
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: bids.length,
                  itemBuilder: (context, i) {
                    final bid = bids[i];
                    return Padding(
                      padding: EdgeInsets.only(right: i == bids.length - 1 ? 0 : 12),
                      child: DriverBidCard(
                        driverId: bid['driverId'] as String? ?? '',
                        driverName: bid['driverName'] as String? ?? 'Unknown',
                        driverRating: bid['rating'] != null
                            ? '${bid['rating']}'
                            : '—',
                        vehicleDescription:
                            '${bid['vehicleColor'] ?? 'White'} ${bid['vehicleModel'] ?? 'Suzuki Ertiga'}',
                        licensePlate:
                            bid['licensePlate'] as String? ?? 'CAA 123-456',
                        cataSticker:
                            bid['cataSticker'] as String? ?? 'M02356',
                        fareLabel: bid['fare'] ?? bid['bidAmount'] ?? 0,
                        onAccept: () =>
                            controller.selectBid(bid['driverId'] as String? ?? ''),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFFDFFF00),
                  ),
                ),
              ),
              error: (_, __) => const Center(
                child: Text(
                  'Unable to load bids',
                  style: TextStyle(color: Color(0xFF606060)),
                ),
              ),
            ),
          ),
        ],
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
          final bidsAsync = AsyncValue.data(state.availableBids);
          return _buildContent(context, controller, state, bidsAsync);
        },
      );
    }

    final controller = ref.watch(kwellaRiderControllerProvider);
    final stateAsync = ref.watch(riderTripStateProvider);
    final availableBidsAsync = ref.watch(availableBidsProvider);
    final RiderTripState state =
        stateAsync.asData?.value ?? controller.state;
    return _buildContent(context, controller, state, availableBidsAsync);
  }

  Widget _buildContent(
    BuildContext context,
    KwellaRiderController controller,
    RiderTripState state,
    AsyncValue<List<Map<String, dynamic>>> bidsAsync,
  ) {
    // Keep text fields synced with state
    if (_pickupController.text != state.pickupLocation) {
      _pickupController.text = state.pickupLocation;
    }
    if (_dropoffController.text != state.dropoffLocation) {
      _dropoffController.text = state.dropoffLocation;
    }

    final bool showGeofence = state.latestEvent != null &&
        state.latestEvent!['action'] == 'geofenceTrigger' &&
        state.latestEvent!['geofence_status'] == 'ARRIVED';

    final bool showTracking = state.status == RiderTripStatus.accepted ||
        state.status == RiderTripStatus.arrived;

    final bool showBids = state.status == RiderTripStatus.biddingOpen;

    // The collapsed search view only applies while idle — once a trip has
    // been requested, keep the full pickup/dropoff editor visible throughout.
    final bool sheetExpanded = state.status != RiderTripStatus.idle;
    final bool showDestinationPanel =
        !sheetExpanded && _isDestinationPanelExpanded;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // ── Map layer ────────────────────────────────────────────────
          Positioned.fill(
            child: KwellaMapView(driverLocation: state.currentDriverLocation),
          ),
          // ── Live status badge ────────────────────────────────────────
          if (state.status != RiderTripStatus.idle)
            _buildLocationStatusBadge(state),
          // ── Floating pickup point pill ───────────────────────────────
          if (!sheetExpanded && !showDestinationPanel) _buildPickupPill(state),
          // ── Top safe-area overlay (menu) ─────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [_buildHamburgerButton()],
                ),
              ),
            ),
          ),
          // ── Geofence arrival banner ──────────────────────────────────
          if (showGeofence) _buildGeofenceBanner(),
          // ── Live bid carousel ────────────────────────────────────────
          if (showBids)
            _buildBidCarousel(bidsAsync, controller),
          // ── Active tracking hint ─────────────────────────────────────
          if (showTracking)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions_car_rounded,
                        color: Color(0xFFDFFF00), size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Driver is on the way',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(
                        context,
                        '/rider/tracking',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFDFFF00),
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Track →',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // ── Scrim behind the expanded destination panel ──────────────
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !showDestinationPanel,
              child: GestureDetector(
                key: const Key('destination_panel_scrim'),
                onTap: _collapseDestinationPanel,
                child: AnimatedOpacity(
                  opacity: showDestinationPanel ? 1 : 0,
                  duration: _panelExpandDuration,
                  curve: Curves.easeOutCubic,
                  child: Container(color: const Color(0x8C000000)),
                ),
              ),
            ),
          ),
          // ── Bottom booking sheet ─────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FadeTransition(
              opacity: _sheetFade,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E1E1E),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SingleChildScrollView(
                  // The destination panel manages its own fixed height and
                  // internal suggestions scroll — letting this outer view
                  // scroll too fights it for drag gestures and makes the
                  // whole panel shift while browsing results.
                  physics: showDestinationPanel
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  child: AnimatedSize(
                    duration: _panelExpandDuration,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Drag handle
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 4),
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3C3C3C),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                          child: sheetExpanded
                              ? _buildExpandedEditor(context, controller, state)
                              : showDestinationPanel
                                  ? DestinationEditorPanel(
                                      controller: controller,
                                      state: state,
                                      onClose: _collapseDestinationPanel,
                                      placesService: widget.placesService,
                                      previousDestinations:
                                          widget.previousDestinations,
                                    )
                                  : _buildCollapsedSheet(controller),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedSheet(KwellaRiderController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchBar(),
        const SizedBox(height: 8),
        _buildQuickDestinations(controller),
      ],
    );
  }

  Widget _buildExpandedEditor(
    BuildContext context,
    KwellaRiderController controller,
    RiderTripState state,
  ) {
    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Service category chips ─────────────────
                          _buildServiceCategoryRow(),
                          const SizedBox(height: 16),
                          // ── Location inputs ────────────────────────
                          LocationInputField(
                            label: 'Pickup location',
                            controller: _pickupController,
                            fieldKey: const Key('pickup_input'),
                            onChanged: controller.updatePickupLocation,
                            prefixIcon: Icons.trip_origin_rounded,
                            dotColor: const Color(0xFFDFFF00),
                            isLoading: state.pickupLocationStatus ==
                                PickupLocationStatus.loading,
                          ),
                          const SizedBox(height: 10),
                          LocationInputField(
                            label: 'Where to?',
                            controller: _dropoffController,
                            fieldKey: const Key('dropoff_input'),
                            onChanged: controller.updateDropoffLocation,
                            prefixIcon: Icons.location_on_rounded,
                            dotColor: const Color(0xFFFF5370),
                          ),
                          const SizedBox(height: 18),
                          // ── Passenger selector ────────────────────
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Passengers',
                                style: TextStyle(
                                  color: Color(0xFFA0A0A0),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Icon(
                                Icons.person_rounded,
                                color: Color(0xFFDFFF00),
                                size: 18,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildPassengerSelector(state, controller),
                          const SizedBox(height: 20),
                          // ── Request Ride CTA ──────────────────────
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              key: const Key('request_ride_button'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDFFF00),
                                foregroundColor: const Color(0xFF1A1A00),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              onPressed: state.status ==
                                      RiderTripStatus.searching
                                  ? null
                                  : () {
                                      if (widget.controller != null) {
                                        // Test / DI path – skip validation
                                        controller.requestTrip();
                                        return;
                                      }
                                      if (state.pickupLocation.isEmpty ||
                                          state.dropoffLocation.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Add pickup and destination first.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      Navigator.pushNamed(
                                          context, '/rider/fare-offer');
                                    },
                              child: state.status ==
                                      RiderTripStatus.searching
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: TickerMode(
                                            enabled: false,
                                            child: const CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFF1A1A00),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        const Text(
                                          'Finding Drivers…',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Request Ride',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      );
  }
}

