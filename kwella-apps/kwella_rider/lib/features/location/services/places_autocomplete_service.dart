import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// A single Google Places Autocomplete prediction.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
    this.distanceMeters,
    this.lat,
    this.lng,
  });

  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  /// Straight-line distance from the search origin, when one was supplied to
  /// [PlacesAutocompleteService.searchPlaces]. Null otherwise.
  final int? distanceMeters;

  /// Known coordinates for this suggestion, when already resolved (e.g. a
  /// previous destination). Null for fresh Places Autocomplete predictions,
  /// which only carry a [placeId] until [PlacesAutocompleteService.getPlaceDetails]
  /// resolves them.
  final double? lat;
  final double? lng;
}

/// Lat/lng of a resolved place, returned by
/// [PlacesAutocompleteService.getPlaceDetails].
class PlaceLocation {
  const PlaceLocation({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

/// Thin wrapper around the Google Places Autocomplete and Place Details
/// APIs. Mirrors `KwellaLocationService`'s "never throws" contract —
/// network/parse failures resolve to an empty list / null rather than
/// propagating.
class PlacesAutocompleteService {
  PlacesAutocompleteService({http.Client? httpClient, String? apiKey})
      : _httpClient = httpClient ?? http.Client(),
        _apiKey = apiKey ?? dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';

  static const int _minQueryLength = 3;
  static const String _autocompleteEndpoint =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const String _detailsEndpoint =
      'https://maps.googleapis.com/maps/api/place/details/json';

  /// Soft location bias radius (metres) applied when an origin is supplied —
  /// wide enough to still surface city-wide matches, per the "Shoprite"
  /// example in the product brief, while keeping nearby results first.
  static const int _biasRadiusMeters = 50000;

  final http.Client _httpClient;
  final String _apiKey;

  /// Returns matching place suggestions for [query]. Returns an empty list
  /// (without making a network call) when the query is shorter than three
  /// characters or no API key is configured.
  ///
  /// When [originLat]/[originLng] are supplied, results are biased toward
  /// that coordinate and annotated with [PlaceSuggestion.distanceMeters],
  /// then sorted nearest-first.
  Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    double? originLat,
    double? originLng,
  }) async {
    final String trimmed = query.trim();
    if (trimmed.length < _minQueryLength || _apiKey.isEmpty) {
      return const [];
    }

    try {
      final bool hasOrigin = originLat != null && originLng != null;
      final Uri uri =
          Uri.parse(_autocompleteEndpoint).replace(queryParameters: {
        'input': trimmed,
        'key': _apiKey,
        if (hasOrigin) 'location': '$originLat,$originLng',
        if (hasOrigin) 'radius': '$_biasRadiusMeters',
        if (hasOrigin) 'origin': '$originLat,$originLng',
      });
      final http.Response response = await _httpClient.get(uri);
      if (response.statusCode != 200) {
        return const [];
      }

      final dynamic body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['status'] != 'OK') {
        return const [];
      }

      final dynamic predictions = body['predictions'];
      if (predictions is! List) {
        return const [];
      }

      final List<PlaceSuggestion> results = predictions
          .whereType<Map<String, dynamic>>()
          .map(_parsePrediction)
          .whereType<PlaceSuggestion>()
          .toList();

      results.sort((a, b) {
        final int? da = a.distanceMeters;
        final int? db = b.distanceMeters;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
      return results;
    } catch (e) {
      debugPrint('[PlacesAutocompleteService] Autocomplete lookup failed: $e');
      return const [];
    }
  }

  /// Resolves the lat/lng of a place picked from [searchPlaces]. Returns null
  /// on any network/parse failure rather than throwing.
  Future<PlaceLocation?> getPlaceDetails(String placeId) async {
    if (placeId.isEmpty || _apiKey.isEmpty) {
      return null;
    }

    try {
      final Uri uri = Uri.parse(_detailsEndpoint).replace(queryParameters: {
        'place_id': placeId,
        'fields': 'geometry',
        'key': _apiKey,
      });
      final http.Response response = await _httpClient.get(uri);
      if (response.statusCode != 200) {
        return null;
      }

      final dynamic body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['status'] != 'OK') {
        return null;
      }

      final dynamic result = body['result'];
      final dynamic geometry = result is Map<String, dynamic>
          ? result['geometry']
          : null;
      final dynamic location =
          geometry is Map<String, dynamic> ? geometry['location'] : null;
      if (location is! Map<String, dynamic>) {
        return null;
      }

      final dynamic lat = location['lat'];
      final dynamic lng = location['lng'];
      if (lat is num && lng is num) {
        return PlaceLocation(lat: lat.toDouble(), lng: lng.toDouble());
      }
      return null;
    } catch (e) {
      debugPrint('[PlacesAutocompleteService] Place details lookup failed: $e');
      return null;
    }
  }

  PlaceSuggestion? _parsePrediction(Map<String, dynamic> prediction) {
    final String? placeId = prediction['place_id'] as String?;
    final String? description = prediction['description'] as String?;
    if (placeId == null || description == null) {
      return null;
    }

    final Map<String, dynamic>? structuredFormatting =
        prediction['structured_formatting'] as Map<String, dynamic>?;
    final String mainText =
        structuredFormatting?['main_text'] as String? ?? description;
    final String secondaryText =
        structuredFormatting?['secondary_text'] as String? ?? '';
    final dynamic distanceMeters = prediction['distance_meters'];

    return PlaceSuggestion(
      placeId: placeId,
      description: description,
      mainText: mainText,
      secondaryText: secondaryText,
      distanceMeters: distanceMeters is num ? distanceMeters.toInt() : null,
    );
  }
}
