import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';
import 'package:kwella_rider/features/location/services/kwella_location_service.dart';

// ---------------------------------------------------------------------------
// Test double — subclasses KwellaLocationService and overrides its
// @protected platform hooks so the controller's pickup-resolution flow can
// be driven deterministically without touching platform channels.
// ---------------------------------------------------------------------------
class _FakeLocationService extends KwellaLocationService {
  _FakeLocationService() : super.forTesting();

  bool permissionsGranted = true;
  Position? position;
  String? addressLabel;

  @override
  Future<bool> requestLocationPermissions() async => permissionsGranted;

  @override
  Future<Position?> getCurrentPosition() async => position;

  @override
  Future<String?> resolveAddressLabel(double latitude, double longitude) async =>
      addressLabel;
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
  group('KwellaRiderController', () {
    test('captures incoming driver bid and transitions to biddingOpen', () {
      final controller = KwellaRiderController();

      controller.handleIncomingWebSocketEvent({
        'action': 'driverBidReceived',
        'bidMetrics': [
          {'bidAmount': 120, 'driverId': 'driver-123', 'etaSeconds': 180},
        ],
      });

      expect(controller.state.status, equals(RiderTripStatus.biddingOpen));
      expect(controller.state.bidMetrics, isNotEmpty);
      expect(controller.state.bidMetrics.first['bidAmount'], equals(120));

      controller.dispose();
    });

    test('parses liveDriverLocation events and updates driver coordinates', () {
      final controller = KwellaRiderController();

      controller.handleIncomingWebSocketEvent({
        'action': 'liveDriverLocation',
        'latitude': -34.0012,
        'longitude': 18.6013,
      });

      expect(controller.state.currentDriverLocation, isNotNull);
      expect(
        controller.state.currentDriverLocation?.latitude,
        equals(-34.0012),
      );
      expect(
        controller.state.currentDriverLocation?.longitude,
        equals(18.6013),
      );
      expect(controller.state.status, equals(RiderTripStatus.idle));
      expect(controller.state.pickupLocation, equals(''));
      expect(controller.state.dropoffLocation, equals(''));

      controller.dispose();
    });
  });

  group('resolvePickupLocation —', () {
    test('defaults pickup to the reverse-geocoded device location', () async {
      final fakeService = _FakeLocationService()
        ..position = _makePosition(latitude: -33.9249, longitude: 18.4241)
        ..addressLabel = 'Long Street, Cape Town';
      final controller = KwellaRiderController(locationService: fakeService);

      expect(controller.state.pickupLocationStatus,
          equals(PickupLocationStatus.loading));

      await controller.resolvePickupLocation();

      expect(controller.state.pickupLocation, equals('Long Street, Cape Town'));
      expect(controller.state.pickupLocationStatus,
          equals(PickupLocationStatus.resolved));

      controller.dispose();
    });

    test('falls back to formatted coordinates when reverse geocoding fails',
        () async {
      final fakeService = _FakeLocationService()
        ..position = _makePosition(latitude: -33.9249, longitude: 18.4241)
        ..addressLabel = null;
      final controller = KwellaRiderController(locationService: fakeService);

      await controller.resolvePickupLocation();

      expect(controller.state.pickupLocation, equals('-33.92490, 18.42410'));
      expect(controller.state.pickupLocationStatus,
          equals(PickupLocationStatus.resolved));

      controller.dispose();
    });

    test('marks pickup unavailable when location permission is denied',
        () async {
      final fakeService = _FakeLocationService()..permissionsGranted = false;
      final controller = KwellaRiderController(locationService: fakeService);

      await controller.resolvePickupLocation();

      expect(controller.state.pickupLocation, isEmpty);
      expect(controller.state.pickupLocationStatus,
          equals(PickupLocationStatus.unavailable));

      controller.dispose();
    });

    test('marks pickup unavailable when the position lookup fails', () async {
      final fakeService = _FakeLocationService()
        ..permissionsGranted = true
        ..position = null;
      final controller = KwellaRiderController(locationService: fakeService);

      await controller.resolvePickupLocation();

      expect(controller.state.pickupLocationStatus,
          equals(PickupLocationStatus.unavailable));

      controller.dispose();
    });

    test('manual pickup edits mark the pickup as resolved', () {
      final controller = KwellaRiderController(
        locationService: _FakeLocationService()..permissionsGranted = false,
      );

      controller.updatePickupLocation('My Street, Cape Town');

      expect(controller.state.pickupLocationStatus,
          equals(PickupLocationStatus.resolved));

      controller.dispose();
    });
  });
}
