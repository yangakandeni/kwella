import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';
import 'package:kwella_rider/features/booking/presentation/screens/rider_booking_screen.dart';
import 'package:kwella_rider/features/booking/presentation/widgets/destination_editor_panel.dart';
import 'package:kwella_rider/features/location/services/places_autocomplete_service.dart';

class _FakePlacesAutocompleteService extends PlacesAutocompleteService {
  _FakePlacesAutocompleteService() : super(apiKey: 'test-key');

  List<PlaceSuggestion> nextResults = const [];

  @override
  Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    double? originLat,
    double? originLng,
  }) async => nextResults;
}

void main() {
  testWidgets(
    'idle state shows the collapsed search sheet, without pickup/dropoff inputs',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();

      await tester.pumpWidget(
        MaterialApp(home: RiderBookingScreen(controller: controller)),
      );

      expect(find.byKey(const Key('search_bar')), findsOneWidget);
      expect(find.byKey(const Key('pickup_input')), findsNothing);
      expect(find.byKey(const Key('dropoff_input')), findsNothing);
      expect(find.byKey(const Key('profile_avatar')), findsNothing);
      expect(find.text('Set your destination to get started'), findsNothing);

      controller.dispose();
    },
  );

  testWidgets(
    'tapping the search bar expands the destination editor inline, without pushing a new route',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();

      await tester.pumpWidget(
        MaterialApp(
          home: RiderBookingScreen(
            controller: controller,
            placesService: _FakePlacesAutocompleteService(),
          ),
        ),
      );

      expect(find.byKey(const Key('from_input')), findsNothing);

      await tester.tap(find.byKey(const Key('search_bar')));
      await tester.pumpAndSettle();

      // Same screen, same Scaffold — just an in-place expansion.
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byKey(const Key('from_input')), findsOneWidget);
      expect(find.byKey(const Key('to_input')), findsOneWidget);
      expect(find.byKey(const Key('search_bar')), findsNothing);

      controller.dispose();
    },
  );

  testWidgets(
    'tapping a quick destination expands the panel with it pre-filled',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();

      await tester.pumpWidget(
        MaterialApp(
          home: RiderBookingScreen(
            controller: controller,
            placesService: _FakePlacesAutocompleteService(),
          ),
        ),
      );

      await tester.tap(find.text('Zevenwacht Mall'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('to_input')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('to_input')))
            .controller!
            .text,
        equals('Zevenwacht Mall'),
      );
      expect(controller.state.dropoffLocation, equals('Zevenwacht Mall'));

      controller.dispose();
    },
  );

  testWidgets(
    'closing the expanded panel preserves edits made to the pickup location',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();

      await tester.pumpWidget(
        MaterialApp(
          home: RiderBookingScreen(
            controller: controller,
            placesService: _FakePlacesAutocompleteService(),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('search_bar')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('from_input')),
        'Updated Pickup Rd',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('close_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('from_input')), findsNothing);
      expect(find.byKey(const Key('search_bar')), findsOneWidget);
      expect(controller.state.pickupLocation, equals('Updated Pickup Rd'));

      controller.dispose();
    },
  );

  testWidgets('tapping the scrim outside the panel collapses it back', (
    WidgetTester tester,
  ) async {
    final controller = KwellaRiderController();

    await tester.pumpWidget(
      MaterialApp(
        home: RiderBookingScreen(
          controller: controller,
          placesService: _FakePlacesAutocompleteService(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('search_bar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('destination_panel_scrim')), findsOneWidget);

    // Tap a point in the dimmed area above the expanded panel rather than
    // the widget's geometric center, which the tall panel itself covers.
    await tester.tapAt(const Offset(700, 20));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('from_input')), findsNothing);
    expect(find.byKey(const Key('search_bar')), findsOneWidget);

    controller.dispose();
  });

  testWidgets(
    'inline destination panel height stays fixed once expanded, even as suggestions appear',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();
      final placesService = _FakePlacesAutocompleteService()
        ..nextResults = const [
          PlaceSuggestion(
            placeId: 'place-1',
            description: 'Shoprite Mandalay, Swartklip Road, Cape Town',
            mainText: 'Shoprite Mandalay',
            secondaryText: 'Swartklip Road, Cape Town',
          ),
        ];

      await tester.pumpWidget(
        MaterialApp(
          home: RiderBookingScreen(
            controller: controller,
            placesService: placesService,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('search_bar')));
      await tester.pumpAndSettle();

      final Size expandedSize = tester.getSize(
        find.byType(DestinationEditorPanel),
      );

      await tester.enterText(find.byKey(const Key('to_input')), 'Shoprite');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Shoprite Mandalay'), findsOneWidget);
      expect(tester.getSize(find.byType(DestinationEditorPanel)), expandedSize);

      await tester.enterText(find.byKey(const Key('to_input')), '');
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.getSize(find.byType(DestinationEditorPanel)), expandedSize);

      controller.dispose();
    },
  );

  testWidgets(
    'once a trip is active, the pickup/dropoff editor and passenger selector become visible and interactive',
    (WidgetTester tester) async {
      final controller = KwellaRiderController();
      controller.handleIncomingWebSocketEvent({
        'action': 'tripMatchConfirmed',
        'tripId': 'trip-001',
      });

      await tester.pumpWidget(
        MaterialApp(home: RiderBookingScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pickup_input')), findsOneWidget);
      expect(find.byKey(const Key('dropoff_input')), findsOneWidget);
      expect(find.byKey(const Key('passenger_1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('passenger_4')));
      await tester.pumpAndSettle();
      expect(controller.state.passengerCount, equals(4));

      await tester.tap(find.byKey(const Key('request_ride_button')));
      await tester.pumpAndSettle();
      expect(controller.state.status, equals(RiderTripStatus.searching));

      controller.dispose();
    },
  );
}
