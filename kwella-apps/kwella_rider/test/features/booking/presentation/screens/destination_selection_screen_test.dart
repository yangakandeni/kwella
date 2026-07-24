import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/screens/destination_selection_screen.dart';
import 'package:kwella_rider/features/location/services/places_autocomplete_service.dart';

class _FakePlacesAutocompleteService extends PlacesAutocompleteService {
  _FakePlacesAutocompleteService() : super(apiKey: 'test-key');

  List<PlaceSuggestion> nextResults = const [];
  final List<String> queries = [];

  @override
  Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    queries.add(query);
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

  testWidgets('pre-fills the From field with the current pickup location',
      (tester) async {
    controller.updatePickupLocation('Tennyson St 31');

    await pumpScreen(tester, controller: controller, placesService: placesService);

    expect(
      tester.widget<TextField>(find.byKey(const Key('from_input'))).controller!.text,
      equals('Tennyson St 31'),
    );
  });

  testWidgets('pre-fills the To field when an initial destination is passed',
      (tester) async {
    await pumpScreen(
      tester,
      controller: controller,
      placesService: placesService,
      initialDropoff: 'Shoprite Mandalay',
    );

    expect(
      tester.widget<TextField>(find.byKey(const Key('to_input'))).controller!.text,
      equals('Shoprite Mandalay'),
    );
    expect(controller.state.dropoffLocation, equals('Shoprite Mandalay'));
  });

  testWidgets('does not query suggestions for fewer than 3 characters',
      (tester) async {
    await pumpScreen(tester, controller: controller, placesService: placesService);

    await tester.enterText(find.byKey(const Key('to_input')), 'Sh');
    await tester.pump(const Duration(milliseconds: 400));

    expect(placesService.queries, isEmpty);
    expect(find.byKey(const Key('destination_suggestions_list')), findsNothing);
  });

  testWidgets(
      'shows suggestions after 3+ characters and selecting one fills the To field',
      (tester) async {
    placesService.nextResults = _shopriteSuggestions;
    await pumpScreen(tester, controller: controller, placesService: placesService);

    await tester.enterText(find.byKey(const Key('to_input')), 'Shoprite');
    await tester.pump(const Duration(milliseconds: 400));

    expect(placesService.queries, contains('Shoprite'));
    expect(find.text('Shoprite Mandalay'), findsOneWidget);
    expect(find.text('Shoprite Lentegeur'), findsOneWidget);

    await tester.tap(find.text('Shoprite Mandalay'));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byKey(const Key('to_input'))).controller!.text,
      equals('Shoprite Mandalay, Swartklip Road, Cape Town'),
    );
    expect(
      controller.state.dropoffLocation,
      equals('Shoprite Mandalay, Swartklip Road, Cape Town'),
    );
    expect(find.text('Shoprite Lentegeur'), findsNothing);
  });

  testWidgets('passenger stepper defaults to 1 and clamps between 1 and 6',
      (tester) async {
    await pumpScreen(tester, controller: controller, placesService: placesService);

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
        child: MaterialApp(
          home: Scaffold(body: Text('Home')),
        ),
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
      'continue button is disabled until both fields are set, then opens the fare offer screen',
      (tester) async {
    await pumpScreen(tester, controller: controller, placesService: placesService);

    final continueButtonFinder = find.byKey(const Key('continue_button'));
    ElevatedButton continueButton() =>
        tester.widget<ElevatedButton>(continueButtonFinder);

    expect(continueButton().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('from_input')), 'Tennyson St 31');
    await tester.enterText(find.byKey(const Key('to_input')), 'Shoprite Mandalay');
    await tester.pump();

    expect(continueButton().onPressed, isNotNull);

    await tester.tap(continueButtonFinder);
    await tester.pumpAndSettle();

    expect(find.text('Fare Offer Screen'), findsOneWidget);
  });
}
