import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/booking/presentation/widgets/autocomplete_suggestions_list.dart';
import 'package:kwella_rider/features/location/services/places_autocomplete_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AutocompleteSuggestionsList is tested here entirely on its own — it takes
// no passenger/booking state at all, so there is no way for these tests (or
// the widget itself) to touch a passenger selector. That structural
// isolation is what prevents the "suggestions replace the whole panel"
// regression from recurring: this widget can only ever render its own
// loading/empty/populated states.
// ─────────────────────────────────────────────────────────────────────────────

const _suggestions = [
  PlaceSuggestion(
    placeId: 'place-1',
    description: 'Shoprite Mandalay, Swartklip Road, Cape Town, South Africa',
    mainText: 'Shoprite Mandalay',
    secondaryText: 'Swartklip Road, Cape Town, South Africa',
  ),
  PlaceSuggestion(
    placeId: 'place-2',
    description: 'Shoprite Lentegeur, Melkbos Road, Cape Town',
    mainText: 'Shoprite Lentegeur',
    secondaryText: 'Melkbos Road, Cape Town',
  ),
];

Future<void> pumpList(
  WidgetTester tester, {
  bool isLoading = false,
  List<PlaceSuggestion> suggestions = const [],
  String lastSearchedQuery = '',
  ValueChanged<PlaceSuggestion>? onSelect,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: AutocompleteSuggestionsList(
            isLoading: isLoading,
            suggestions: suggestions,
            lastSearchedQuery: lastSearchedQuery,
            onSelect: onSelect ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders nothing before any search has run', (tester) async {
    await pumpList(tester);

    expect(find.byKey(const Key('suggestions_loading')), findsNothing);
    expect(find.byKey(const Key('suggestions_empty_state')), findsNothing);
    expect(find.byKey(const Key('destination_suggestions_list')), findsNothing);
  });

  testWidgets('shows a loading indicator while a search is in flight', (
    tester,
  ) async {
    await pumpList(tester, isLoading: true);

    expect(find.byKey(const Key('suggestions_loading')), findsOneWidget);
    expect(find.byKey(const Key('destination_suggestions_list')), findsNothing);
  });

  testWidgets('shows a friendly empty state when a search returns no matches', (
    tester,
  ) async {
    await pumpList(tester, lastSearchedQuery: 'Zzzzzzz');

    expect(find.byKey(const Key('suggestions_empty_state')), findsOneWidget);
    expect(find.textContaining('No matching locations'), findsOneWidget);
  });

  testWidgets(
    'renders every suggestion, scrollable, with a Cape Town-formatted secondary line',
    (tester) async {
      await pumpList(
        tester,
        suggestions: _suggestions,
        lastSearchedQuery: 'Shoprite',
      );

      expect(find.byKey(const Key('destination_suggestions_list')), findsOneWidget);
      expect(find.text('Shoprite Mandalay'), findsOneWidget);
      expect(find.text('Shoprite Lentegeur'), findsOneWidget);

      // "Cape Town" / "South Africa" are stripped from the secondary line —
      // every result is local, so they add clutter, not information.
      expect(find.text('Swartklip Road'), findsOneWidget);
      expect(find.text('Melkbos Road'), findsOneWidget);
      expect(find.text('Swartklip Road, Cape Town, South Africa'), findsNothing);
    },
  );

  testWidgets('tapping a suggestion invokes onSelect with that suggestion', (
    tester,
  ) async {
    PlaceSuggestion? selected;
    await pumpList(
      tester,
      suggestions: _suggestions,
      lastSearchedQuery: 'Shoprite',
      onSelect: (s) => selected = s,
    );

    await tester.tap(find.byKey(const Key('suggestion_place-1')));
    await tester.pump();

    expect(selected?.placeId, equals('place-1'));
  });
}
