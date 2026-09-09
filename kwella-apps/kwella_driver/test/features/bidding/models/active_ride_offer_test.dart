import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_driver/features/bidding/models/active_ride_offer.dart';

void main() {
  group('ActiveRideOffer.fromJson', () {
    test('parses the real backend\'s string-label payload with no coordinates',
        () {
      final offer = ActiveRideOffer.fromJson({
        'tripId': 'TRIP#abc-123',
        'pickupLocation': 'Cape Town CBD',
        'dropoffLocation': 'V&A Waterfront',
        'baseFare': 45.50,
        'expiresAt': '2024-06-21T06:00:15.000Z',
      });

      expect(offer.pickupLocation, equals('Cape Town CBD'));
      expect(offer.dropoffLocation, equals('V&A Waterfront'));
      expect(offer.pickupLat, isNull);
      expect(offer.pickupLng, isNull);
      expect(offer.dropoffLat, isNull);
      expect(offer.dropoffLng, isNull);
    });

    test(
        'parses the mock orchestrator\'s pickup_location/dropoff_location '
        '[lat, lon] arrays into pickupLat/pickupLng/dropoffLat/dropoffLng',
        () {
      final offer = ActiveRideOffer.fromJson({
        'tripId': 'TRIP#abc-123',
        'pickup_location': [-33.9249, 18.4241],
        'dropoff_location': [-33.9581, 18.6961],
        'baseFare': 45.50,
        'expiresAt': '2024-06-21T06:00:15.000Z',
      });

      expect(offer.pickupLat, equals(-33.9249));
      expect(offer.pickupLng, equals(18.4241));
      expect(offer.dropoffLat, equals(-33.9581));
      expect(offer.dropoffLng, equals(18.6961));
      // No pickupLocation/dropoffLocation string keys in this payload shape
      // — falls back to a placeholder label rather than throwing.
      expect(offer.pickupLocation, equals('Pickup location unavailable'));
      expect(offer.dropoffLocation, equals('Dropoff location unavailable'));
    });

    test('ignores a malformed pickup_location/dropoff_location shape', () {
      final offer = ActiveRideOffer.fromJson({
        'tripId': 'TRIP#abc-123',
        'pickupLocation': 'Cape Town CBD',
        'dropoffLocation': 'V&A Waterfront',
        'pickup_location': 'not-a-list',
        'baseFare': 45.50,
        'expiresAt': '2024-06-21T06:00:15.000Z',
      });

      expect(offer.pickupLat, isNull);
      expect(offer.pickupLng, isNull);
    });
  });

  group('ActiveRideOffer.fromPushNotification', () {
    test('parses coordinate fields alongside the coordinate-based fallback label',
        () {
      final offer = ActiveRideOffer.fromPushNotification({
        'tripId': 'TRIP#push-1',
        'base_fare': 60,
        'pickup_latitude': -33.9249,
        'pickup_longitude': 18.4241,
        'dropoff_lat': -33.9581,
        'dropoff_lng': 18.6961,
      });

      expect(offer.pickupLat, equals(-33.9249));
      expect(offer.pickupLng, equals(18.4241));
      expect(offer.dropoffLat, equals(-33.9581));
      expect(offer.dropoffLng, equals(18.6961));
      expect(offer.pickupLocation, equals('Pickup @ -33.92490, 18.42410'));
      expect(offer.dropoffLocation, equals('Dropoff @ -33.95810, 18.69610'));
    });

    test(
        'falls back to a placeholder label (without throwing) when neither '
        'an address nor coordinates are present',
        () {
      final offer = ActiveRideOffer.fromPushNotification({
        'tripId': 'TRIP#push-2',
        'base_fare': 60,
      });

      expect(offer.pickupLocation, equals('Pickup location unavailable'));
      expect(offer.dropoffLocation, equals('Dropoff location unavailable'));
      expect(offer.pickupLat, isNull);
      expect(offer.dropoffLat, isNull);
    });

    test('prefers an explicit address label over coordinates when both are present',
        () {
      final offer = ActiveRideOffer.fromPushNotification({
        'tripId': 'TRIP#push-3',
        'base_fare': 60,
        'pickupLocation': 'Woodstock',
        'pickup_latitude': -33.93,
        'pickup_longitude': 18.45,
      });

      expect(offer.pickupLocation, equals('Woodstock'));
      // The coordinate is still captured even though the label came from
      // the address text, not the coordinate fallback.
      expect(offer.pickupLat, equals(-33.93));
      expect(offer.pickupLng, equals(18.45));
    });
  });
}
