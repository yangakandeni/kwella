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
  });

  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;
}

/// Thin wrapper around the Google Places Autocomplete API. Mirrors
/// `KwellaLocationService`'s "never throws" contract — network/parse
/// failures resolve to an empty suggestion list rather than propagating.
class PlacesAutocompleteService {
  PlacesAutocompleteService({http.Client? httpClient, String? apiKey})
      : _httpClient = httpClient ?? http.Client(),
        _apiKey = apiKey ?? dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';

  static const int _minQueryLength = 3;
  static const String _endpoint =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';

  final http.Client _httpClient;
  final String _apiKey;

  /// Returns matching destination suggestions for [query]. Returns an empty
  /// list (without making a network call) when the query is shorter than
  /// three characters or no API key is configured.
  Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final String trimmed = query.trim();
    if (trimmed.length < _minQueryLength || _apiKey.isEmpty) {
      return const [];
    }

    try {
      final Uri uri = Uri.parse(_endpoint).replace(queryParameters: {
        'input': trimmed,
        'key': _apiKey,
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

      return predictions
          .whereType<Map<String, dynamic>>()
          .map(_parsePrediction)
          .whereType<PlaceSuggestion>()
          .toList();
    } catch (e) {
      debugPrint('[PlacesAutocompleteService] Autocomplete lookup failed: $e');
      return const [];
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

    return PlaceSuggestion(
      placeId: placeId,
      description: description,
      mainText: mainText,
      secondaryText: secondaryText,
    );
  }
}
