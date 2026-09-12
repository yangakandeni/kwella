import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kwella_core/kwella_core.dart';

const KwellaEnvironment _localEnv = KwellaEnvironment(
  httpApiEndpoint: 'http://10.0.2.2:8790/',
  isLocal: true,
);

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
            'routes': [
              {
                'distanceMeters': 5400,
                'duration': '540s',
                'polyline': {'encodedPolyline': encodedPolyline},
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
      expect(capturedRequest!.method, equals('POST'));
      expect(capturedRequest!.url.toString(),
          equals('https://routes.googleapis.com/directions/v2:computeRoutes'));
      expect(
        capturedRequest!.headers['X-Goog-FieldMask'],
        equals(
          'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
        ),
      );
      expect(capturedRequest!.headers['X-Goog-Api-Key'], equals('test-key'));

      final Map<String, dynamic> body = jsonDecode(capturedRequest!.body);
      expect(
        body['origin']['location']['latLng'],
        equals({'latitude': -33.9249, 'longitude': 18.4241}),
      );
      expect(
        body['destination']['location']['latLng'],
        equals({'latitude': -33.9581, 'longitude': 18.6961}),
      );
      expect(body['travelMode'], equals('DRIVE'));
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

    test('returns null when the response has no routes', () async {
      final client = MockClient(
        (request) async => http.Response(jsonEncode({'routes': []}), 200),
      );
      final service = DirectionsService(httpClient: client, apiKey: 'test-key');

      final result = await service.getRoute(
        origin: const LatLng(0, 0),
        destination: const LatLng(1, 1),
      );

      expect(result, isNull);
    });

    test('returns null when the route has no polyline', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'routes': [
              {'distanceMeters': 100},
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

    test(
        'in local mode, routes to the mock orchestrator maps/directions '
        'endpoint without an API key header, even with no API key configured',
        () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'routes': [
              {
                'distanceMeters': 5400,
                'duration': '540s',
                'polyline': {'encodedPolyline': encodedPolyline},
              },
            ],
          }),
          200,
        );
      });
      final service = DirectionsService(
        httpClient: client,
        environment: _localEnv,
      );

      final RouteResult? result = await service.getRoute(
        origin: const LatLng(-33.9249, 18.4241),
        destination: const LatLng(-33.9581, 18.6961),
      );

      expect(result, isNotNull);
      expect(result!.distanceMeters, equals(5400));

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.method, equals('POST'));
      expect(capturedRequest!.url.host, equals('10.0.2.2'));
      expect(capturedRequest!.url.path, equals('/maps/directions'));
      expect(
        capturedRequest!.headers.containsKey('X-Goog-Api-Key'),
        isFalse,
      );

      final Map<String, dynamic> body = jsonDecode(capturedRequest!.body);
      expect(
        body['origin']['location']['latLng'],
        equals({'latitude': -33.9249, 'longitude': 18.4241}),
      );
      expect(
        body['destination']['location']['latLng'],
        equals({'latitude': -33.9581, 'longitude': 18.6961}),
      );
    });
  });
}
