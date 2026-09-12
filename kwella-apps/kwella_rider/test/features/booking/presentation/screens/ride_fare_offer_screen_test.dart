import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';
import 'package:kwella_rider/features/booking/presentation/screens/active_search_screen.dart';
import 'package:kwella_rider/features/booking/presentation/screens/ride_fare_offer_screen.dart';
import 'package:kwella_rider/features/booking/presentation/widgets/kwella_map_view.dart';

const LatLng _pickup = LatLng(-33.9249, 18.4241);
const LatLng _dropoff = LatLng(-33.9581, 18.6961);

/// 12:00 SAST — off peak, daytime. Pinned because the recommended fare now
/// carries peak-hour and night-risk surcharges.
final DateTime _offPeakDaytime = DateTime.utc(2026, 6, 21, 10);

/// The recommended fare these tests assert against.
///
/// Priced off the *haversine* distance between [_pickup] and [_dropoff]
/// (~25.36 km), not the route's `distanceMeters`: the backend only ever sees
/// the four coordinates and prices the straight line between them, so the
/// screen must quote the same measure or the rider is shown a fare the
/// server will refuse to honour. Mirrors
/// `test_fare_calculator.py` with 3 passengers at 12:00 SAST:
///
///   base 30.00 + time 48.70 + distance 190.21 + pax 5.00 = 273.91
///   lifted to the next payable 50c                       = 274.00
///   rounded to the nearest R5 for the +/- controls       = R275
///
/// Nothing is added on top of the subtotal: kwella's 10% is taken from the
/// driver's side of the agreed fare, not added to the rider's quote.
const String _expectedRecommendedFare = 'R275';

/// The fake route's geometry is still used to draw the polyline; its
/// `distanceMeters` is deliberately NOT what the fare is computed from.
class _FakeDirectionsService extends DirectionsService {
  _FakeDirectionsService() : super(apiKey: 'test-key');

  int callCount = 0;

  @override
  Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    callCount++;
    return const RouteResult(
      points: [_pickup, LatLng(-33.94, 18.5), _dropoff],
      distanceMeters: 4000,
    );
  }
}

KwellaRiderController _controllerWithRideDetails() {
  final controller = KwellaRiderController();
  controller.updatePickupLocation(
    '23 West Drive, Khayelitsha, Cape Town, South Africa',
    lat: _pickup.latitude,
    lng: _pickup.longitude,
  );
  controller.updateDropoffLocation(
    'Liberty Promenade, Mitchells Plain, Cape Town, South Africa',
    lat: _dropoff.latitude,
    lng: _dropoff.longitude,
  );
  controller.setPassengerCount(3);
  return controller;
}

