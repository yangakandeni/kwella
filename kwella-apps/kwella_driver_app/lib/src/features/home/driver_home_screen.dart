import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kwella_core/kwella_core.dart';

import '../bidding/driver_bidding_provider.dart';
import '../telematics/native_location_service.dart';
import '../telematics/telematics_buffer.dart';

// ---------------------------------------------------------------------------
// Driver Home screen  –  Phase 3 high-fidelity layout
// ---------------------------------------------------------------------------

/// Live Google Map showing the driver's own position (via the native "my
/// location" blue dot), a marker for the active passenger pickup, and a
/// polyline tracing the route between them.
///
/// Watches [telematicsBufferProvider] for the driver's current hardware fix
/// and [driverBiddingProvider] for the active offer's pickup coordinates.
class _DriverMap extends ConsumerStatefulWidget {
  const _DriverMap();

  @override
  ConsumerState<_DriverMap> createState() => _DriverMapState();
}

class _DriverMapState extends ConsumerState<_DriverMap> {
  // Fallback centre used until the device's first GPS fix arrives.
  static const LatLng _fallbackCenter = LatLng(-33.9249, 18.4241);
  static const String _pickupMarkerId = 'pickup';
  static const String _routePolylineId = 'driver_to_pickup';

  GoogleMapController? _mapController;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final telematics = ref.watch(telematicsBufferProvider);
    final bidding = ref.watch(driverBiddingProvider);

    ref.listen<TelematicsState>(telematicsBufferProvider, (previous, next) {
      final controller = _mapController;
      if (controller == null) return;
      controller.animateCamera(
        CameraUpdate.newLatLng(LatLng(next.latitude, next.longitude)),
      );
    });

    final hasFix = telematics.latitude != 0.0 || telematics.longitude != 0.0;
    final driverPosition = hasFix
        ? LatLng(telematics.latitude, telematics.longitude)
        : _fallbackCenter;

    final pickupLatitude = bidding.pickupLatitude;
    final pickupLongitude = bidding.pickupLongitude;
    final pickupPosition = pickupLatitude != null && pickupLongitude != null
        ? LatLng(pickupLatitude, pickupLongitude)
        : null;

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: driverPosition,
        zoom: 15,
      ),
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      markers: {
        if (pickupPosition != null)
          Marker(
            markerId: const MarkerId(_pickupMarkerId),
            position: pickupPosition,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
            infoWindow: const InfoWindow(title: 'Passenger Pickup'),
          ),
      },
      polylines: {
        if (pickupPosition != null && hasFix)
          Polyline(
            polylineId: const PolylineId(_routePolylineId),
            points: [driverPosition, pickupPosition],
            color: Colors.blue,
            width: 5,
          ),
      },
      onMapCreated: (controller) => _mapController = controller,
    );
  }
}

// ---------------------------------------------------------------------------
// Pulsing streaming-status dot
// ---------------------------------------------------------------------------
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.3).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: child,
        ),
      ),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: KwellaColors.cataTransitGreen,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Telematics header overlay  –  reactive to TelematicsBufferManager
// ---------------------------------------------------------------------------
class _TelematicsHeader extends ConsumerWidget {
  const _TelematicsHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telem = ref.watch(telematicsBufferProvider);

