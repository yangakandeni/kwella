import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:kwella_driver/features/bidding/presentation/screens/trip_navigation_screen.dart';
import 'package:kwella_driver/features/location/presentation/controllers/kwella_telemetry_controller.dart';

import '../../../../support/fake_kwella_location_service.dart';
import '../../../../support/fake_kwella_websocket_service.dart';

class _FakeDirectionsService extends DirectionsService {
  _FakeDirectionsService() : super(apiKey: 'test-key');

  int callCount = 0;
  RouteResult? nextResult;

  @override
  Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    callCount++;
    return nextResult;
  }
}

void main() {
  late FakeKwellaLocationService locationService;
  late FakeKwellaWebSocketService wsService;
  late KwellaTelemetryController telemetryController;
  late _FakeDirectionsService directionsService;
  late StreamController<Position> positionController;

  setUp(() async {
    locationService = FakeKwellaLocationService();
    wsService = FakeKwellaWebSocketService();
    positionController = StreamController<Position>.broadcast();
    locationService.fakeStream = positionController.stream;
    directionsService = _FakeDirectionsService()
      ..nextResult = const RouteResult(
        points: [LatLng(-33.93, 18.45), LatLng(-33.94, 18.5)],
        distanceMeters: 2400,
      );

    telemetryController = KwellaTelemetryController(
      locationService: locationService,
      wsService: wsService,
    );
    // By the time a driver reaches this screen, tracking (and the WS
    // subscription that hydrates activeOffer) was already started back on
    // BiddingMarketplaceScreen — mirror that instead of relying on this
    // screen to start it itself.
    await telemetryController.startDriverTracking(driverId: 'USR#drv-12345');
  });

  tearDown(() async {
    telemetryController.stopDriverTracking();
    await positionController.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          telemetryControllerProvider.overrideWith(
            (ref) => telemetryController,
          ),
        ],
        child: MaterialApp(
          home: TripNavigationScreen(
            locationService: locationService,
            directionsService: directionsService,
          ),
          routes: {
            '/driver/post-trip': (_) =>
                const Scaffold(body: Text('post-trip')),
          },
        ),
      ),
    );
    // The location-permission handshake inside initState's
    // _startPositionTracking() is async, so the stream listener doesn't
    // attach on the very first frame — a second pump lets that microtask
    // chain finish before a test feeds a position into the broadcast
    // stream (broadcast streams drop events sent before a listener attaches).
    await tester.pump();
    await tester.pump();
  }

  Future<void> emitRideOffer(
    WidgetTester tester, {
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    // Shaped exactly like handler.py's rideOfferAvailable frame.
    wsService.emit({
      'action': 'rideOfferAvailable',
      'tripId': 'TRIP#nav-1',
      'rider_id': 'USR#rider-001',
      'pickup_location': const [-33.9249, 18.4241],
      'dropoff_location': [dropoffLat, dropoffLng],
      'passenger_count': 3,
      'base_fare': '60.00',
      'expires_in_seconds': 15,
    });
    // The WS -> controller -> rebuild -> post-frame route fetch -> setState
    // chain spans a few frame boundaries; pumpAndSettle can't help since
    // nothing schedules a new frame until the post-frame callback's route
    // fetch resolves, so pump explicitly enough times to cover it.
    for (int i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  GoogleMap mapWidget(WidgetTester tester) =>
      tester.widget<GoogleMap>(find.byKey(const Key('trip_navigation_map')));

  testWidgets(
      'renders a real GoogleMap with a driver marker once the position stream emits',
      (tester) async {
    await pumpScreen(tester);

    positionController.add(makeFakePosition(latitude: -33.93, longitude: 18.45));
    await tester.pumpAndSettle();

    final Marker driverMarker = mapWidget(tester)
        .markers
        .singleWhere((m) => m.markerId == const MarkerId('driver'));
    expect(driverMarker.position, equals(const LatLng(-33.93, 18.45)));
  });

  testWidgets('renders the dropoff marker once the active offer carries coordinates',
      (tester) async {
    await pumpScreen(tester);

    await emitRideOffer(tester, dropoffLat: -33.96, dropoffLng: 18.7);

    final Marker dropoffMarker = mapWidget(tester)
        .markers
        .singleWhere((m) => m.markerId == const MarkerId('dropoff'));
    expect(dropoffMarker.position, equals(const LatLng(-33.96, 18.7)));
  });

  testWidgets(
      'fetches and renders the driving route once both driver position and '
      'dropoff coordinates are known, and shows the real remaining distance',
      (tester) async {
    await pumpScreen(tester);

    positionController.add(makeFakePosition(latitude: -33.93, longitude: 18.45));
    await tester.pumpAndSettle();
    await emitRideOffer(tester, dropoffLat: -33.96, dropoffLng: 18.7);

    expect(directionsService.callCount, equals(1));
    final Polyline route = mapWidget(tester)
        .polylines
        .singleWhere((p) => p.polylineId == const PolylineId('route'));
    expect(route.points, equals(directionsService.nextResult!.points));

    final Text distance =
        tester.widget<Text>(find.byKey(const Key('remaining_distance_label')));
    expect(distance.data, equals('2.4 km'));
  });

  testWidgets('only fetches the route once even after further position updates',
      (tester) async {
    await pumpScreen(tester);

    positionController.add(makeFakePosition(latitude: -33.93, longitude: 18.45));
    await tester.pumpAndSettle();
    await emitRideOffer(tester, dropoffLat: -33.96, dropoffLng: 18.7);
    expect(directionsService.callCount, equals(1));

    positionController.add(makeFakePosition(latitude: -33.931, longitude: 18.451));
    await tester.pumpAndSettle();

    expect(directionsService.callCount, equals(1));
  });

  testWidgets(
      'labels the card with the dropoff — this screen is the post-pickup leg '
      '— instead of a hardcoded placeholder', (tester) async {
    await pumpScreen(tester);

    await emitRideOffer(tester, dropoffLat: -33.9581, dropoffLng: 18.6961);

    expect(find.text('📍 Dropoff @ -33.95810, 18.69610'), findsOneWidget);
  });

  testWidgets('cancels the position stream subscription on dispose', (tester) async {
    await pumpScreen(tester);
    expect(positionController.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox());

    expect(positionController.hasListener, isFalse);
  });

  testWidgets('tapping Navigate does not throw once a position is known',
      (tester) async {
    await pumpScreen(tester);
    positionController.add(makeFakePosition(latitude: -33.93, longitude: 18.45));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('navigate_button')));
    await tester.pump();
  });

  testWidgets(
      'sliding to confirm dispatches confirmArrival and navigates to the post-trip screen',
      (tester) async {
    await pumpScreen(tester);

    await tester.drag(
      find.byKey(const Key('slide_to_confirm')),
      const Offset(2000, 0),
    );
    await tester.pumpAndSettle();

    expect(
      wsService.sentMessages.any((m) => m['action'] == 'confirmArrival'),
      isTrue,
    );
    expect(find.text('post-trip'), findsOneWidget);
  });
}
