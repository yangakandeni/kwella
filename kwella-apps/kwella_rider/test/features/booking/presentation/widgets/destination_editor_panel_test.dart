import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';
import 'package:kwella_rider/features/booking/presentation/widgets/destination_editor_panel.dart';
import 'package:kwella_rider/features/location/services/places_autocomplete_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Regression coverage for: autocomplete suggestions appearing used to hide
// the passenger count selector (it lived in the same reserved slot as the
// suggestions list, and search activation permanently swapped one for the
// other). The panel now renders the suggestions list and the passenger
// selector as separate, always-present siblings, so every test group below
// asserts the passenger selector survives each stage of the search flow.
// ─────────────────────────────────────────────────────────────────────────────

class _FakePlacesAutocompleteService extends PlacesAutocompleteService {
  _FakePlacesAutocompleteService() : super(apiKey: 'test-key');

  List<PlaceSuggestion> nextResults = const [];
  Completer<void>? pendingSearch;

  @override
  Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    double? originLat,
    double? originLng,
  }) async {
    if (pendingSearch != null) {
      await pendingSearch!.future;
    }
    return nextResults;
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

Future<void> pumpPanel(
  WidgetTester tester, {
  required KwellaRiderController controller,
  required PlacesAutocompleteService placesService,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StreamBuilder<RiderTripState>(
          stream: controller.stateStream,
          initialData: controller.state,
          builder: (context, snapshot) {
            return DestinationEditorPanel(
              controller: controller,
              state: snapshot.data ?? controller.state,
              onClose: () {},
              placesService: placesService,
            );
          },
        ),
      ),
    ),
  );
}

/// The three controls the fix guarantees survive every autocomplete state.
void expectCoreControlsVisible() {
  expect(find.byKey(const Key('from_input')), findsOneWidget);
  expect(find.byKey(const Key('to_input')), findsOneWidget);
  expect(find.byKey(const Key('passenger_selector_section')), findsOneWidget);
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

  group('opening the panel —', () {
    testWidgets(
      'shows the pickup field, destination field, and passenger selector',
      (tester) async {
        await pumpPanel(
          tester,
          controller: controller,
          placesService: placesService,
        );

        expectCoreControlsVisible();
        expect(find.text('1'), findsOneWidget); // default passenger count
        expect(find.byKey(const Key('destination_suggestions_list')), findsNothing);
      },
    );
  });

  group('autocomplete interaction —', () {
    testWidgets(
      'a loading search does not hide the passenger selector or the fields',
      (tester) async {
        final pending = Completer<void>();
        placesService.pendingSearch = pending;
        placesService.nextResults = _shopriteSuggestions;

        await pumpPanel(
          tester,
          controller: controller,
          placesService: placesService,
        );

        await tester.enterText(find.byKey(const Key('to_input')), 'Shoprite');
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byKey(const Key('suggestions_loading')), findsOneWidget);
        expectCoreControlsVisible();

        pending.complete();
        await tester.pump();
        await tester.pump();
      },
    );

    testWidgets(
      'populated suggestions do not hide the passenger selector, the panel size, or the fields',
      (tester) async {
        placesService.nextResults = _shopriteSuggestions;
        await pumpPanel(
          tester,
          controller: controller,
          placesService: placesService,
        );

        final Size sizeBeforeSearch = tester.getSize(
          find.byType(DestinationEditorPanel),
        );

        await tester.enterText(find.byKey(const Key('to_input')), 'Shoprite');
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byKey(const Key('destination_suggestions_list')), findsOneWidget);
        expect(find.text('Shoprite Mandalay'), findsOneWidget);
        expect(find.text('Shoprite Lentegeur'), findsOneWidget);

        // The regression this guards against: suggestions appearing must
        // never remove, hide, or replace the passenger selector or fields.
        expectCoreControlsVisible();
        expect(
          tester.getSize(find.byType(DestinationEditorPanel)),
          sizeBeforeSearch,
        );
      },
    );

    testWidgets(
      'an empty result set does not hide the passenger selector or the fields',
      (tester) async {
        placesService.nextResults = const [];
        await pumpPanel(
          tester,
          controller: controller,
          placesService: placesService,
        );

        await tester.enterText(find.byKey(const Key('to_input')), 'Zzzzzzz');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        expect(find.byKey(const Key('suggestions_empty_state')), findsOneWidget);
        expectCoreControlsVisible();
      },
    );
  });

  group('clearing search —', () {
    testWidgets(
      'suggestions disappear, the passenger selector stays, and the panel size is unchanged',
      (tester) async {
        placesService.nextResults = _shopriteSuggestions;
        await pumpPanel(
          tester,
          controller: controller,
          placesService: placesService,
        );

        final Size sizeBeforeSearch = tester.getSize(
          find.byType(DestinationEditorPanel),
        );

        await tester.enterText(find.byKey(const Key('to_input')), 'Shoprite');
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const Key('destination_suggestions_list')), findsOneWidget);

        await tester.enterText(find.byKey(const Key('to_input')), '');
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byKey(const Key('destination_suggestions_list')), findsNothing);
        expect(find.byKey(const Key('suggestions_empty_state')), findsNothing);
        expectCoreControlsVisible();
        expect(
          tester.getSize(find.byType(DestinationEditorPanel)),
          sizeBeforeSearch,
        );
      },
    );
  });

  group('selecting a destination —', () {
    testWidgets(
      'fills the destination field and keeps the passenger selector visible',
      (tester) async {
        placesService.nextResults = _shopriteSuggestions;
        await pumpPanel(
          tester,
          controller: controller,
          placesService: placesService,
        );

        await tester.enterText(find.byKey(const Key('to_input')), 'Shoprite');
        await tester.pump(const Duration(milliseconds: 400));

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
        expect(find.byKey(const Key('destination_suggestions_list')), findsNothing);
        expectCoreControlsVisible();
      },
    );
  });

  group('passenger selector —', () {
    testWidgets('defaults to 1 and clamps between 1 and 6', (tester) async {
      await pumpPanel(
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

    testWidgets(
      'remains visible and interactive while destination suggestions are showing',
      (tester) async {
        placesService.nextResults = _shopriteSuggestions;
        await pumpPanel(
          tester,
          controller: controller,
          placesService: placesService,
        );

        await tester.enterText(find.byKey(const Key('to_input')), 'Shoprite');
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byKey(const Key('destination_suggestions_list')), findsOneWidget);

        await tester.tap(find.byKey(const Key('passenger_increment')));
        await tester.pump();

        expect(controller.state.passengerCount, equals(2));
        expect(find.byKey(const Key('passenger_selector_section')), findsOneWidget);
      },
    );
  });
}
