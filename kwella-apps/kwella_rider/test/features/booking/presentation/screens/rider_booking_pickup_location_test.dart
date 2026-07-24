import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/screens/rider_booking_screen.dart';
import 'package:kwella_rider/features/location/services/kwella_location_service.dart';
import 'package:kwella_rider/features/location/services/places_autocomplete_service.dart';

class _FakePlacesAutocompleteService extends PlacesAutocompleteService {
  _FakePlacesAutocompleteService() : super(apiKey: 'test-key');

  @override
  Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    double? originLat,
    double? originLng,
  }) async =>
      const [];
}

class _FakeLocationService extends KwellaLocationService {
  _FakeLocationService() : super.forTesting();

  bool permissionsGranted = true;
  Position? position;
  String? addressLabel;

  @override
  Future<bool> requestLocationPermissions() async => permissionsGranted;

  @override
  Future<Position?> getCurrentPosition() async => position;

  @override
  Future<String?> resolveAddressLabel(double latitude, double longitude) async =>
      addressLabel;
}

Position _makePosition({required double latitude, required double longitude}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    altitude: 0,
    altitudeAccuracy: 0,
    accuracy: 5,
    speed: 0,
    speedAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    timestamp: DateTime.now(),
  );
}

void main() {
  testWidgets(
    'pickup pill shows a loading state, then defaults to the device location',
    (WidgetTester tester) async {
      final fakeService = _FakeLocationService()
        ..position = _makePosition(latitude: -33.9249, longitude: 18.4241)
        ..addressLabel = 'Long Street, Cape Town';
      final controller = KwellaRiderController(locationService: fakeService);

      await tester.pumpWidget(
        MaterialApp(home: RiderBookingScreen(controller: controller)),
      );

      // Before the async lookup resolves, the pill shows a loading label
      // rather than the old static placeholder.
      expect(find.text('Locating you…'), findsOneWidget);
      expect(find.text('Set your pickup point'), findsNothing);

      await tester.pumpAndSettle();

      expect(find.text('Long Street, Cape Town'), findsOneWidget);
      expect(find.text('Locating you…'), findsNothing);

      controller.dispose();
    },
  );

  testWidgets(
    'pickup pill falls back to the manual placeholder when location access is denied',
    (WidgetTester tester) async {
      final fakeService = _FakeLocationService()..permissionsGranted = false;
      final controller = KwellaRiderController(locationService: fakeService);

      await tester.pumpWidget(
        MaterialApp(
          home: RiderBookingScreen(
            controller: controller,
            placesService: _FakePlacesAutocompleteService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Set your pickup point'), findsOneWidget);

      // The rider can still tap through to set a pickup point manually — the
      // destination editor now expands inline rather than navigating away.
      await tester.tap(find.byKey(const Key('pickup_pill')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('from_input')), findsOneWidget);

      controller.dispose();
    },
  );
}
