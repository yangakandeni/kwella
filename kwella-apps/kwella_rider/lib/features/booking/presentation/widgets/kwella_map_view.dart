import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
    return GoogleMap(
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
      onMapCreated: (controller) => _controller = controller,
    );
  }
}
