import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:kwella_rider/features/location/services/places_autocomplete_service.dart';

const KwellaEnvironment _localEnv = KwellaEnvironment(
  httpApiEndpoint: 'http://10.0.2.2:8790/',
  isLocal: true,
);

Map<String, dynamic> _suggestion({
  required String placeId,
  required String description,
  String? mainText,
  String? secondaryText,
  int? distanceMeters,
}) {
  return {
    'placePrediction': {
      'placeId': placeId,
      'text': {'text': description},
      'structuredFormat': {
        'mainText': {'text': mainText ?? description},
        'secondaryText': {'text': secondaryText ?? ''},
      },
      'distanceMeters': ?distanceMeters,
    },
  };
}

void main() {
  group('PlacesAutocompleteService', () {
    test('returns predictions parsed from a successful response', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'suggestions': [
              _suggestion(
                placeId: 'place-1',
                description: 'Shoprite Mandalay, Swartklip Road, Cape Town',
                mainText: 'Shoprite Mandalay',
                secondaryText: 'Swartklip Road, Cape Town',
              ),
              _suggestion(
                placeId: 'place-2',
                description: 'Shoprite Lentegeur, Melkbos Road, Cape Town',
                mainText: 'Shoprite Lentegeur',
                secondaryText: 'Melkbos Road, Cape Town',
              ),
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
      expect(capturedRequest!.method, equals('POST'));
      expect(
        capturedRequest!.url.toString(),
        equals('https://places.googleapis.com/v1/places:autocomplete'),
      );
      expect(capturedRequest!.headers['X-Goog-Api-Key'], equals('test-key'));

      final Map<String, dynamic> body = jsonDecode(capturedRequest!.body);
      expect(body['input'], equals('Shoprite'));
      expect(body['sessionToken'], isA<String>());
      expect(body['sessionToken'], isNotEmpty);
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

    test('returns no results when the API responds without suggestions',
        () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({}), 200);
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
            'suggestions': [
              _suggestion(
                placeId: 'place-far',
                description: 'Shoprite Blue Downs',
                distanceMeters: 7400,
              ),
              _suggestion(
                placeId: 'place-near',
                description: 'Shoprite Mandalay',
                distanceMeters: 1600,
              ),
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

      final Map<String, dynamic> body = jsonDecode(capturedRequest!.body);
      expect(
        body['locationBias']['circle']['center'],
        equals({'latitude': -33.97, 'longitude': 18.63}),
      );
      expect(body['locationBias']['circle']['radius'], isNotNull);

      expect(results.map((r) => r.placeId), equals(['place-near', 'place-far']));
      expect(results.first.distanceMeters, equals(1600));
    });

    test('omits locationBias when no origin is supplied', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(jsonEncode({'suggestions': []}), 200);
      });
      final service =
          PlacesAutocompleteService(httpClient: client, apiKey: 'test-key');

      await service.searchPlaces('Shoprite');

      final Map<String, dynamic> body = jsonDecode(capturedRequest!.body);
      expect(body.containsKey('locationBias'), isFalse);
    });

    test(
        'in local mode, routes to the mock orchestrator '
        'maps/place/autocomplete endpoint without an API key header, even '
        'with no API key configured', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'suggestions': [
              _suggestion(
                placeId: 'place-1',
                description: 'Shoprite Mandalay, Swartklip Road, Cape Town',
              ),
            ],
          }),
          200,
        );
      });
      final service = PlacesAutocompleteService(
        httpClient: client,
        environment: _localEnv,
      );

      final results = await service.searchPlaces(
        'Shoprite',
        originLat: -33.97,
        originLng: 18.63,
      );

      expect(results, hasLength(1));
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.method, equals('POST'));
      expect(capturedRequest!.url.host, equals('10.0.2.2'));
      expect(capturedRequest!.url.path, equals('/maps/place/autocomplete'));
      expect(capturedRequest!.headers.containsKey('X-Goog-Api-Key'), isFalse);

      final Map<String, dynamic> body = jsonDecode(capturedRequest!.body);
      expect(body['input'], equals('Shoprite'));
      expect(
        body['locationBias']['circle']['center'],
        equals({'latitude': -33.97, 'longitude': 18.63}),
      );
    });

    test(
        'reuses the same session token across searches, then clears it '
        'once getPlaceDetails consumes it', () async {
      final List<http.Request> capturedRequests = [];
      final client = MockClient((request) async {
        capturedRequests.add(request);
        if (request.url.path.contains('autocomplete')) {
          return http.Response(
            jsonEncode({
              'suggestions': [
                _suggestion(placeId: 'place-1', description: 'Shoprite'),
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'id': 'place-1',
            'location': {'latitude': -33.97, 'longitude': 18.63},
          }),
          200,
        );
      });
      final service =
          PlacesAutocompleteService(httpClient: client, apiKey: 'test-key');

      await service.searchPlaces('Shop');
      await service.searchPlaces('Shopr');
      final String firstToken =
          jsonDecode(capturedRequests[0].body)['sessionToken'] as String;
      final String secondToken =
          jsonDecode(capturedRequests[1].body)['sessionToken'] as String;
      expect(secondToken, equals(firstToken));

      await service.getPlaceDetails('place-1');
      expect(
        capturedRequests[2].url.queryParameters['sessionToken'],
        equals(firstToken),
      );

      await service.searchPlaces('Newquery');
      final String thirdToken =
          jsonDecode(capturedRequests[3].body)['sessionToken'] as String;
      expect(thirdToken, isNot(equals(firstToken)));
    });
  });

  group('PlacesAutocompleteService.getPlaceDetails', () {
    test('resolves the lat/lng of a place', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'id': 'place-1',
            'location': {'latitude': -33.97, 'longitude': 18.63},
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
      expect(capturedRequest!.url.host, equals('places.googleapis.com'));
      expect(capturedRequest!.url.path, equals('/v1/places/place-1'));
      expect(capturedRequest!.headers['X-Goog-Api-Key'], equals('test-key'));
      expect(capturedRequest!.headers['X-Goog-FieldMask'], equals('location'));
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

    test(
        'in local mode, routes to the mock orchestrator '
        'maps/place/details endpoint without an API key header, even with '
        'no API key configured', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'id': 'place-1',
            'location': {'latitude': -33.97, 'longitude': 18.63},
          }),
          200,
        );
      });
      final service = PlacesAutocompleteService(
        httpClient: client,
        environment: _localEnv,
      );

      final location = await service.getPlaceDetails('place-1');

      expect(location, isNotNull);
      expect(location!.lat, equals(-33.97));
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.url.host, equals('10.0.2.2'));
      expect(capturedRequest!.url.path, equals('/maps/place/details'));
      expect(capturedRequest!.headers.containsKey('X-Goog-Api-Key'), isFalse);
      expect(
        capturedRequest!.url.queryParameters['place_id'],
        equals('place-1'),
      );
    });
  });
}
