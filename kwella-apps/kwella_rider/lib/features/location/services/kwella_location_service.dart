import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

/// One-shot device location + reverse-geocoding lookups used to default the
/// rider booking screen's pickup point. Mirrors the permission-handshake
/// pattern of `kwella_driver`'s `KwellaLocationService`, but fetches a single
/// fix rather than a continuous stream — the rider screen only needs a
/// starting pickup point, not live telematics.
///
/// On an emulator/simulator with a mocked GPS fix configured, the same
/// `Geolocator` calls below simply return that mocked position — no separate
/// dev/test code path is needed.
class KwellaLocationService {
  static KwellaLocationService _instance = KwellaLocationService._internal();
  factory KwellaLocationService() => _instance;
  KwellaLocationService._internal();

  /// Named constructor for test subclasses only. Do not use in production.
  @visibleForTesting
  KwellaLocationService.forTesting();

  /// Application-wide singleton accessor.
  static KwellaLocationService get instance => _instance;

  /// Replaces the singleton with a fresh instance; intended for unit tests only.
  @visibleForTesting
  static void reset() {
    _instance = KwellaLocationService._internal();
  }

  /// Performs the foreground permission handshake, returning `true` only when
  /// the app has at least [LocationPermission.whileInUse]. Never throws.
  Future<bool> requestLocationPermissions() async {
    final bool serviceEnabled = await checkServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[KwellaLocationService] Location services are disabled.');
      return false;
    }

    LocationPermission permission = await checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await requestPermission();
    }

    final bool granted = permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
    if (!granted) {
      debugPrint(
        '[KwellaLocationService] Permission not granted (got: $permission).',
      );
    }
    return granted;
  }

  /// Fetches a single high-accuracy position fix. Returns `null` (never
  /// throws) if the hardware/OS reports an error.
  Future<Position?> getCurrentPosition() async {
    try {
      return await fetchCurrentPosition();
    } catch (e) {
      debugPrint('[KwellaLocationService] Unable to fetch position: $e');
      return null;
    }
  }

  /// Reverse-geocodes a coordinate pair into a short human-readable label
  /// (e.g. "Long Street, Cape Town"). Returns `null` if no placemark is
  /// found or the lookup fails.
  Future<String?> resolveAddressLabel(
    double latitude,
    double longitude,
  ) async {
    try {
      final List<geocoding.Placemark> placemarks =
          await fetchPlacemarks(latitude, longitude);
      if (placemarks.isEmpty) return null;
      return _formatPlacemark(placemarks.first);
    } catch (e) {
      debugPrint('[KwellaLocationService] Unable to reverse geocode: $e');
      return null;
    }
  }

  String? _formatPlacemark(geocoding.Placemark placemark) {
    final List<String> parts = [
      placemark.street,
      placemark.subLocality,
      placemark.locality,
    ].where((String? part) => part != null && part.trim().isNotEmpty).cast<String>().toList();

    if (parts.isEmpty) return null;
    // Street + one area label is enough to identify a pickup point without
    // crowding the booking sheet's pickup field.
    return parts.take(2).join(', ');
  }

  // ---------------------------------------------------------------------------
  // Protected overridable platform hooks — isolate each geolocator/geocoding
  // static call so test subclasses can override exactly the platform-bound
  // call without touching the orchestration logic above.
  // ---------------------------------------------------------------------------

  @protected
  Future<bool> checkServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @protected
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @protected
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @protected
  Future<Position> fetchCurrentPosition() => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

  @protected
  Future<List<geocoding.Placemark>> fetchPlacemarks(
    double latitude,
    double longitude,
  ) =>
      geocoding.placemarkFromCoordinates(latitude, longitude);
}
