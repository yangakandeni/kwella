import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/screens/destination_selection_screen.dart';
import 'package:kwella_rider/features/booking/presentation/widgets/destination_editor_panel.dart';
import 'package:kwella_rider/features/location/services/places_autocomplete_service.dart';

class _FakePlacesAutocompleteService extends PlacesAutocompleteService {
  _FakePlacesAutocompleteService() : super(apiKey: 'test-key');

  List<PlaceSuggestion> nextResults = const [];
  PlaceLocation? nextPlaceLocation;
  final List<String> queries = [];
  final List<double?> queriedOriginLats = [];
  final List<double?> queriedOriginLngs = [];
  final List<String> detailsRequestedFor = [];

  /// When set, [searchPlaces] awaits this instead of resolving immediately,
  /// so tests can deterministically observe the in-flight loading state.
  Completer<void>? pendingSearch;

  @override
  Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    double? originLat,
    double? originLng,
  }) async {
    queries.add(query);
    queriedOriginLats.add(originLat);
    queriedOriginLngs.add(originLng);
    if (pendingSearch != null) {
      await pendingSearch!.future;
    }
    return nextResults;
  }

  @override
  Future<PlaceLocation?> getPlaceDetails(String placeId) async {
    detailsRequestedFor.add(placeId);
    return nextPlaceLocation;
  }
}

const _shopriteSuggestions = [
  PlaceSuggestion(
    placeId: 'place-1',
    description: 'Shoprite Mandalay, Swartklip Road, Cape Town',
    mainText: 'Shoprite Mandalay',
    secondaryText: 'Swartklip Road, Cape Town',
  ),
  PlaceSuggestion(
    placeId: 'place-2',
    description: 'Shoprite Lentegeur, Melkbos Road, Cape Town',
    mainText: 'Shoprite Lentegeur',
    secondaryText: 'Melkbos Road, Cape Town',
  ),
];

Future<void> pumpScreen(
  WidgetTester tester, {
  required KwellaRiderController controller,
  required PlacesAutocompleteService placesService,
  String? initialDropoff,
}) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        routes: {
          '/rider/fare-offer': (_) =>
              const Scaffold(body: Text('Fare Offer Screen')),
        },
        home: DestinationSelectionScreen(
          controller: controller,
          placesService: placesService,
          initialDropoff: initialDropoff,
        ),
      ),
    ),
  );
}

