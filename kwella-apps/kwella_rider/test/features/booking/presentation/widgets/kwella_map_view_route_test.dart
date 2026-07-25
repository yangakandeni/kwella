import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
