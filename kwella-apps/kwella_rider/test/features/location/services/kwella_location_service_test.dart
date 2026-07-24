import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:kwella_rider/features/location/services/kwella_location_service.dart';

// ---------------------------------------------------------------------------
// Test double — subclasses KwellaLocationService and overrides its
// @protected platform hooks, isolating the orchestration logic from
// hardware/platform channels without any mocking framework. Mirrors the
// pattern used by kwella_driver's KwellaLocationService test.
// ---------------------------------------------------------------------------
class _FakeLocationService extends KwellaLocationService {
  _FakeLocationService() : super.forTesting();

  bool serviceEnabled = true;
  LocationPermission currentPermission = LocationPermission.denied;
  final List<LocationPermission> _permissionResponses = [];

  Position? fakePosition;
  Object? positionError;

  List<geocoding.Placemark> fakePlacemarks = const [];
  Object? placemarksError;

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
  Future<Position> fetchCurrentPosition() async {
    if (positionError != null) throw positionError!;
    return fakePosition!;
  }

  @override
  Future<List<geocoding.Placemark>> fetchPlacemarks(
    double latitude,
    double longitude,
  ) async {
    if (placemarksError != null) throw placemarksError!;
    return fakePlacemarks;
  }
}

Position _makePosition({required double latitude, required double longitude}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    altitude: 0,
    altitudeAccuracy: 0,
    accuracy: 5,
    speed: 0,
    speedAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    timestamp: DateTime.now(),
  );
}

void main() {
  late _FakeLocationService svc;

  setUp(() {
    svc = _FakeLocationService();
  });

  group('requestLocationPermissions —', () {
    test('returns false when location service is disabled', () async {
      svc.serviceEnabled = false;

      final result = await svc.requestLocationPermissions();

      expect(result, isFalse);
    });

    test('returns false when permission is denied and dialog is refused',
        () async {
      svc.serviceEnabled = true;
      svc.currentPermission = LocationPermission.denied;
      svc.enqueuePermissionResponse(LocationPermission.denied);

      final result = await svc.requestLocationPermissions();

      expect(result, isFalse);
    });

    test('returns true when whileInUse permission is already granted',
        () async {
      svc.serviceEnabled = true;
      svc.currentPermission = LocationPermission.whileInUse;

      final result = await svc.requestLocationPermissions();

      expect(result, isTrue);
    });

    test('returns true when permission is granted after the runtime dialog',
        () async {
      svc.serviceEnabled = true;
      svc.currentPermission = LocationPermission.denied;
      svc.enqueuePermissionResponse(LocationPermission.always);

      final result = await svc.requestLocationPermissions();

      expect(result, isTrue);
    });
  });

  group('getCurrentPosition —', () {
    test('returns the fetched position', () async {
      svc.fakePosition =
          _makePosition(latitude: -33.9249, longitude: 18.4241);

      final position = await svc.getCurrentPosition();

      expect(position, isNotNull);
      expect(position!.latitude, closeTo(-33.9249, 0.0001));
      expect(position.longitude, closeTo(18.4241, 0.0001));
    });

    test('returns null (never throws) when the platform call fails',
        () async {
      svc.positionError = Exception('Simulated hardware failure');

      final position = await svc.getCurrentPosition();

      expect(position, isNull);
    });
  });

  group('resolveAddressLabel —', () {
    test('formats street + sub-locality into a short label', () async {
      svc.fakePlacemarks = const [
        geocoding.Placemark(
          street: 'Long Street',
          subLocality: 'City Bowl',
          locality: 'Cape Town',
        ),
      ];

      final label = await svc.resolveAddressLabel(-33.9249, 18.4241);

      expect(label, equals('Long Street, City Bowl'));
    });

    test('falls back to locality when street/sub-locality are unavailable',
        () async {
      svc.fakePlacemarks = const [
        geocoding.Placemark(locality: 'Cape Town'),
      ];

      final label = await svc.resolveAddressLabel(-33.9249, 18.4241);

      expect(label, equals('Cape Town'));
    });

    test('returns null when no placemarks are found', () async {
      svc.fakePlacemarks = const [];

      final label = await svc.resolveAddressLabel(-33.9249, 18.4241);

      expect(label, isNull);
    });

    test('returns null (never throws) when the platform call fails',
        () async {
      svc.placemarksError = Exception('Simulated geocoding failure');

      final label = await svc.resolveAddressLabel(-33.9249, 18.4241);

      expect(label, isNull);
    });
  });
}
