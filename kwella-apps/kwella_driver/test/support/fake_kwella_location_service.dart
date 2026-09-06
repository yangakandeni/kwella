import 'package:geolocator/geolocator.dart';

import 'package:kwella_driver/features/location/services/kwella_location_service.dart';

/// Shared [KwellaLocationService] test double.
///
/// Mirrors the pattern originally defined privately (`_FakeLocationService`)
/// inside `kwella_telemetry_controller_test.dart`; factored out here so the
/// driver full-flow E2E suite can drive a scripted GPS position stream
/// without touching real hardware or OS permission dialogs.
///
/// Subclasses [KwellaLocationService] via its `@visibleForTesting` named
/// constructor and overrides the `@protected` platform hooks — exactly the
/// seam the production class was designed to expose for tests.
class FakeKwellaLocationService extends KwellaLocationService {
  FakeKwellaLocationService() : super.forTesting();

  /// Whether the device's location hardware/OS service reports as enabled.
  bool serviceEnabled = true;

  /// The permission [checkPermission] returns before any request.
  LocationPermission startingPermission = LocationPermission.always;

  /// The permission [requestPermission] resolves to when invoked.
  LocationPermission permissionOnRequest = LocationPermission.always;

  /// Injected stream returned by [getPositionStream]. Assign a
  /// [Stream<Position>] (e.g. backed by a [Stream] controller you hold onto)
  /// before calling `startDriverTracking` so frames can be fed on demand.
  Stream<Position> fakeStream = const Stream<Position>.empty();

  @override
  Future<bool> checkServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => startingPermission;

  @override
  Future<LocationPermission> requestPermission() async => permissionOnRequest;

  @override
  LocationSettings buildLocationSettings() => const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        timeLimit: Duration(seconds: 5),
      );

  @override
  Stream<Position> getPositionStream(LocationSettings settings) => fakeStream;
}

/// Builds a synthetic [Position] frame without touching the hardware stack.
Position makeFakePosition({
  required double latitude,
  required double longitude,
  double heading = 0,
  double speed = 0,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    altitude: 0,
    altitudeAccuracy: 0,
    accuracy: 5,
    speed: speed,
    speedAccuracy: 0,
    heading: heading,
    headingAccuracy: 0,
    timestamp: DateTime.now(),
  );
}
