import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/rider_trip_state.dart';

/// Marker id used for the live driver position, shared with tests.
const MarkerId kDriverMarkerId = MarkerId('driver');

/// Marker id used for the ride's pickup point, shared with tests.
const MarkerId kPickupMarkerId = MarkerId('pickup');

/// Marker id used for the ride's dropoff point, shared with tests.
const MarkerId kDropoffMarkerId = MarkerId('dropoff');

/// Polyline id used for the pickup-to-dropoff route, shared with tests.
const PolylineId kRoutePolylineId = PolylineId('route');

/// The real, dark-styled Google Map shared by the booking, tracking, and
/// fare offer screens — replaces the old `_MapGridPainter`/
/// `_TrackingGridPainter` placeholders.
///
/// Shows the rider's live device location via the SDK's built-in
/// "my location" indicator, and, when [driverLocation] is supplied, a
/// marker sourced from the live trip state (already lat/lng, just never
/// rendered on a real map before).
///
/// When [pickupLocation] and [dropoffLocation] are both supplied, the map
/// switches to route mode: it renders a marker at each point, draws a
/// polyline between them (using [routePoints] when available, otherwise a
/// straight line), and frames the camera to fit both — instead of centering
/// on the device's live location.
class KwellaMapView extends StatefulWidget {
  const KwellaMapView({
    super.key,
    this.driverLocation,
    this.pickupLocation,
    this.dropoffLocation,
    this.routePoints,
    this.nearbyDrivers,
  });

  final DriverLocation? driverLocation;
  final LatLng? pickupLocation;
  final LatLng? dropoffLocation;
  final List<LatLng>? routePoints;

  /// Idle nearby drivers broadcast by the mock orchestrator's
  /// `nearbyDriverUpdate` frames, keyed by driverId — rendered as their own
  /// marker set, distinct from [driverLocation] (the rider's matched
  /// driver).
  final Map<String, DriverLocation>? nearbyDrivers;

  /// Cape Town CBD — used only until the device location fix resolves.
  static const LatLng fallbackCenter = LatLng(-33.9249, 18.4241);

  static const String stylePath = 'assets/map_styles/dark_map_style.json';

  /// Cloud-based map style ID enabling Advanced Markers, injected via
  /// `--dart-define=GOOGLE_MAP_ID=<id>`. When unset, [GoogleMap] falls back
  /// to legacy marker rendering.
  static const String _mapId = String.fromEnvironment('GOOGLE_MAP_ID');

  /// Computes a camera position centered on [points]' bounding box, with a
  /// zoom level that scales down as the box widens — so both ends of a
  /// route stay on-screen regardless of trip length. Pure and synchronous,
  /// so callers (including tests) don't need a live map controller.
  static CameraPosition cameraForBounds(List<LatLng> points) {
    assert(points.isNotEmpty);
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final LatLng point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final LatLng center = LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );
    final double span = [
      (maxLat - minLat).abs(),
      (maxLng - minLng).abs(),
    ].reduce((a, b) => a > b ? a : b);

    double zoom;
    if (span <= 0.003) {
      zoom = 16;
    } else if (span <= 0.01) {
      zoom = 15;
    } else if (span <= 0.03) {
      zoom = 14;
    } else if (span <= 0.06) {
      zoom = 13;
    } else if (span <= 0.15) {
      zoom = 12;
    } else if (span <= 0.3) {
      zoom = 11;
    } else {
      zoom = 10;
    }

    return CameraPosition(target: center, zoom: zoom);
  }

  static LatLngBounds _boundsFor(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final LatLng point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  @override
  State<KwellaMapView> createState() => _KwellaMapViewState();
}

class _KwellaMapViewState extends State<KwellaMapView> {
  String? _mapStyle;
  bool _myLocationEnabled = false;
  GoogleMapController? _controller;
  LatLng? _pendingCameraTarget;

