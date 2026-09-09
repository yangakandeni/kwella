import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';
import 'package:kwella_rider/features/booking/presentation/screens/active_search_screen.dart';
import 'package:kwella_rider/features/booking/presentation/screens/ride_fare_offer_screen.dart';
import 'package:kwella_rider/features/booking/presentation/widgets/kwella_map_view.dart';
import 'package:kwella_rider/features/location/services/directions_service.dart';

const LatLng _pickup = LatLng(-33.9249, 18.4241);
const LatLng _dropoff = LatLng(-33.9581, 18.6961);

/// Returns a 4 km route — chosen so the recommended-fare formula
/// (R25 base + R6.50/km, rounded to the nearest R5) lands on a clean R50.
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
      expect(recommended.data, equals('R50'));
      expect(directionsService.callCount, equals(1));
    });

    testWidgets(
        'defaults the fare offer to the recommended fare once the route resolves',
        (tester) async {
      await pumpScreen(tester);

      final Text offer =
          tester.widget<Text>(find.byKey(const Key('your_offer_value')));
      expect(offer.data, equals('R50'));
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
      expect(offer.data, equals('R55'));
      expect(recommended.data, equals('R50'));
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
  });
}