    final speedLabel = '${telem.speed.toStringAsFixed(0)} km/h';
    final coordLabel = telem.latitude == 0.0 && telem.longitude == 0.0
        ? 'Acquiring GPS...'
        : '${telem.latitude.toStringAsFixed(4)}, '
            '${telem.longitude.toStringAsFixed(4)}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            // ── Speed badge ───────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: KwellaColors.deepSlateCard.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: KwellaColors.deepSlateBorder, width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.speed_rounded,
                      color: KwellaColors.cataTransitGreen, size: 20),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: Text(
                      speedLabel,
                      key: ValueKey(speedLabel),
                      style: const TextStyle(
                        color: KwellaColors.textOnDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // ── GPS streaming status pill ──────────────────────────────────
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: KwellaColors.deepSlateCard.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: KwellaColors.deepSlateBorder, width: 1.0),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const _PulsingDot(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: Text(
                          coordLabel,
                          key: ValueKey(coordLabel),
                          style: const TextStyle(
                            color: KwellaColors.textOnDarkMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide-to-Confirm button
// ---------------------------------------------------------------------------
class SlideToConfirmButton extends StatefulWidget {
  const SlideToConfirmButton({
    super.key,
    required this.label,
    required this.onConfirmed,
  });

  /// Text label shown inside the track.
  final String label;

  /// Called once when the driver successfully slides to the end.
  final VoidCallback onConfirmed;

  @override
  State<SlideToConfirmButton> createState() => _SlideToConfirmButtonState();
}

class _SlideToConfirmButtonState extends State<SlideToConfirmButton>
    with SingleTickerProviderStateMixin {
  // Width of the circular handle.
  static const double _handleDiameter = 56.0;
  // Horizontal padding inside the track.
  static const double _trackPadding = 6.0;
  // Fraction of track width that counts as "confirmed".
  static const double _confirmThreshold = 0.82;

  double _dragOffset = 0.0; // normalised 0.0 → 1.0
  bool _confirmed = false;

  late final AnimationController _snapCtrl;
  late final Animation<double> _snapAnim;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _snapAnim = CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double trackWidth) {
    if (_confirmed) return;
    final maxOffset = trackWidth - _handleDiameter - _trackPadding * 2;
    setState(() {
      _dragOffset =
          (_dragOffset + details.delta.dx / maxOffset).clamp(0.0, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails _, double trackWidth) {
    if (_confirmed) return;
    if (_dragOffset >= _confirmThreshold) {
      setState(() {
        _dragOffset = 1.0;
        _confirmed = true;
      });
      widget.onConfirmed();
    } else {
      // Snap back
      final startOffset = _dragOffset;
      _snapCtrl.reset();
      _snapAnim.addListener(() {
        if (!mounted) return;
        setState(() {
          _dragOffset = startOffset * (1.0 - _snapAnim.value);
        });
      });
      _snapCtrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          final maxOffset =
              trackWidth - _handleDiameter - _trackPadding * 2;
          final handleLeft = _trackPadding + _dragOffset * maxOffset;

          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // ── Track container ─────────────────────────────────────────
              Container(
                height: 68,
                width: trackWidth,
                decoration: BoxDecoration(
                  color: KwellaColors.deepSlateCard.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(
                    color: _confirmed
                        ? KwellaColors.cataTransitGreen
                        : KwellaColors.deepSlateBorder,
                    width: _confirmed ? 1.5 : 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x44000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                // ── Progress fill ──────────────────────────────────────────
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(34),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _dragOffset,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              KwellaColors.cataTransitGreen
                                  .withValues(alpha: 0.18),
                              KwellaColors.cataTransitGreen
                                  .withValues(alpha: 0.06),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Track label ─────────────────────────────────────────────
              Center(
                child: AnimatedOpacity(
                  opacity: _confirmed ? 0.0 : (1.0 - _dragOffset * 1.8).clamp(0.0, 1.0),
                  duration: const Duration(milliseconds: 150),
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: KwellaColors.textOnDarkMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              // ── Confirmed label ─────────────────────────────────────────
              if (_confirmed)
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.check_circle_rounded,
                          color: KwellaColors.cataTransitGreen, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Arrived at Destination',
                        style: TextStyle(
                          color: KwellaColors.cataTransitGreen,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Draggable handle ────────────────────────────────────────
              AnimatedPositioned(
                duration: const Duration(milliseconds: 0),
                left: handleLeft,
                child: GestureDetector(
                  onHorizontalDragUpdate: _confirmed
                      ? null
                      : (d) => _onDragUpdate(d, trackWidth),
                  onHorizontalDragEnd: _confirmed
                      ? null
                      : (d) => _onDragEnd(d, trackWidth),
                  child: Container(
                    width: _handleDiameter,
                    height: _handleDiameter,
                    margin: EdgeInsets.symmetric(vertical: _trackPadding),
                    decoration: BoxDecoration(
                      color: _confirmed
                          ? KwellaColors.successGreen
                          : KwellaColors.cataTransitGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: KwellaColors.cataTransitGreen
                              .withValues(alpha: 0.45),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      _confirmed
                          ? Icons.check_rounded
                          : Icons.chevron_right_rounded,
                      color: KwellaColors.deepSlate,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Driver Home screen – full-screen navigation layout
// ---------------------------------------------------------------------------
class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  bool _arrived = false;

  final _locationService = const NativeLocationService();

  /// Subscription to the native position stream, forwarding every sample
  /// straight into the telematics buffer for batched WebSocket flushing.
  StreamSubscription<Position>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  Future<void> _startLocationTracking() async {
    final granted = await _locationService.ensurePermissionGranted();
    if (!granted || !mounted) return;

    _positionSubscription = _locationService.positionStream().listen(
      (position) {
        ref.read(telematicsBufferProvider.notifier).pushCoordinate(
              position.latitude,
              position.longitude,
              position.speed,
            );
      },
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _handleArrival() {
    setState(() => _arrived = true);
  }

  @override
  Widget build(BuildContext context) {
    final biddingState = ref.watch(driverBiddingProvider);

    // If we just received an offer, show the bottom sheet over the map.
    // Ensure we only show it once by checking if a route is active or something,
    // but for now we'll just rely on the UI overlay. We can just render it as a positioned widget instead of a modal to match the Phase 3 requirement "display a floating incoming request bottom sheet over the map".

    return Scaffold(
      backgroundColor: KwellaColors.deepSlate,
      // No AppBar – full bleed immersive map layout.
      body: Stack(
        children: [
          // ── Layer 0 : Live Google Map with pickup route ──────────────────
          const Positioned.fill(
            child: _DriverMap(),
          ),

          // ── Layer 1 : Sign-out button (top-right corner) ─────────────────
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 12),
                child: Material(
                  color: KwellaColors.deepSlateCard.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => ref
                        .read(kwellaAuthNotifierProvider.notifier)
                        .signOut(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.logout_rounded,
                        color: KwellaColors.textOnDarkMuted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Layer 2 : Telematics header ──────────────────────────────────
          const Positioned(
            top: 0,
            left: 0,
            right: 60, // leave room for sign-out button
            child: _TelematicsHeader(),
          ),

          // ── Layer 3 : Arrival status banner ──────────────────────────────
          if (_arrived)
            Positioned(
              left: 16,
              right: 16,
              bottom: 132,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: KwellaColors.successGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: KwellaColors.successGreen.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.place_rounded,
                        color: KwellaColors.successGreen, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Arrived at Destination',
                        style: TextStyle(
                          color: KwellaColors.successGreen,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Layer 4 : Bottom UI Area ──────────────────────────────────────
          if (biddingState.status == DriverJobStatus.offerReceived || biddingState.status == DriverJobStatus.bidSubmitted)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: _buildFloatingRequestSheet(biddingState),
            )
          else
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SlideToConfirmButton(
                label: _arrived ? 'Trip Complete' : 'Slide to Confirm Arrival',
                onConfirmed: _arrived ? () {} : _handleArrival,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFloatingRequestSheet(DriverBiddingState state) {
    final isSubmitted = state.status == DriverJobStatus.bidSubmitted;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: BoxDecoration(
        color: KwellaColors.deepSlateCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: KwellaColors.deepSlateBorder),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, 10),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isSubmitted ? 'Bid Submitted' : 'Incoming Ride Request',
            style: const TextStyle(
              color: KwellaColors.textOnDark,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Rider', style: TextStyle(color: KwellaColors.textOnDarkMuted)),
              Text(state.riderName ?? 'Unknown', style: const TextStyle(color: KwellaColors.textOnDark, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Destination', style: TextStyle(color: KwellaColors.textOnDarkMuted)),
              Text(state.destination ?? 'Unknown', style: const TextStyle(color: KwellaColors.textOnDark, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Est. Payout', style: TextStyle(color: KwellaColors.textOnDarkMuted)),
              Text('\$${state.estimatedPayout?.toStringAsFixed(2) ?? '0.00'}', style: const TextStyle(color: KwellaColors.cataTransitGreen, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 24),
          if (isSubmitted)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: KwellaColors.cataTransitGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: KwellaColors.cataTransitGreen.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, color: KwellaColors.cataTransitGreen),
                  SizedBox(width: 8),
                  Text('Waiting for Rider...', style: TextStyle(color: KwellaColors.cataTransitGreen, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          else
            SizedBox(
              height: 68,
              child: SlideToConfirmButton(
                label: 'Slide to Bid \$${state.estimatedPayout?.toStringAsFixed(2) ?? '0.00'}',
                onConfirmed: () {
                  ref.read(driverBiddingProvider.notifier).submitBid(state.estimatedPayout ?? 0.0);
                },
              ),
            ),
        ],
      ),
    );
  }
}
