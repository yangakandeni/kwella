import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../location/presentation/controllers/kwella_telemetry_controller.dart';
import '../../../location/services/directions_service.dart';
import '../../../location/services/kwella_location_service.dart';
import '../../models/active_ride_offer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kwella Driver – Trip Navigation Screen
// Entered after the driver confirms pickup (see bidding_marketplace_screen's
// driverArrived() -> push '/driver/navigation'), so this screen's whole job
// is driving the passenger from the pickup point to the dropoff — a real
// map with the driver's live position, the dropoff marker, and the driving
// route between them, plus the passenger info card and slide-to-confirm
// arrival control.
// ─────────────────────────────────────────────────────────────────────────────

class TripNavigationScreen extends ConsumerStatefulWidget {
  const TripNavigationScreen({
    super.key,
    this.locationService,
    this.directionsService,
  });

  final KwellaLocationService? locationService;
  final DirectionsService? directionsService;

  /// Cape Town CBD — used only until the first live position fix resolves.
  static const LatLng fallbackCenter = LatLng(-33.9249, 18.4241);

  @override
  ConsumerState<TripNavigationScreen> createState() =>
      _TripNavigationScreenState();
}

class _TripNavigationScreenState extends ConsumerState<TripNavigationScreen> {
  double _slideProgress = 0.0; // 0–1 for slide-to-confirm
  bool _arrived = false;

  late final KwellaLocationService _locationService;
  late final DirectionsService _directionsService;
  StreamSubscription<Position>? _positionSubscription;
  Position? _driverPosition;
  RouteResult? _route;
  bool _routeRequested = false;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _locationService = widget.locationService ?? KwellaLocationService.instance;
    _directionsService = widget.directionsService ?? DirectionsService();
    ref
        .read(telemetryControllerProvider.notifier)
        .startTrip(driverId: 'USR#drv-12345');
    _startPositionTracking();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  /// Requests location permission before subscribing to the position
  /// stream — never starts a listener ahead of a granted permission.
  Future<void> _startPositionTracking() async {
    final bool granted = await _locationService.requestLocationPermissions();
    if (!granted || !mounted) return;
    _positionSubscription =
        _locationService.startPositionStream().listen(_onPosition);
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    setState(() => _driverPosition = position);
    final GoogleMapController? controller = _mapController;
    if (controller != null) {
      controller.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    }
    _maybeLoadRoute(ref.read(telemetryControllerProvider).activeOffer);
  }

  /// Fetches the driving route from the driver's current position to the
  /// dropoff once both are known. Only ever fetched once per screen visit —
  /// mirrors [RideFareOfferScreen]'s one-shot `_loadRoute` in kwella_rider
  /// rather than refetching on every GPS tick.
  Future<void> _maybeLoadRoute(ActiveRideOffer? offer) async {
    if (_routeRequested) return;
    final Position? driverPos = _driverPosition;
    final double? dropoffLat = offer?.dropoffLat;
    final double? dropoffLng = offer?.dropoffLng;
    if (driverPos == null || dropoffLat == null || dropoffLng == null) return;

    _routeRequested = true;
    final RouteResult? route = await _directionsService.getRoute(
      origin: LatLng(driverPos.latitude, driverPos.longitude),
      destination: LatLng(dropoffLat, dropoffLng),
    );
    if (!mounted || route == null) return;
    setState(() => _route = route);
  }

