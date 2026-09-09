import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';
import 'package:kwella_rider/features/location/services/kwella_location_service.dart';

import 'support/fake_websocket_gateway.dart';

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

    test('connect() opens the gateway and forwards decoded incoming frames',
        () async {
      final fakeGateway = FakeWebSocketGateway();
      final controller = KwellaRiderController(gateway: fakeGateway);

      await controller.connect(riderId: 'rider-1', accessToken: 'token-abc');

      expect(fakeGateway.connected, isTrue);
      expect(fakeGateway.lastAccessToken, equals('token-abc'));

      fakeGateway.simulateIncomingFrame(jsonEncode({
        'action': 'driverBidReceived',
        'tripId': 'trip-99',
        'bidMetrics': [
          {'bidAmount': 80, 'driverId': 'driver-9'},
        ],
      }));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, equals(RiderTripStatus.biddingOpen));
      expect(controller.state.tripId, equals('trip-99'));

      controller.dispose();
      await fakeGateway.disconnect();
    });

    test('connect() tolerates malformed incoming frames without throwing',
        () async {
      final fakeGateway = FakeWebSocketGateway();
      final controller = KwellaRiderController(gateway: fakeGateway);

      await controller.connect(riderId: 'rider-1', accessToken: 'token-abc');
      fakeGateway.simulateIncomingFrame('not valid json');
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, equals(RiderTripStatus.idle));

      controller.dispose();
      await fakeGateway.disconnect();
    });

    test('requestTrip() sends a requestTrip frame before flipping to searching',
        () {
      final fakeGateway = FakeWebSocketGateway();
      final controller = KwellaRiderController(gateway: fakeGateway);

      controller.updatePickupLocation('Pickup', lat: -33.9, lng: 18.4);
      controller.updateDropoffLocation('Dropoff', lat: -34.0, lng: 18.5);
      controller.setPassengerCount(2);
      controller.requestTrip();

      expect(fakeGateway.sentPayloads, hasLength(1));
      expect(fakeGateway.sentPayloads.single, equals({
        'action': 'requestTrip',
        'riderId': null,
        'pickup_latitude': -33.9,
        'pickup_longitude': 18.4,
        'dropoff_latitude': -34.0,
        'dropoff_longitude': 18.5,
        'passenger_count': 2,
      }));
      expect(controller.state.status, equals(RiderTripStatus.searching));

      controller.dispose();
    });

    test('requestTrip() includes the riderId set via connect()', () async {
      final fakeGateway = FakeWebSocketGateway();
      final controller = KwellaRiderController(gateway: fakeGateway);
      await controller.connect(riderId: 'rider-42', accessToken: 'token');

      controller.requestTrip();

      expect(fakeGateway.sentPayloads.single['riderId'], equals('rider-42'));

      controller.dispose();
      await fakeGateway.disconnect();
    });

    test('selectBid() sends a selectBid frame through the gateway', () {
      final fakeGateway = FakeWebSocketGateway();
      final controller = KwellaRiderController(gateway: fakeGateway);

      controller.handleIncomingWebSocketEvent({
        'action': 'driverBidReceived',
        'tripId': 'trip-5',
      });
      controller.selectBid('driver-7');

      expect(fakeGateway.sentPayloads.single, equals({
        'action': 'selectBid',
        'tripId': 'trip-5',
        'driverId': 'driver-7',
      }));
      expect(controller.state.status, equals(RiderTripStatus.accepted));

      controller.dispose();
    });

    test('submitRating() sends a submitRating frame through the gateway', () {
      final fakeGateway = FakeWebSocketGateway();
      final controller = KwellaRiderController(gateway: fakeGateway);

      controller.handleIncomingWebSocketEvent({
        'action': 'driverBidReceived',
        'tripId': 'trip-5',
      });
      controller.submitRating(5);

      expect(fakeGateway.sentPayloads.single, equals({
        'action': 'submitRating',
        'tripId': 'trip-5',
        'rating': 5,
        'target': 'DRIVER',
      }));

      controller.dispose();
    });

    test('setPaymentMethod() updates the state', () {
      final controller = KwellaRiderController();

      expect(controller.state.paymentMethod, equals('CASH'));
      controller.setPaymentMethod('CARD');
      expect(controller.state.paymentMethod, equals('CARD'));

      controller.dispose();
    });

    test('raiseFare() sends an updateFare frame and optimistically updates offeredFare',
        () {
      final fakeGateway = FakeWebSocketGateway();
      final controller = KwellaRiderController(gateway: fakeGateway);

      controller.handleIncomingWebSocketEvent({
        'status': 'TripBroadcast',
        'tripId': 'trip-5',
        'matched_drivers': 3,
        'passenger_count': 1,
        'calculated_fare': '60',
      });

      controller.raiseFare(75.0);

      expect(fakeGateway.sentPayloads.last, equals({
        'action': 'updateFare',
        'tripId': 'trip-5',
        'riderId': null,
        'new_fare': 75.0,
      }));
      expect(controller.state.offeredFare, equals(75.0));

      controller.dispose();
    });

    test('declineBid() removes a specific bid from bidMetrics without a wire call',
        () {
      final fakeGateway = FakeWebSocketGateway();
      final controller = KwellaRiderController(gateway: fakeGateway);

      controller.handleIncomingWebSocketEvent({
        'action': 'driverBidReceived',
        'tripId': 'trip-5',
        'bidMetrics': [
          {'driverId': 'driver-1', 'bidAmount': 100},
          {'driverId': 'driver-2', 'bidAmount': 90},
        ],
      });

      controller.declineBid('driver-1');

      expect(controller.state.bidMetrics, hasLength(1));
      expect(controller.state.bidMetrics.single['driverId'], equals('driver-2'));
      expect(fakeGateway.sentPayloads, isEmpty);

      controller.dispose();
    });

    test('cancelSearch() resets state to idle with no wire call', () {
      final fakeGateway = FakeWebSocketGateway();
      final controller = KwellaRiderController(gateway: fakeGateway);

      controller.requestTrip();
      controller.handleIncomingWebSocketEvent({
        'action': 'driverBidReceived',
        'bidMetrics': [
          {'driverId': 'driver-1', 'bidAmount': 100},
        ],
      });

      controller.cancelSearch();

      expect(controller.state.status, equals(RiderTripStatus.idle));
      expect(controller.state.bidMetrics, isEmpty);
      // Only the earlier requestTrip() frame was ever sent — cancelSearch()
      // itself makes no wire call.
      expect(fakeGateway.sentPayloads, hasLength(1));

      controller.dispose();
    });

    test('requestTrip(autoAccept: true) auto-selects the first incoming bid',
        () {
      final fakeGateway = FakeWebSocketGateway();
      final controller = KwellaRiderController(gateway: fakeGateway);

      controller.requestTrip(autoAccept: true);
      expect(controller.state.autoAcceptEnabled, isTrue);

      controller.handleIncomingWebSocketEvent({
        'action': 'driverBidReceived',
        'tripId': 'trip-5',
        'bidMetrics': [
          {'driverId': 'driver-1', 'bidAmount': 100},
          {'driverId': 'driver-2', 'bidAmount': 90},
        ],
      });

      expect(controller.state.status, equals(RiderTripStatus.accepted));
      final Map<String, dynamic> selectBidFrame = fakeGateway.sentPayloads
          .singleWhere((m) => m['action'] == 'selectBid');
      expect(selectBidFrame['driverId'], equals('driver-1'));
      expect(selectBidFrame['tripId'], equals('trip-5'));

      controller.dispose();
    });

    test('requestTrip() without autoAccept leaves incoming bids for manual selection',
        () {
      final fakeGateway = FakeWebSocketGateway();
      final controller = KwellaRiderController(gateway: fakeGateway);

      controller.requestTrip();
      expect(controller.state.autoAcceptEnabled, isFalse);

      controller.handleIncomingWebSocketEvent({
        'action': 'driverBidReceived',
        'tripId': 'trip-5',
        'bidMetrics': [
          {'driverId': 'driver-1', 'bidAmount': 100},
        ],
      });

      expect(controller.state.status, equals(RiderTripStatus.biddingOpen));
      expect(
        fakeGateway.sentPayloads.where((m) => m['action'] == 'selectBid'),
        isEmpty,
      );

      controller.dispose();
    });

    test('handles TripBroadcast status by setting tripId and offeredFare from calculated_fare',
        () {
      final controller = KwellaRiderController();

      controller.handleIncomingWebSocketEvent({
        'status': 'TripBroadcast',
        'tripId': 'trip-42',
        'matched_drivers': 4,
        'passenger_count': 2,
        'calculated_fare': '87.5',
      });

      expect(controller.state.tripId, equals('trip-42'));
      expect(controller.state.offeredFare, equals(87.5));

      controller.dispose();
    });

    test('handles TripBroadcast status when calculated_fare arrives as a number',
        () {
      final controller = KwellaRiderController();

      controller.handleIncomingWebSocketEvent({
        'status': 'TripBroadcast',
        'tripId': 'trip-42',
        'calculated_fare': 87.5,
      });

      expect(controller.state.offeredFare, equals(87.5));

      controller.dispose();
    });

    test('handles FareUpdated status by reconciling offeredFare from base_fare',
        () {
      final controller = KwellaRiderController();

      controller.handleIncomingWebSocketEvent({
        'status': 'FareUpdated',
        'tripId': 'trip-42',
        'base_fare': '95',
      });

      expect(controller.state.offeredFare, equals(95.0));

      controller.dispose();
    });

    test('upserts nearbyDriverUpdate frames into nearbyDrivers keyed by driverId',
        () {
      final controller = KwellaRiderController();

      controller.handleIncomingWebSocketEvent({
        'action': 'nearbyDriverUpdate',
        'driverId': 'driver-idle-1',
        'latitude': -33.9,
        'longitude': 18.4,
        'status': 'idle',
      });

      expect(controller.state.nearbyDrivers, hasLength(1));
      expect(
        controller.state.nearbyDrivers['driver-idle-1']?.latitude,
        equals(-33.9),
      );
      expect(
        controller.state.nearbyDrivers['driver-idle-1']?.longitude,
        equals(18.4),
      );

      controller.handleIncomingWebSocketEvent({
        'action': 'nearbyDriverUpdate',
        'driverId': 'driver-idle-2',
        'latitude': -34.0,
        'longitude': 18.5,
        'status': 'idle',
      });

      expect(controller.state.nearbyDrivers, hasLength(2));
      // The first driver's entry survives the second driver's update — the
      // map is upserted, not replaced wholesale.
      expect(controller.state.nearbyDrivers['driver-idle-1'], isNotNull);

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
      expect(controller.state.pickupLat, equals(-33.9249));
      expect(controller.state.pickupLng, equals(18.4241));

      controller.dispose();
    });

    test('falls back to a friendly label when reverse geocoding fails',
        () async {
      final fakeService = _FakeLocationService()
        ..position = _makePosition(latitude: -33.9249, longitude: 18.4241)
        ..addressLabel = null;
      final controller = KwellaRiderController(locationService: fakeService);

      await controller.resolvePickupLocation();

      expect(controller.state.pickupLocation, equals('Selected Location'));
      expect(controller.state.pickupLocation, isNot(matches(r'-?\d')));
      expect(controller.state.pickupLocationStatus,
          equals(PickupLocationStatus.resolved));
      expect(controller.state.pickupLat, equals(-33.9249));
      expect(controller.state.pickupLng, equals(18.4241));

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

    test('selecting a pickup suggestion records its coordinates', () {
      final controller = KwellaRiderController(
        locationService: _FakeLocationService()..permissionsGranted = false,
      );

      controller.updatePickupLocation(
        'Shoprite Mandalay, Swartklip Road, Cape Town',
        lat: -33.97,
        lng: 18.63,
      );

      expect(controller.state.pickupLat, equals(-33.97));
      expect(controller.state.pickupLng, equals(18.63));

      // A later free-text edit (no coordinates supplied) keeps the last
      // resolved coordinate rather than clearing it, so proximity biasing
      // stays intact while the rider keeps typing.
      controller.updatePickupLocation('Shoprite Ma');

      expect(controller.state.pickupLat, equals(-33.97));
      expect(controller.state.pickupLng, equals(18.63));

      controller.dispose();
    });
  });

  group('updatePickupFromMapPin / updateDropoffFromMapPin —', () {
    test('reverse-geocodes a dragged pickup pin into pickupLocation', () async {
      final fakeService = _FakeLocationService()
        ..addressLabel = 'Long Street, Cape Town';
      final controller = KwellaRiderController(locationService: fakeService);

      await controller.updatePickupFromMapPin(-33.9249, 18.4241);

      expect(controller.state.pickupLocation, equals('Long Street, Cape Town'));
      expect(controller.state.pickupLocationStatus,
          equals(PickupLocationStatus.resolved));
      expect(controller.state.pickupLat, equals(-33.9249));
      expect(controller.state.pickupLng, equals(18.4241));

      controller.dispose();
    });

    test('falls back to a friendly label when reverse geocoding a dropped pickup pin fails',
        () async {
      final fakeService = _FakeLocationService()..addressLabel = null;
      final controller = KwellaRiderController(locationService: fakeService);

      await controller.updatePickupFromMapPin(-33.9249, 18.4241);

      expect(controller.state.pickupLocation, equals('Selected Location'));
      expect(controller.state.pickupLat, equals(-33.9249));
      expect(controller.state.pickupLng, equals(18.4241));

      controller.dispose();
    });

    test('reverse-geocodes a dragged dropoff pin into dropoffLocation', () async {
      final fakeService = _FakeLocationService()
        ..addressLabel = 'V&A Waterfront, Cape Town';
      final controller = KwellaRiderController(locationService: fakeService);

      await controller.updateDropoffFromMapPin(-33.9036, 18.4216);

      expect(controller.state.dropoffLocation,
          equals('V&A Waterfront, Cape Town'));
      expect(controller.state.dropoffLat, equals(-33.9036));
      expect(controller.state.dropoffLng, equals(18.4216));

      controller.dispose();
    });

    test('falls back to a friendly label when reverse geocoding a dropped dropoff pin fails',
        () async {
      final fakeService = _FakeLocationService()..addressLabel = null;
      final controller = KwellaRiderController(locationService: fakeService);

      await controller.updateDropoffFromMapPin(-33.9036, 18.4216);

      expect(controller.state.dropoffLocation, equals('Selected Location'));
      expect(controller.state.dropoffLat, equals(-33.9036));
      expect(controller.state.dropoffLng, equals(18.4216));

      controller.dispose();
    });
  });
}
