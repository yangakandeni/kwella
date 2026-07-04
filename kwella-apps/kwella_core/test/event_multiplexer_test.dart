import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_core/src/network/bidding_events.dart';

void main() {
  group('KwellaBiddingEvent parser', () {
    test('parses BidReceivedEvent correctly', () {
      final json = {
        'action': 'BidReceived',
        'payload': {
          'id': 'bid-123',
          'driverName': 'John Doe',
          'rating': '4.8',
          'eta': '5 mins',
          'price': 'R 45.00'
        }
      };

      final event = KwellaBiddingEvent.fromJson(json);

      expect(event, isA<BidReceivedEvent>());
      final bidEvent = event as BidReceivedEvent;
      expect(bidEvent.bid.id, 'bid-123');
      expect(bidEvent.bid.driverName, 'John Doe');
      expect(bidEvent.bid.rating, '4.8');
      expect(bidEvent.bid.eta, '5 mins');
      expect(bidEvent.bid.price, 'R 45.00');
    });

    test('parses RideAcceptedEvent correctly', () {
      final json = {
        'action': 'RideAccepted',
        'payload': {
          'rideId': 'ride-999',
          'driverId': 'drv-456',
          'finalPrice': 'R 50.00'
        }
      };

      final event = KwellaBiddingEvent.fromJson(json);

      expect(event, isA<RideAcceptedEvent>());
      final acceptedEvent = event as RideAcceptedEvent;
      expect(acceptedEvent.rideId, 'ride-999');
      expect(acceptedEvent.driverId, 'drv-456');
      expect(acceptedEvent.finalPrice, 'R 50.00');
    });

    test('parses RideCancelledEvent correctly', () {
      final json = {
        'action': 'RideCancelled',
        'payload': {
          'rideId': 'ride-999',
          'reason': 'Driver unavailable'
        }
      };

      final event = KwellaBiddingEvent.fromJson(json);

      expect(event, isA<RideCancelledEvent>());
      final cancelledEvent = event as RideCancelledEvent;
      expect(cancelledEvent.rideId, 'ride-999');
      expect(cancelledEvent.reason, 'Driver unavailable');
    });

    test('parses RideCancelledEvent without reason correctly', () {
      final json = {
        'action': 'RideCancelled',
        'payload': {
          'rideId': 'ride-999'
        }
      };

      final event = KwellaBiddingEvent.fromJson(json);

      expect(event, isA<RideCancelledEvent>());
      final cancelledEvent = event as RideCancelledEvent;
      expect(cancelledEvent.rideId, 'ride-999');
      expect(cancelledEvent.reason, isNull);
    });

    test('throws FormatException on unknown action', () {
      final json = {
        'action': 'UnknownAction',
        'payload': {}
      };

      expect(() => KwellaBiddingEvent.fromJson(json), throwsFormatException);
    });
  });
}