void main() {
  late KwellaRiderController controller;
  late _FakeDirectionsService directionsService;

  setUp(() {
    controller = _controllerWithRideDetails();
    directionsService = _FakeDirectionsService();
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RideFareOfferScreen(
          controller: controller,
          directionsService: directionsService,
          clock: () => _offPeakDaytime,
        ),
      ),
    );
    // Let the async route fetch resolve.
    await tester.pump();
    await tester.pump();
  }

  group('Ride details', () {
    testWidgets('displays the shortened pickup location', (tester) async {
      await pumpScreen(tester);

      expect(
        find.text('23 West Drive, Khayelitsha'),
        findsOneWidget,
      );
    });

    testWidgets('displays the destination split into name and area',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('Liberty Promenade'), findsOneWidget);
      expect(find.text('Mitchells Plain'), findsOneWidget);
    });

    testWidgets('displays the passenger count from the booking flow',
        (tester) async {
      await pumpScreen(tester);

      final Text label =
          tester.widget<Text>(find.byKey(const Key('passenger_count_label')));
      expect(label.data, equals('3'));
    });

    testWidgets('displays the recommended fare computed from route distance',
        (tester) async {
      await pumpScreen(tester);

      final Text recommended =
          tester.widget<Text>(find.byKey(const Key('recommended_fare_value')));
      expect(recommended.data, equals(_expectedRecommendedFare));
      expect(directionsService.callCount, equals(1));
    });

    testWidgets(
        'defaults the fare offer to the recommended fare once the route resolves',
        (tester) async {
      await pumpScreen(tester);

      final Text offer =
          tester.widget<Text>(find.byKey(const Key('your_offer_value')));
      expect(offer.data, equals(_expectedRecommendedFare));
    });

    testWidgets('lets the rider adjust their offer independently of the recommendation',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('increase_fare_button')));
      await tester.pump();

      final Text offer =
          tester.widget<Text>(find.byKey(const Key('your_offer_value')));
      final Text recommended =
          tester.widget<Text>(find.byKey(const Key('recommended_fare_value')));
      // One +R5 tap above the recommendation.
      expect(offer.data, equals('R280'));
      expect(recommended.data, equals(_expectedRecommendedFare));
    });
  });

  group('Map', () {
    testWidgets('renders pickup and destination markers', (tester) async {
      await pumpScreen(tester);

      final GoogleMap map =
          tester.widget<GoogleMap>(find.byKey(const Key('kwella_map_view')));
      final Marker pickupMarker =
          map.markers.singleWhere((m) => m.markerId == kPickupMarkerId);
      final Marker dropoffMarker =
          map.markers.singleWhere((m) => m.markerId == kDropoffMarkerId);

      expect(pickupMarker.position, _pickup);
      expect(dropoffMarker.position, _dropoff);
    });

    testWidgets('renders the fetched route as a polyline', (tester) async {
      await pumpScreen(tester);

      final GoogleMap map =
          tester.widget<GoogleMap>(find.byKey(const Key('kwella_map_view')));
      final Polyline route =
          map.polylines.singleWhere((p) => p.polylineId == kRoutePolylineId);

      expect(
        route.points,
        equals(const [_pickup, LatLng(-33.94, 18.5), _dropoff]),
      );
    });

    testWidgets('frames the camera to include both pickup and destination',
        (tester) async {
      await pumpScreen(tester);

      final GoogleMap map =
          tester.widget<GoogleMap>(find.byKey(const Key('kwella_map_view')));
      expect(
        map.initialCameraPosition.target,
        isNot(equals(KwellaMapView.fallbackCenter)),
      );
    });

    testWidgets(
        'dragging the pickup pin updates the pin position and reloads the route',
        (tester) async {
      await pumpScreen(tester);
      expect(directionsService.callCount, equals(1));

      GoogleMap map =
          tester.widget<GoogleMap>(find.byKey(const Key('kwella_map_view')));
      final Marker pickupMarker =
          map.markers.singleWhere((m) => m.markerId == kPickupMarkerId);
      const LatLng dropped = LatLng(-33.93, 18.44);
      pickupMarker.onDragEnd!(dropped);
      await tester.pumpAndSettle();

      map = tester.widget<GoogleMap>(find.byKey(const Key('kwella_map_view')));
      final Marker movedPickupMarker =
          map.markers.singleWhere((m) => m.markerId == kPickupMarkerId);
      expect(movedPickupMarker.position, equals(dropped));
      expect(controller.state.pickupLat, equals(dropped.latitude));
      expect(controller.state.pickupLng, equals(dropped.longitude));
      // _loadRoute() re-ran against the new pickup coordinate.
      expect(directionsService.callCount, equals(2));
    });
  });

  group('Regression', () {
    testWidgets(
        'passenger count, pickup, and destination survive fare adjustments',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('increase_fare_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('decrease_fare_button')));
      await tester.pump();

      expect(find.text('23 West Drive, Khayelitsha'), findsOneWidget);
      expect(find.text('Liberty Promenade'), findsOneWidget);
      expect(find.text('Mitchells Plain'), findsOneWidget);
      final Text passengers =
          tester.widget<Text>(find.byKey(const Key('passenger_count_label')));
      expect(passengers.data, equals('3'));
    });

    testWidgets(
        'tapping Find Drivers requests the trip and navigates to the active search screen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RideFareOfferScreen(
                        controller: controller,
                        directionsService: directionsService,
                        clock: () => _offPeakDaytime,
                      ),
                    ),
                  ),
                  child: const Text('Open fare offer'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open fare offer'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('find_drivers_button')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('find_drivers_button')));
      await tester.tap(find.byKey(const Key('find_drivers_button')));
      // Not pumpAndSettle: ActiveSearchScreen's "Finding drivers…" row has
      // an indeterminate CircularProgressIndicator, which never settles.
      await tester.pump();
      await tester.pump();

      expect(controller.state.status, equals(RiderTripStatus.searching));
      expect(find.byType(ActiveSearchScreen), findsOneWidget);
      expect(find.byKey(const Key('active_search_offer_value')), findsOneWidget);
    });

    testWidgets(
        'Find Drivers carries the rider offer into the active search sheet '
        'before any server frame arrives',
        (tester) async {
      // Regression: `_findDrivers` used to drop `_offeredFare` on the floor,
      // so ActiveSearchScreen rendered `state.offeredFare ?? 0` => "R0"
      // until (or unless) a TripBroadcast frame turned up.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RideFareOfferScreen(
                        controller: controller,
                        directionsService: directionsService,
                        clock: () => _offPeakDaytime,
                      ),
                    ),
                  ),
                  child: const Text('Open fare offer'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open fare offer'));
      await tester.pumpAndSettle();

      // The fake route puts the rider's offer at R300; bump it twice so
      // the asserted value can only have come from this screen's own state.
      await tester.ensureVisible(find.byKey(const Key('increase_fare_button')));
      await tester.tap(find.byKey(const Key('increase_fare_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('increase_fare_button')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('your_offer_value'))).data,
        equals('R285'),
      );

      await tester.ensureVisible(find.byKey(const Key('find_drivers_button')));
      await tester.tap(find.byKey(const Key('find_drivers_button')));
      await tester.pump();
      await tester.pump();

      // Seeded optimistically by requestTrip(offeredFare: ...) — no
      // TripBroadcast has been simulated at this point.
      expect(controller.state.offeredFare, equals(285.0));
      expect(find.byType(ActiveSearchScreen), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('active_search_offer_value')))
            .data,
        equals('R285'),
      );
    });
  });
}
