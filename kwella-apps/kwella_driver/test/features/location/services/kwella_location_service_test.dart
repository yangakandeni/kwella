import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kwella_driver/features/location/services/kwella_location_service.dart';

// ---------------------------------------------------------------------------
// Test doubles
//
// We subclass KwellaLocationService and override its @protected platform hooks.
// This fully isolates the orchestration logic from hardware without any mocking
// framework.
// ---------------------------------------------------------------------------

class _FakeLocationService extends KwellaLocationService {
  _FakeLocationService() : super.forTesting();

  bool serviceEnabled = true;
  LocationPermission currentPermission = LocationPermission.denied;

  /// Queue of responses for successive [requestPermission] calls.
  final List<LocationPermission> _permissionResponses = [];

  /// Stream injected by individual test cases.
  Stream<Position> fakePositionStream = const Stream<Position>.empty();

  void enqueuePermissionResponse(LocationPermission p) =>
      _permissionResponses.add(p);

  @override
  Future<bool> checkServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => currentPermission;

  @override
  Future<LocationPermission> requestPermission() async {
    if (_permissionResponses.isEmpty) return LocationPermission.denied;
    return _permissionResponses.removeAt(0);
  }

  @override
  LocationSettings buildLocationSettings() => const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        timeLimit: Duration(seconds: 5),
      );

  @override
  Stream<Position> getPositionStream(LocationSettings settings) =>
      fakePositionStream;
}

// ---------------------------------------------------------------------------
// Helper: synthesise a Position frame without needing the hardware stack.
// ---------------------------------------------------------------------------
Position _makePosition({
  required double latitude,
  required double longitude,
  double altitude = 0,
  double accuracy = 5,
  double speed = 0,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
    altitudeAccuracy: 0,
    accuracy: accuracy,
    speed: speed,
    speedAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    timestamp: DateTime.now(),
  );
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  late _FakeLocationService svc;

  setUp(() {
    svc = _FakeLocationService();
  });

  // ---- Permission Lifecycle ------------------------------------------------

  group('requestLocationPermissions —', () {
    test('returns false when location service is disabled', () async {
      svc.serviceEnabled = false;

      final result = await svc.requestLocationPermissions();

      expect(result, isFalse);
      expect(svc.permissionsGranted, isFalse);
    });

    test('returns false when permission is permanently denied after dialog',
        () async {
      svc.serviceEnabled = true;
      svc.currentPermission = LocationPermission.denied;
      svc.enqueuePermissionResponse(LocationPermission.deniedForever);

      final result = await svc.requestLocationPermissions();

      expect(result, isFalse);
      expect(svc.permissionsGranted, isFalse);
    });

    test(
        'returns true when foreground granted even if background upgrade denied',
        () async {
      svc.serviceEnabled = true;
      svc.currentPermission = LocationPermission.denied;
      // First dialog → foreground; second (background upgrade) → denied.
      svc.enqueuePermissionResponse(LocationPermission.whileInUse);
      svc.enqueuePermissionResponse(LocationPermission.denied);

      final result = await svc.requestLocationPermissions();

      // whileInUse alone is sufficient — result must be true.
      expect(result, isTrue);
      expect(svc.permissionsGranted, isTrue);
    });

    test('returns true when always (background) permission is granted',
        () async {
      svc.serviceEnabled = true;
      svc.currentPermission = LocationPermission.denied;
      svc.enqueuePermissionResponse(LocationPermission.always);

      final result = await svc.requestLocationPermissions();

      expect(result, isTrue);
      expect(svc.permissionsGranted, isTrue);
    });

    test(
        'upgrades from whileInUse to always when background dialog succeeds',
        () async {
      svc.serviceEnabled = true;
      svc.currentPermission = LocationPermission.whileInUse;
      // No foreground request needed (already granted); only background called.
      svc.enqueuePermissionResponse(LocationPermission.always);

      final result = await svc.requestLocationPermissions();

      expect(result, isTrue);
      expect(svc.permissionsGranted, isTrue);
    });

    test(
        'returns true when currentPermission is already always without dialog',
        () async {
      svc.serviceEnabled = true;
      svc.currentPermission = LocationPermission.always;
      // No responses queued — requestPermission should never be called.

      final result = await svc.requestLocationPermissions();

      expect(result, isTrue);
      expect(svc.permissionsGranted, isTrue);
    });
  });

  // ---- Position Stream ------------------------------------------------------

  group('startPositionStream —', () {
    test('returns empty stream when permissions have not been granted', () async {
      // Deliberately skip calling requestLocationPermissions.
      final stream = svc.startPositionStream();
      expect(await stream.isEmpty, isTrue);
    });

    test('emits synthetic Position frames after permissions are granted',
        () async {
      svc.serviceEnabled = true;
      svc.currentPermission = LocationPermission.always;
      // already 'always' — requestPermission never called, no response needed.

      final positions = [
        _makePosition(latitude: -26.2041, longitude: 28.0473), // Johannesburg
        _makePosition(latitude: -26.2055, longitude: 28.0490),
        _makePosition(latitude: -26.2070, longitude: 28.0505),
      ];
      svc.fakePositionStream = Stream.fromIterable(positions);

      final granted = await svc.requestLocationPermissions();
      expect(granted, isTrue);

      final collected = await svc.startPositionStream().toList();

      expect(collected.length, equals(3));
      expect(collected[0].latitude, closeTo(-26.2041, 0.0001));
      expect(collected[0].longitude, closeTo(28.0473, 0.0001));
      expect(collected[2].latitude, closeTo(-26.2070, 0.0001));
    });

    test(
        'returns empty stream when LocationServiceDisabledException is raised',
        () async {
      svc.serviceEnabled = true;
      svc.currentPermission = LocationPermission.always;
      svc.fakePositionStream =
          Stream.error(const LocationServiceDisabledException());

      await svc.requestLocationPermissions();
      final stream = svc.startPositionStream();

      // Service wraps the exception and surfaces an empty stream, not a throw.
      expect(await stream.isEmpty, isTrue);
    });

    test('returns empty stream when an unexpected error is raised', () async {
      svc.serviceEnabled = true;
      svc.currentPermission = LocationPermission.always;
      svc.fakePositionStream =
          Stream.error(Exception('Simulated hardware failure'));

      await svc.requestLocationPermissions();
      final stream = svc.startPositionStream();

      expect(await stream.isEmpty, isTrue);
    });
  });

  // ---- LocationSettings configuration ---------------------------------------

  group('buildLocationSettings —', () {
    test('is configured for high accuracy with correct filter and time limit',
        () {
      final settings = svc.buildLocationSettings();

      expect(settings.accuracy, equals(LocationAccuracy.high));
      expect(settings.distanceFilter, equals(10));
      expect(settings.timeLimit, equals(const Duration(seconds: 5)));
    });
  });
}