  /// Animates the camera to fit both the driver's position and the dropoff
  /// point — the "Navigate" button's real behavior, replacing the previous
  /// no-op.
  void _onNavigatePressed() {
    final Position? driverPos = _driverPosition;
    final ActiveRideOffer? offer = ref.read(telemetryControllerProvider).activeOffer;
    final double? dropoffLat = offer?.dropoffLat;
    final double? dropoffLng = offer?.dropoffLng;
    final GoogleMapController? controller = _mapController;
    if (controller == null || driverPos == null) return;

    final LatLng driverLatLng = LatLng(driverPos.latitude, driverPos.longitude);
    if (dropoffLat == null || dropoffLng == null) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(driverLatLng, 16));
      return;
    }

    final LatLng dropoffLatLng = LatLng(dropoffLat, dropoffLng);
    final double minLat = driverLatLng.latitude < dropoffLatLng.latitude
        ? driverLatLng.latitude
        : dropoffLatLng.latitude;
    final double maxLat = driverLatLng.latitude > dropoffLatLng.latitude
        ? driverLatLng.latitude
        : dropoffLatLng.latitude;
    final double minLng = driverLatLng.longitude < dropoffLatLng.longitude
        ? driverLatLng.longitude
        : dropoffLatLng.longitude;
    final double maxLng = driverLatLng.longitude > dropoffLatLng.longitude
        ? driverLatLng.longitude
        : dropoffLatLng.longitude;

    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        48,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TelemetryState telemetryState = ref.watch(telemetryControllerProvider);
    final ActiveRideOffer? offer = telemetryState.activeOffer;

    // Fetch the route as soon as the active offer's dropoff coordinates
    // arrive, in case they land after the driver's first position fix.
    ref.listen<TelemetryState>(telemetryControllerProvider, (previous, next) {
      if (next.activeOffer != previous?.activeOffer) {
        // Deferred to a post-frame callback rather than called directly:
        // kicking off unawaited async work straight from a ref.listen
        // callback invoked during build() ties its continuation to this
        // build in a way that doesn't integrate cleanly with the widget
        // lifecycle. A post-frame callback runs once this frame is
        // actually done, which is the well-defined, supported place to
        // trigger side effects from a rebuild.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeLoadRoute(next.activeOffer);
        });
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // ── Real map: driver position, dropoff marker, driving route ──
          Positioned.fill(
            child: GoogleMap(
              key: const Key('trip_navigation_map'),
              initialCameraPosition: const CameraPosition(
                target: TripNavigationScreen.fallbackCenter,
                zoom: 15,
              ),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              markers: _buildMarkers(offer),
              polylines: _buildPolylines(),
              onMapCreated: (controller) {
                _mapController = controller;
                final Position? driverPos = _driverPosition;
                if (driverPos != null) {
                  controller.animateCamera(
                    CameraUpdate.newLatLngZoom(
                      LatLng(driverPos.latitude, driverPos.longitude),
                      16,
                    ),
                  );
                }
              },
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
                          children: [
                            const Text(
                              'Passenger',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Outfit',
                              ),
                            ),
                            Text(
                              '📍 ${offer?.pickupLocation ?? 'Pickup location unavailable'}',
                              key: const Key('pickup_location_label'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
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
                          key: const Key('navigate_button'),
                          icon: const Icon(Icons.navigation_rounded,
                              color: Color(0xFF1A1A00), size: 22),
                          onPressed: _onNavigatePressed,
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
                      // Route status + remaining distance
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
                            child: Text(
                              'En route to dropoff',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Outfit',
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF242424),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _remainingDistanceLabel(),
                              key: const Key('remaining_distance_label'),
                              style: const TextStyle(
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

  Set<Marker> _buildMarkers(ActiveRideOffer? offer) {
    final Set<Marker> markers = {};

    final Position? driverPos = _driverPosition;
    if (driverPos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(driverPos.latitude, driverPos.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueYellow,
          ),
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    final double? dropoffLat = offer?.dropoffLat;
    final double? dropoffLng = offer?.dropoffLng;
    if (dropoffLat != null && dropoffLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(dropoffLat, dropoffLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    final RouteResult? route = _route;
    if (route == null || route.points.isEmpty) return const <Polyline>{};
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: route.points,
        color: const Color(0xFFDFFF00),
        width: 4,
      ),
    };
  }

  String _remainingDistanceLabel() {
    final int? distanceMeters = _route?.distanceMeters;
    if (distanceMeters == null) return '—';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  Widget _buildSlider() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        const thumbSize = 56.0;
        final trackWidth = maxWidth;

        return GestureDetector(
          key: const Key('slide_to_confirm'),
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
    final pendingBidAmount =
        ref.read(telemetryControllerProvider).pendingBidAmount ?? 0.0;
    notifier.confirmArrival(
      driverId: 'USR#drv-12345',
      finalBidAmount: pendingBidAmount,
    );
    Navigator.of(context).pushNamed('/driver/post-trip');
  }
}