  /// True once both a pickup and dropoff point are supplied — the map then
  /// frames the route instead of chasing the device's live location.
  bool get _isRouteMode =>
      widget.pickupLocation != null && widget.dropoffLocation != null;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _requestLocationPermission();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString(KwellaMapView.stylePath);
    if (mounted) {
      setState(() => _mapStyle = style);
    }
  }

  Future<void> _requestLocationPermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    final bool granted = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    if (mounted) {
      setState(() => _myLocationEnabled = granted);
    }
    // Route mode already frames the camera on the pickup/dropoff bounds —
    // recentering on the device's live location here would immediately
    // fight that framing.
    if (granted && !_isRouteMode) {
      await _centerOnCurrentLocation();
    }
  }

  /// Recenters the camera on the device's live/mocked GPS fix — without
  /// this, the "my location" dot only ever renders wherever it falls
  /// relative to [KwellaMapView.fallbackCenter], which is off-screen for
  /// any fix outside Cape Town CBD (e.g. an emulator test location).
  Future<void> _centerOnCurrentLocation() async {
    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final LatLng target = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      final GoogleMapController? controller = _controller;
      if (controller != null) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(target, 16),
        );
      } else {
        _pendingCameraTarget = target;
      }
    } catch (_) {
      // Location unavailable — keep the fallback camera position.
    }
  }

  Set<Marker> get _markers {
    final Set<Marker> markers = {};

    final DriverLocation? driver = widget.driverLocation;
    if (driver != null) {
      markers.add(
        Marker(
          markerId: kDriverMarkerId,
          position: LatLng(driver.latitude, driver.longitude),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    final LatLng? pickup = widget.pickupLocation;
    if (pickup != null) {
      markers.add(
        Marker(
          markerId: kPickupMarkerId,
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    final LatLng? dropoff = widget.dropoffLocation;
    if (dropoff != null) {
      markers.add(
        Marker(
          markerId: kDropoffMarkerId,
          position: dropoff,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    final Map<String, DriverLocation>? nearby = widget.nearbyDrivers;
    if (nearby != null) {
      for (final entry in nearby.entries) {
        markers.add(
          Marker(
            markerId: MarkerId('nearby_${entry.key}'),
            position: LatLng(entry.value.latitude, entry.value.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
            anchor: const Offset(0.5, 0.5),
          ),
        );
      }
    }

    return markers;
  }

  Set<Polyline> get _polylines {
    if (!_isRouteMode) return const <Polyline>{};
    final List<LatLng>? route = widget.routePoints;
    final List<LatLng> points = (route != null && route.isNotEmpty)
        ? route
        : [widget.pickupLocation!, widget.dropoffLocation!];
    return <Polyline>{
      Polyline(
        polylineId: kRoutePolylineId,
        points: points,
        color: const Color(0xFFDFFF00),
        width: 4,
      ),
    };
  }

  CameraPosition get _initialCamera {
    if (_isRouteMode) {
      return KwellaMapView.cameraForBounds([
        widget.pickupLocation!,
        widget.dropoffLocation!,
        ...?widget.routePoints,
      ]);
    }
    return const CameraPosition(
      target: KwellaMapView.fallbackCenter,
      zoom: 15,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          key: const Key('kwella_map_view'),
          initialCameraPosition: _initialCamera,
          mapId: KwellaMapView._mapId.isEmpty ? null : KwellaMapView._mapId,
          style: _mapStyle,
          myLocationEnabled: _myLocationEnabled,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          markers: _markers,
          polylines: _polylines,
          onMapCreated: (controller) {
            _controller = controller;
            if (_isRouteMode) {
              controller.animateCamera(
                CameraUpdate.newLatLngBounds(
                  KwellaMapView._boundsFor([
                    widget.pickupLocation!,
                    widget.dropoffLocation!,
                    ...?widget.routePoints,
                  ]),
                  48,
                ),
              );
              return;
            }
            final LatLng? target = _pendingCameraTarget;
            if (target != null) {
              _pendingCameraTarget = null;
              controller.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
            }
          },
        ),
        if (!_isRouteMode)
          Positioned(
            right: 16,
            bottom: 16,
            child: GestureDetector(
              key: const Key('recenter_button'),
              onTap: _centerOnCurrentLocation,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.navigation_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
