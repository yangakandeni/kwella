import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/rider_trip_state.dart';
import 'package:kwella_rider/features/booking/presentation/widgets/kwella_map_view.dart';

GoogleMap _mapWidget(WidgetTester tester) =>
    tester.widget<GoogleMap>(find.byKey(const Key('kwella_map_view')));

void main() {
  const LatLng pickup = LatLng(-33.9249, 18.4241);
  const LatLng dropoff = LatLng(-33.9581, 18.6961);

  group('KwellaMapView route mode', () {
    testWidgets('renders pickup and destination markers at the given positions',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KwellaMapView(pickupLocation: pickup, dropoffLocation: dropoff),
          ),
        ),
      );

      final Set<Marker> markers = _mapWidget(tester).markers;
      final Marker pickupMarker =
          markers.singleWhere((m) => m.markerId == kPickupMarkerId);
      final Marker dropoffMarker =
          markers.singleWhere((m) => m.markerId == kDropoffMarkerId);

      expect(pickupMarker.position, pickup);
      expect(dropoffMarker.position, dropoff);
    });

    testWidgets('renders the route polyline using the supplied route points',
        (WidgetTester tester) async {
      const List<LatLng> route = [
        pickup,
        LatLng(-33.94, 18.5),
        dropoff,
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KwellaMapView(
              pickupLocation: pickup,
              dropoffLocation: dropoff,
              routePoints: route,
            ),
          ),
        ),
      );

      final Set<Polyline> polylines = _mapWidget(tester).polylines;
      final Polyline routeLine =
          polylines.singleWhere((p) => p.polylineId == kRoutePolylineId);
      expect(routeLine.points, equals(route));
    });

    testWidgets(
        'falls back to a straight line between pickup and dropoff when no '
        'route points are supplied',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KwellaMapView(pickupLocation: pickup, dropoffLocation: dropoff),
          ),
        ),
      );

      final Set<Polyline> polylines = _mapWidget(tester).polylines;
      final Polyline routeLine =
          polylines.singleWhere((p) => p.polylineId == kRoutePolylineId);
      expect(routeLine.points, equals([pickup, dropoff]));
    });

    testWidgets('camera frames both pickup and dropoff on the initial position',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KwellaMapView(pickupLocation: pickup, dropoffLocation: dropoff),
          ),
        ),
      );

      final CameraPosition camera = _mapWidget(tester).initialCameraPosition;
      // The frame should center between the two points, not sit on either
      // endpoint or the unrelated fallback (Cape Town CBD) center.
      expect(camera.target.latitude, closeTo((pickup.latitude + dropoff.latitude) / 2, 0.0001));
      expect(camera.target.longitude, closeTo((pickup.longitude + dropoff.longitude) / 2, 0.0001));
      expect(camera.target, isNot(equals(KwellaMapView.fallbackCenter)));
    });

    testWidgets('hides the recenter (device-location) button in route mode',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KwellaMapView(pickupLocation: pickup, dropoffLocation: dropoff),
          ),
        ),
      );

      expect(find.byKey(const Key('recenter_button')), findsNothing);
    });

    testWidgets(
        'without a route, no pickup/dropoff markers or polyline are rendered '
        '(existing driver-tracking behaviour is preserved)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: KwellaMapView()),
        ),
      );

      expect(_mapWidget(tester).markers, isEmpty);
      expect(_mapWidget(tester).polylines, isEmpty);
      expect(find.byKey(const Key('recenter_button')), findsOneWidget);
      expect(
        _mapWidget(tester).initialCameraPosition.target,
        equals(KwellaMapView.fallbackCenter),
      );
    });
  });

  group('KwellaMapView draggable pickup/dropoff pins', () {
    testWidgets('pickup and dropoff markers are draggable; driver/nearby markers are not',
        (WidgetTester tester) async {
      const Map<String, DriverLocation> nearbyDrivers = {
        'driver-idle-1': DriverLocation(latitude: -33.91, longitude: 18.42),
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KwellaMapView(
              pickupLocation: pickup,
              dropoffLocation: dropoff,
              driverLocation: DriverLocation(latitude: -33.93, longitude: 18.45),
              nearbyDrivers: nearbyDrivers,
            ),
          ),
        ),
      );

      final Set<Marker> markers = _mapWidget(tester).markers;
      final Marker pickupMarker =
          markers.singleWhere((m) => m.markerId == kPickupMarkerId);
      final Marker dropoffMarker =
          markers.singleWhere((m) => m.markerId == kDropoffMarkerId);
      final Marker driverMarker =
          markers.singleWhere((m) => m.markerId == kDriverMarkerId);
      final Marker nearbyMarker = markers
          .singleWhere((m) => m.markerId == const MarkerId('nearby_driver-idle-1'));

      expect(pickupMarker.draggable, isTrue);
      expect(dropoffMarker.draggable, isTrue);
      expect(driverMarker.draggable, isFalse);
      expect(nearbyMarker.draggable, isFalse);
    });

    testWidgets('dragging the pickup pin invokes onPickupDragEnd with the dropped position',
        (WidgetTester tester) async {
      LatLng? dragged;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KwellaMapView(
              pickupLocation: pickup,
              dropoffLocation: dropoff,
              onPickupDragEnd: (LatLng position) => dragged = position,
            ),
          ),
        ),
      );

      final Marker pickupMarker = _mapWidget(tester)
          .markers
          .singleWhere((m) => m.markerId == kPickupMarkerId);
      const LatLng dropped = LatLng(-33.93, 18.44);
      pickupMarker.onDragEnd!(dropped);

      expect(dragged, equals(dropped));
    });

    testWidgets('dragging the dropoff pin invokes onDropoffDragEnd with the dropped position',
        (WidgetTester tester) async {
      LatLng? dragged;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KwellaMapView(
              pickupLocation: pickup,
              dropoffLocation: dropoff,
              onDropoffDragEnd: (LatLng position) => dragged = position,
            ),
          ),
        ),
      );

      final Marker dropoffMarker = _mapWidget(tester)
          .markers
          .singleWhere((m) => m.markerId == kDropoffMarkerId);
      const LatLng dropped = LatLng(-33.96, 18.7);
      dropoffMarker.onDragEnd!(dropped);

      expect(dragged, equals(dropped));
    });

    testWidgets(
        'pickup/dropoff markers start on the default hue icon and swap to the '
        'custom brand-colored bitmap once it finishes loading asynchronously',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KwellaMapView(pickupLocation: pickup, dropoffLocation: dropoff),
          ),
        ),
      );

      // Before the async icon-drawing future resolves, the widget must
      // still render a usable (default) icon — never blank, never a crash.
      // `BitmapDescriptor` has no `==` override, so compare via `toJson()`
      // (its wire representation) rather than object identity.
      final Object defaultGreenJson =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
              .toJson();
      final Object defaultRedJson =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)
              .toJson();
      final Marker initialPickupMarker = _mapWidget(tester)
          .markers
          .singleWhere((m) => m.markerId == kPickupMarkerId);
      expect(initialPickupMarker.icon.toJson(), equals(defaultGreenJson));

      await tester.pumpAndSettle();

      final Marker loadedPickupMarker = _mapWidget(tester)
          .markers
          .singleWhere((m) => m.markerId == kPickupMarkerId);
      final Marker loadedDropoffMarker = _mapWidget(tester)
          .markers
          .singleWhere((m) => m.markerId == kDropoffMarkerId);
      expect(loadedPickupMarker.icon.toJson(), isNot(equals(defaultGreenJson)));
      expect(loadedDropoffMarker.icon.toJson(), isNot(equals(defaultRedJson)));
    });
  });

  group('KwellaMapView nearby drivers', () {
    testWidgets(
        'renders a marker for each nearby driver at its given coordinates',
        (WidgetTester tester) async {
      const Map<String, DriverLocation> nearbyDrivers = {
        'driver-idle-1': DriverLocation(latitude: -33.91, longitude: 18.42),
        'driver-idle-2': DriverLocation(latitude: -33.95, longitude: 18.44),
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KwellaMapView(nearbyDrivers: nearbyDrivers),
          ),
        ),
      );

      final Set<Marker> markers = _mapWidget(tester).markers;
      final Marker driver1Marker = markers
          .singleWhere((m) => m.markerId == const MarkerId('nearby_driver-idle-1'));
      final Marker driver2Marker = markers
          .singleWhere((m) => m.markerId == const MarkerId('nearby_driver-idle-2'));

      expect(driver1Marker.position, const LatLng(-33.91, 18.42));
      expect(driver2Marker.position, const LatLng(-33.95, 18.44));
    });
  });

  group('KwellaMapView.cameraForBounds', () {
    test('zooms out as the bounding span widens', () {
      final CameraPosition tight = KwellaMapView.cameraForBounds(const [
        LatLng(-33.9249, 18.4241),
        LatLng(-33.9260, 18.4250),
      ]);
      final CameraPosition wide = KwellaMapView.cameraForBounds(const [
        LatLng(-33.9249, 18.4241),
        LatLng(-34.5, 19.5),
      ]);

      expect(tight.zoom, greaterThan(wide.zoom));
    });

    test('centers on the midpoint of the given points', () {
      final CameraPosition camera = KwellaMapView.cameraForBounds(const [
        LatLng(-33.0, 18.0),
        LatLng(-34.0, 19.0),
      ]);

      expect(camera.target, equals(const LatLng(-33.5, 18.5)));
    });
  });
}
