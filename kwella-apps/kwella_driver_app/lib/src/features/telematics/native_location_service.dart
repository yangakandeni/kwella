import 'package:geolocator/geolocator.dart';

/// Thin wrapper around the `geolocator` plugin's lifecycle steps.
///
/// Centralises the service/permission checks required before subscribing to
/// the native position stream, per the Anti-Over-Engineering Mandate: no
/// custom GPS math lives here, only the native SDK's own lifecycle contract.
class NativeLocationService {
  const NativeLocationService();

  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
  );

  /// Verifies location services are enabled and that this app holds runtime
  /// location permission, requesting it if necessary.
  ///
  /// Returns `true` once tracking is safe to start, `false` if services are
  /// disabled or permission was denied (including permanently).
  Future<bool> ensurePermissionGranted() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// The live native position stream, configured for high-accuracy tracking
  /// with a 5-metre distance filter between updates.
  Stream<Position> positionStream() {
    return Geolocator.getPositionStream(locationSettings: _locationSettings);
  }
}
