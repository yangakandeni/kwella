import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:kwella_core/kwella_core.dart';

/// A driving route between two points, as returned by
/// [DirectionsService.getRoute].
///
/// Duplicated from `kwella_rider`'s service of the same name rather than
/// shared via `kwella_core` — no stateful/plugin-backed service has ever
/// been promoted there (the two apps even run separate WebSocket service
/// implementations), so this follows existing precedent rather than being
/// the first cross-app extraction.
class RouteResult {
  const RouteResult({required this.points, required this.distanceMeters});

  /// Decoded path of the route, in drawing order from origin to destination.
  final List<LatLng> points;

  /// Total route distance, used to estimate ETA/remaining distance.
  final int distanceMeters;
}

/// Thin wrapper around the Google Directions (Routes) API. Network/parse
/// failures resolve to `null` rather than propagating.
class DirectionsService {
  DirectionsService({
    http.Client? httpClient,
    String? apiKey,
    KwellaEnvironment? environment,
  })  : _httpClient = httpClient ?? http.Client(),
        _apiKey = apiKey ??
            const String.fromEnvironment('GOOGLE_MAPS_API_KEY'),
        _environment = environment ?? KwellaEnvironment.current;

  static const String _directionsEndpoint =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  /// Requests only the fields the app actually parses, per the Routes API's
  /// mandatory field mask. `routes.duration` is requested per the migration
  /// spec even though [RouteResult] doesn't surface it — nothing in the app
  /// consumes an ETA today.
  static const String _fieldMask =
      'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline';

  final http.Client _httpClient;
  final String _apiKey;
  final KwellaEnvironment _environment;

  /// Fetches the driving route from [origin] to [destination]. Returns
  /// `null` when no API key is configured or the lookup fails for any
  /// reason. When [KwellaEnvironment.isLocal] is true, requests are routed
  /// to the mock orchestrator's `maps/directions` endpoint instead, and no
  /// API key is required.
  Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (!_environment.isLocal && _apiKey.isEmpty) {
      return null;
    }

    try {
      final Uri uri = _environment.isLocal
          ? Uri.parse(_environment.httpApiEndpoint).resolve('maps/directions')
          : Uri.parse(_directionsEndpoint);
      final Map<String, String> headers = {
        'Content-Type': 'application/json',
        'X-Goog-FieldMask': _fieldMask,
        if (!_environment.isLocal) 'X-Goog-Api-Key': _apiKey,
      };
      final String body = jsonEncode({
        'origin': _locationOf(origin),
        'destination': _locationOf(destination),
        'travelMode': 'DRIVE',
      });
      final http.Response response =
          await _httpClient.post(uri, headers: headers, body: body);
      if (response.statusCode != 200) {
        return null;
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final dynamic routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) {
        return null;
      }
      final Map<String, dynamic> route = routes.first as Map<String, dynamic>;

      final dynamic polyline = route['polyline'];
      final String? encodedPolyline = polyline is Map<String, dynamic>
          ? polyline['encodedPolyline'] as String?
          : null;
      if (encodedPolyline == null || encodedPolyline.isEmpty) {
        return null;
      }

      final List<PointLatLng> decodedPolyline =
          PolylinePoints.decodePolyline(encodedPolyline);
      final List<LatLng> points = decodedPolyline
          .map((PointLatLng p) => LatLng(p.latitude, p.longitude))
          .toList();

      final int distanceMeters = (route['distanceMeters'] as num?)?.toInt() ?? 0;

      return RouteResult(points: points, distanceMeters: distanceMeters);
    } catch (e) {
      debugPrint('[DirectionsService] Route lookup failed: $e');
      return null;
    }
  }

  static Map<String, dynamic> _locationOf(LatLng point) => {
        'location': {
          'latLng': {
            'latitude': point.latitude,
            'longitude': point.longitude,
          },
        },
      };
}
