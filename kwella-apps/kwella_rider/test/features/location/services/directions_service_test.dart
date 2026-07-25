import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kwella_rider/features/location/services/directions_service.dart';

void main() {
  group('DirectionsService', () {
    // Google's canonical encoded-polyline example, decoding to
    // (38.5,-120.2), (40.7,-120.95), (43.252,-126.453).
    const String encodedPolyline = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

    test('returns decoded points and distance from a successful response',
        () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'routes': [
              {
                'overview_polyline': {'points': encodedPolyline},
                'legs': [
                  {
                    'distance': {'value': 5400, 'text': '5.4 km'},
                  },
                ],
              },
            ],
          }),
          200,
        );
      });
      final service = DirectionsService(httpClient: client, apiKey: 'test-key');

      final RouteResult? result = await service.getRoute(
        origin: const LatLng(-33.9249, 18.4241),
        destination: const LatLng(-33.9581, 18.6961),
      );

      expect(result, isNotNull);
      expect(result!.distanceMeters, equals(5400));
      expect(result.points, hasLength(3));
      expect(result.points.first.latitude, closeTo(38.5, 0.001));
      expect(result.points.first.longitude, closeTo(-120.2, 0.001));

      expect(capturedRequest, isNotNull);
      expect(
        capturedRequest!.url.queryParameters['origin'],
        equals('-33.9249,18.4241'),
      );
      expect(
        capturedRequest!.url.queryParameters['destination'],
        equals('-33.9581,18.6961'),
      );
      expect(capturedRequest!.url.queryParameters['key'], equals('test-key'));
    });

    test('returns null when no API key is configured', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        return http.Response('{}', 200);
      });
      final service = DirectionsService(httpClient: client, apiKey: '');

      final result = await service.getRoute(
        origin: const LatLng(0, 0),
        destination: const LatLng(1, 1),
      );

      expect(result, isNull);
      expect(callCount, equals(0));
    });

    test('returns null on a non-200 response', () async {
      final client = MockClient((request) async => http.Response('', 500));
      final service = DirectionsService(httpClient: client, apiKey: 'test-key');

      final result = await service.getRoute(
        origin: const LatLng(0, 0),
        destination: const LatLng(1, 1),
      );

      expect(result, isNull);
    });

    test('returns null when the API reports a non-OK status', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({'status': 'ZERO_RESULTS', 'routes': []}),
          200,
        ),
      );
      final service = DirectionsService(httpClient: client, apiKey: 'test-key');

      final result = await service.getRoute(
        origin: const LatLng(0, 0),
        destination: const LatLng(1, 1),
      );

      expect(result, isNull);
    });

    test('returns null when the route has no overview polyline', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'status': 'OK',
            'routes': [
              {'legs': []},
            ],
          }),
          200,
        ),
      );
      final service = DirectionsService(httpClient: client, apiKey: 'test-key');

      final result = await service.getRoute(
        origin: const LatLng(0, 0),
        destination: const LatLng(1, 1),
      );

      expect(result, isNull);
    });
  });
}
