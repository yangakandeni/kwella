import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../controllers/rider_trip_state.dart';

/// Marker id used for the live driver position, shared with tests.
const MarkerId kDriverMarkerId = MarkerId('driver');

/// The real, dark-styled Google Map shared by the booking and tracking
/// screens — replaces the old `_MapGridPainter`/`_TrackingGridPainter`
/// placeholders.
///
/// Shows the rider's live device location via the SDK's built-in
/// "my location" indicator, and, when [driverLocation] is supplied, a
/// marker sourced from the live trip state (already lat/lng, just never
/// rendered on a real map before).
class KwellaMapView extends StatefulWidget {
  const KwellaMapView({super.key, this.driverLocation});

  final DriverLocation? driverLocation;

  /// Cape Town CBD — used only until the device location fix resolves.
  static const LatLng fallbackCenter = LatLng(-33.9249, 18.4241);

  static const String stylePath = 'assets/map_styles/dark_map_style.json';

  @override
  State<KwellaMapView> createState() => _KwellaMapViewState();
}

class _KwellaMapViewState extends State<KwellaMapView> {
  String? _mapStyle;
  bool _myLocationEnabled = false;
  GoogleMapController? _controller;
  LatLng? _pendingCameraTarget;

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
    if (granted) {
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
    final DriverLocation? location = widget.driverLocation;
    if (location == null) return const <Marker>{};
    return <Marker>{
      Marker(
        markerId: kDriverMarkerId,
        position: LatLng(location.latitude, location.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        anchor: const Offset(0.5, 0.5),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          key: const Key('kwella_map_view'),
          initialCameraPosition: const CameraPosition(
            target: KwellaMapView.fallbackCenter,
            zoom: 15,
          ),
          style: _mapStyle,
          myLocationEnabled: _myLocationEnabled,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          markers: _markers,
          onMapCreated: (controller) {
            _controller = controller;
            final LatLng? target = _pendingCameraTarget;
            if (target != null) {
              _pendingCameraTarget = null;
              controller.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
            }
          },
        ),
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