void main() {
  late KwellaRiderController controller;
  late _FakePlacesAutocompleteService placesService;

  setUp(() {
    controller = KwellaRiderController();
    placesService = _FakePlacesAutocompleteService();
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets('pre-fills the From field with the current pickup location', (
    tester,
  ) async {
    controller.updatePickupLocation('Tennyson St 31');

    await pumpScreen(
      tester,
      controller: controller,
      placesService: placesService,
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('from_input')))
          .controller!
          .text,
      equals('Tennyson St 31'),
    );
  });

  testWidgets('pre-fills the To field when an initial destination is passed', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      controller: controller,
      placesService: placesService,
      initialDropoff: 'Shoprite Mandalay',
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('to_input')))
          .controller!
          .text,
      equals('Shoprite Mandalay'),
    );
    expect(controller.state.dropoffLocation, equals('Shoprite Mandalay'));
  });

  testWidgets('does not query suggestions for fewer than 3 characters', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      controller: controller,
      placesService: placesService,
    );

    await tester.enterText(find.byKey(const Key('to_input')), 'Sh');
    await tester.pump(const Duration(milliseconds: 400));

    expect(placesService.queries, isEmpty);
    expect(find.byKey(const Key('destination_suggestions_list')), findsNothing);
  });

  testWidgets(
    'shows suggestions after 3+ characters and selecting one fills the To field',
    (tester) async {
      placesService.nextResults = _shopriteSuggestions;
      await pumpScreen(
        tester,
        controller: controller,
        placesService: placesService,
      );

      await tester.enterText(find.byKey(const Key('to_input')), 'Shoprite');
      await tester.pump(const Duration(milliseconds: 400));

      expect(placesService.queries, contains('Shoprite'));
      expect(find.text('Shoprite Mandalay'), findsOneWidget);
      expect(find.text('Shoprite Lentegeur'), findsOneWidget);

      await tester.tap(find.text('Shoprite Mandalay'));
      await tester.pump();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('to_input')))
            .controller!
            .text,
        equals('Shoprite Mandalay, Swartklip Road, Cape Town'),
      );
      expect(
        controller.state.dropoffLocation,
        equals('Shoprite Mandalay, Swartklip Road, Cape Town'),
      );
      expect(find.text('Shoprite Lentegeur'), findsNothing);
    },
  );

  testWidgets(
    'shows suggestions for the From field and resolves coordinates on selection',
    (tester) async {
      placesService.nextResults = _shopriteSuggestions;
      placesService.nextPlaceLocation = const PlaceLocation(
        lat: -33.97,
        lng: 18.63,
      );
      await pumpScreen(
        tester,
        controller: controller,
        placesService: placesService,
      );

      await tester.enterText(find.byKey(const Key('from_input')), 'Shoprite');
      await tester.pump(const Duration(milliseconds: 400));

      expect(placesService.queries, contains('Shoprite'));
      expect(find.text('Shoprite Mandalay'), findsOneWidget);

      await tester.tap(find.text('Shoprite Mandalay'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('from_input')))
            .controller!
            .text,
        equals('Shoprite Mandalay, Swartklip Road, Cape Town'),
      );
      expect(placesService.detailsRequestedFor, contains('place-1'));
      expect(controller.state.pickupLat, equals(-33.97));
      expect(controller.state.pickupLng, equals(18.63));
    },
  );

  testWidgets(
    'biases destination searches toward the resolved pickup coordinates',
    (tester) async {
      controller.updatePickupLocation('Long Street', lat: -33.92, lng: 18.42);
      await pumpScreen(
        tester,
        controller: controller,
        placesService: placesService,
      );

      await tester.enterText(find.byKey(const Key('to_input')), 'Shoprite');
      await tester.pump(const Duration(milliseconds: 400));

      expect(placesService.queriedOriginLats, contains(-33.92));
      expect(placesService.queriedOriginLngs, contains(18.42));
    },
  );

  testWidgets('shows a loading indicator while suggestions are being fetched', (
    tester,
  ) async {
    final pending = Completer<void>();
    placesService.pendingSearch = pending;
    placesService.nextResults = _shopriteSuggestions;
    await pumpScreen(
      tester,
      controller: controller,
      placesService: placesService,
    );

    await tester.enterText(find.byKey(const Key('to_input')), 'Shoprite');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('suggestions_loading')), findsOneWidget);
    expect(find.byKey(const Key('destination_suggestions_list')), findsNothing);

    pending.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('suggestions_loading')), findsNothing);
    expect(find.text('Shoprite Mandalay'), findsOneWidget);
  });

  testWidgets('shows a friendly empty state when no places match the query', (
    tester,
  ) async {
    placesService.nextResults = const [];
    await pumpScreen(
      tester,
      controller: controller,
      placesService: placesService,
    );

    await tester.enterText(find.byKey(const Key('to_input')), 'Zzzzzzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byKey(const Key('suggestions_empty_state')), findsOneWidget);
    expect(find.textContaining('No matching locations'), findsOneWidget);
  });

  testWidgets('passenger stepper defaults to 1 and clamps between 1 and 6', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      controller: controller,
      placesService: placesService,
    );

    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('passenger_decrement')));
    await tester.pump();
    expect(controller.state.passengerCount, equals(1));

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('passenger_increment')));
      await tester.pump();
    }
    expect(controller.state.passengerCount, equals(6));

    await tester.tap(find.byKey(const Key('passenger_increment')));
    await tester.pump();
    expect(controller.state.passengerCount, equals(6));
  });

  testWidgets('close button pops the screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: Text('Home'))),
      ),
    );

    // Push the destination screen on top of a real navigator stack so
    // popping it is observable.
    final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
    navigatorState.push(
      MaterialPageRoute(
        builder: (_) => DestinationSelectionScreen(
          controller: controller,
          placesService: placesService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('to_input')), findsOneWidget);

    await tester.tap(find.byKey(const Key('close_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('to_input')), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets(
    'panel height stays fixed as suggestions load, populate, empty out, and clear',
    (tester) async {
      final pending = Completer<void>();
      placesService.pendingSearch = pending;
      placesService.nextResults = _shopriteSuggestions;
      await pumpScreen(
        tester,
        controller: controller,
        placesService: placesService,
      );

      final Size initialSize = tester.getSize(
        find.byType(DestinationEditorPanel),
      );

      // Typing enough to trigger a search (loading state) must not resize
      // the panel.
      await tester.enterText(find.byKey(const Key('to_input')), 'Shop');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('suggestions_loading')), findsOneWidget);
      expect(tester.getSize(find.byType(DestinationEditorPanel)), initialSize);

      // Results arriving must not resize the panel either.
      pending.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Shoprite Mandalay'), findsOneWidget);
      expect(tester.getSize(find.byType(DestinationEditorPanel)), initialSize);

      // An empty-result search keeps the same fixed height.
      placesService.nextResults = const [];
      await tester.enterText(find.byKey(const Key('to_input')), 'Zzzzzzz');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('suggestions_empty_state')), findsOneWidget);
      expect(tester.getSize(find.byType(DestinationEditorPanel)), initialSize);

      // Clearing the field back to empty must keep the panel expanded at the
      // same height rather than collapsing back toward the passenger
      // selector.
      await tester.enterText(find.byKey(const Key('to_input')), '');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('suggestions_empty_state')), findsNothing);
      expect(
        find.byKey(const Key('destination_suggestions_list')),
        findsNothing,
      );
      expect(tester.getSize(find.byType(DestinationEditorPanel)), initialSize);
    },
  );

  testWidgets(
    'continue button is disabled until both fields are set, then opens the fare offer screen',
    (tester) async {
      await pumpScreen(
        tester,
        controller: controller,
        placesService: placesService,
      );

      final continueButtonFinder = find.byKey(const Key('continue_button'));
      ElevatedButton continueButton() =>
          tester.widget<ElevatedButton>(continueButtonFinder);

      expect(continueButton().onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('from_input')),
        'Tennyson St 31',
      );
      await tester.enterText(
        find.byKey(const Key('to_input')),
        'Shoprite Mandalay',
      );
      await tester.pump();

      expect(continueButton().onPressed, isNotNull);

      await tester.tap(continueButtonFinder);
      await tester.pumpAndSettle();

      expect(find.text('Fare Offer Screen'), findsOneWidget);
    },
  );
}
