import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_driver/features/bidding/models/active_ride_offer.dart';

/// The `rideOfferAvailable` WebSocket frame exactly as
/// `kwella-backend/src/lambdas/bidding_engine/handler.py`'s
/// `_dispatch_ride_offer_to_matched_drivers` builds it (and
/// `scripts/mock_orchestrator/contract.py` mirrors it). Fixtures here are
/// copied from the producing handler, not from what the parser happens to
/// accept.
Map<String, dynamic> _wsFrame() => <String, dynamic>{
  'action': 'rideOfferAvailable',
  'tripId': 'TRIP#abc-123',
  'rider_id': 'USR#rider-001',
  'pickup_location': <double>[-33.9249, 18.4241],
  'dropoff_location': <double>[-33.9581, 18.6961],
  'passenger_count': 3,
  'base_fare': '45.50',
  'expires_in_seconds': 15,
};

void main() {
  group('ActiveRideOffer.fromJson', () {
    test('parses the WebSocket frame both backends actually send', () {
      final offer = ActiveRideOffer.fromJson(_wsFrame());

      expect(offer.tripId, equals('TRIP#abc-123'));
      expect(offer.riderId, equals('USR#rider-001'));
      // base_fare arrives as a string on the wire.
      expect(offer.baseFare, closeTo(45.50, 0.001));
      expect(offer.pickupLat, equals(-33.9249));
      expect(offer.pickupLng, equals(18.4241));
      expect(offer.dropoffLat, equals(-33.9581));
      expect(offer.dropoffLng, equals(18.6961));
    });

    test('derives display labels from the coordinates, since no payload in '
        'the stack carries an address string', () {
      final offer = ActiveRideOffer.fromJson(_wsFrame());

      expect(offer.pickupLocation, equals('Pickup @ -33.92490, 18.42410'));
      expect(offer.dropoffLocation, equals('Dropoff @ -33.95810, 18.69610'));
    });

    test('parses the FCM fallback payload, which carries only tripId and '
        'base_fare', () {
      // _send_fcm_push_via_sns in the same handler.
      final offer = ActiveRideOffer.fromJson(<String, dynamic>{
        'action': 'rideOfferAvailable',
        'tripId': 'TRIP#push-1',
        'base_fare': '60.0',
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      });

      expect(offer.tripId, equals('TRIP#push-1'));
      expect(offer.baseFare, closeTo(60.0, 0.001));
      expect(offer.riderId, isNull);
      expect(offer.pickupLat, isNull);
      expect(offer.dropoffLat, isNull);
      expect(offer.pickupLocation, equals('Pickup location unavailable'));
      expect(offer.dropoffLocation, equals('Dropoff location unavailable'));
    });

    test('accepts a numeric base_fare as well as the string the wire uses',
        () {
      final offer = ActiveRideOffer.fromJson(
        _wsFrame()..['base_fare'] = 45.50,
      );

      expect(offer.baseFare, closeTo(45.50, 0.001));
    });

    test('discards a malformed coordinate pair whole rather than per-axis',
        () {
      final offer = ActiveRideOffer.fromJson(
        _wsFrame()
          ..['pickup_location'] = 'not-a-list'
          ..['dropoff_location'] = <Object>[-33.95, 'not-a-number'],
      );

      expect(offer.pickupLat, isNull);
      expect(offer.pickupLng, isNull);
      expect(offer.dropoffLat, isNull);
      expect(offer.dropoffLng, isNull);
    });

    test('throws when tripId is absent', () {
      expect(
        () => ActiveRideOffer.fromJson(_wsFrame()..remove('tripId')),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when base_fare is absent or unparseable', () {
      expect(
        () => ActiveRideOffer.fromJson(_wsFrame()..remove('base_fare')),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ActiveRideOffer.fromJson(_wsFrame()..['base_fare'] = ''),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
