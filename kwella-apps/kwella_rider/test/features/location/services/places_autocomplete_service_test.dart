import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kwella_rider/features/location/services/places_autocomplete_service.dart';

void main() {
  group('PlacesAutocompleteService', () {
    test('returns predictions parsed from a successful response', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'predictions': [
              {
                'place_id': 'place-1',
                'description': 'Shoprite Mandalay, Swartklip Road, Cape Town',
                'structured_formatting': {
                  'main_text': 'Shoprite Mandalay',
                  'secondary_text': 'Swartklip Road, Cape Town',
                },
              },
              {
                'place_id': 'place-2',
                'description': 'Shoprite Lentegeur, Melkbos Road, Cape Town',
                'structured_formatting': {
                  'main_text': 'Shoprite Lentegeur',
                  'secondary_text': 'Melkbos Road, Cape Town',
                },
              },
            ],
          }),
          200,
        );
      });
      final service =
          PlacesAutocompleteService(httpClient: client, apiKey: 'test-key');

      final results = await service.searchPlaces('Shoprite');

      expect(results, hasLength(2));
      expect(results.first.placeId, equals('place-1'));
      expect(results.first.mainText, equals('Shoprite Mandalay'));
      expect(results.first.secondaryText, equals('Swartklip Road, Cape Town'));
      expect(
        results.first.description,
        equals('Shoprite Mandalay, Swartklip Road, Cape Town'),
      );
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.url.queryParameters['input'], equals('Shoprite'));
      expect(capturedRequest!.url.queryParameters['key'], equals('test-key'));
    });

    test('returns no results for queries shorter than 3 characters without '
        'calling the network', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        return http.Response('{}', 200);
      });
      final service =
          PlacesAutocompleteService(httpClient: client, apiKey: 'test-key');

      final results = await service.searchPlaces('Sh');

      expect(results, isEmpty);
      expect(callCount, equals(0));
    });

    test('returns no results when no API key is configured', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        return http.Response('{}', 200);
      });
      final service = PlacesAutocompleteService(httpClient: client, apiKey: '');

      final results = await service.searchPlaces('Shoprite');

      expect(results, isEmpty);
      expect(callCount, equals(0));
    });

    test('returns no results when the API responds with a non-OK status',
        () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'status': 'ZERO_RESULTS'}), 200);
      });
      final service =
          PlacesAutocompleteService(httpClient: client, apiKey: 'test-key');

      final results = await service.searchPlaces('Shoprite');

      expect(results, isEmpty);
    });

    test('returns no results and does not throw on an HTTP error response',
        () async {
      final client = MockClient((request) async {
        return http.Response('Server error', 500);
      });
      final service =
          PlacesAutocompleteService(httpClient: client, apiKey: 'test-key');

      final results = await service.searchPlaces('Shoprite');

      expect(results, isEmpty);
    });

    test('returns no results and does not throw when the network call throws',
        () async {
      final client = MockClient((request) async {
        throw Exception('network down');
      });
      final service =
          PlacesAutocompleteService(httpClient: client, apiKey: 'test-key');

      final results = await service.searchPlaces('Shoprite');

      expect(results, isEmpty);
    });

    test(
        'biases toward the supplied origin and sorts results nearest-first',
        () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'predictions': [
              {
                'place_id': 'place-far',
                'description': 'Shoprite Blue Downs',
                'distance_meters': 7400,
              },
              {
                'place_id': 'place-near',
                'description': 'Shoprite Mandalay',
                'distance_meters': 1600,
              },
            ],
          }),
          200,
        );
      });
      final service =
          PlacesAutocompleteService(httpClient: client, apiKey: 'test-key');

      final results = await service.searchPlaces(
        'Shoprite',
        originLat: -33.97,
        originLng: 18.63,
      );

      expect(capturedRequest!.url.queryParameters['location'],
          equals('-33.97,18.63'));
      expect(capturedRequest!.url.queryParameters['origin'],
          equals('-33.97,18.63'));
      expect(capturedRequest!.url.queryParameters['radius'], isNotNull);

      expect(results.map((r) => r.placeId), equals(['place-near', 'place-far']));
      expect(results.first.distanceMeters, equals(1600));
    });

    test('omits location bias params when no origin is supplied', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(jsonEncode({'status': 'OK', 'predictions': []}), 200);
      });
      final service =
          PlacesAutocompleteService(httpClient: client, apiKey: 'test-key');

      await service.searchPlaces('Shoprite');

      expect(capturedRequest!.url.queryParameters.containsKey('location'), isFalse);
      expect(capturedRequest!.url.queryParameters.containsKey('origin'), isFalse);
    });
  });

  group('PlacesAutocompleteService.getPlaceDetails', () {
    test('resolves the lat/lng of a place', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'result': {
              'geometry': {
                'location': {'lat': -33.97, 'lng': 18.63},
              },
            },
          }),
          200,
        );
      });
      final service =
          PlacesAutocompleteService(httpClient: client, apiKey: 'test-key');

      final location = await service.getPlaceDetails('place-1');

      expect(location, isNotNull);
      expect(location!.lat, equals(-33.97));
      expect(location.lng, equals(18.63));
      expect(capturedRequest!.url.queryParameters['place_id'], equals('place-1'));
    });

    test('returns null and does not throw on failure', () async {
      final client = MockClient((request) async {
        throw Exception('network down');
      });
      final service =
          PlacesAutocompleteService(httpClient: client, apiKey: 'test-key');

      final location = await service.getPlaceDetails('place-1');

      expect(location, isNull);
    });

    test('returns null without a network call when no API key is configured',
        () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        return http.Response('{}', 200);
      });
      final service = PlacesAutocompleteService(httpClient: client, apiKey: '');

      final location = await service.getPlaceDetails('place-1');

      expect(location, isNull);
      expect(callCount, equals(0));
    });
  });
}
