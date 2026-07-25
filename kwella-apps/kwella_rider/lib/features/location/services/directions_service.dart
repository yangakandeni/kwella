import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// A driving route between two points, as returned by
/// [DirectionsService.getRoute].
class RouteResult {
  const RouteResult({required this.points, required this.distanceMeters});

  /// Decoded path of the route, in drawing order from origin to destination.
  final List<LatLng> points;

  /// Total route distance, used to estimate a recommended fare.
  final int distanceMeters;
}

/// Thin wrapper around the Google Directions API. Mirrors
/// [PlacesAutocompleteService]'s "never throws" contract — network/parse
/// failures resolve to `null` rather than propagating.
class DirectionsService {
  DirectionsService({http.Client? httpClient, String? apiKey})
      : _httpClient = httpClient ?? http.Client(),
        _apiKey = apiKey ?? dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';

  static const String _directionsEndpoint =
      'https://maps.googleapis.com/maps/api/directions/json';

  final http.Client _httpClient;
  final String _apiKey;

  /// Fetches the driving route from [origin] to [destination]. Returns
  /// `null` when no API key is configured or the lookup fails for any
  /// reason.
  Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (_apiKey.isEmpty) {
      return null;
    }

    try {
      final Uri uri = Uri.parse(_directionsEndpoint).replace(
        queryParameters: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'key': _apiKey,
        },
      );
      final http.Response response = await _httpClient.get(uri);
      if (response.statusCode != 200) {
        return null;
      }

      final dynamic body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['status'] != 'OK') {
        return null;
      }

      final dynamic routes = body['routes'];
      if (routes is! List || routes.isEmpty) {
        return null;
      }
      final Map<String, dynamic> route = routes.first as Map<String, dynamic>;

      final dynamic overviewPolyline = route['overview_polyline'];
      final String? encodedPolyline = overviewPolyline is Map<String, dynamic>
          ? overviewPolyline['points'] as String?
          : null;
      if (encodedPolyline == null || encodedPolyline.isEmpty) {
        return null;
      }

      final List<PointLatLng> decoded =
          PolylinePoints.decodePolyline(encodedPolyline);
      final List<LatLng> points = decoded
          .map((PointLatLng p) => LatLng(p.latitude, p.longitude))
          .toList();

      int distanceMeters = 0;
      final dynamic legs = route['legs'];
      if (legs is List && legs.isNotEmpty) {
        final Map<String, dynamic> leg = legs.first as Map<String, dynamic>;
        final dynamic distance = leg['distance'];
        if (distance is Map<String, dynamic>) {
          distanceMeters = (distance['value'] as num?)?.toInt() ?? 0;
        }
      }

      return RouteResult(points: points, distanceMeters: distanceMeters);
    } catch (e) {
      debugPrint('[DirectionsService] Route lookup failed: $e');
      return null;
    }
  }
}
