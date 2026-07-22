import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kwella_rider/features/booking/presentation/controllers/kwella_rider_controller.dart';
import 'package:kwella_rider/features/booking/presentation/screens/rider_booking_screen.dart';
import 'package:kwella_rider/features/booking/presentation/widgets/kwella_map_view.dart';

/// Reads the marker set currently passed to the real GoogleMap widget —
/// KwellaMapView renders a driver Marker rather than a Key'd widget, so
/// tests inspect the GoogleMap's `markers` property directly.
Set<Marker> _mapMarkers(WidgetTester tester) =>
    tester.widget<GoogleMap>(find.byKey(const Key('kwella_map_view'))).markers;

void main() {
  late KwellaRiderController controller;

  setUp(() {
    controller = KwellaRiderController();
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets(
    'live driver location updates render the tracking marker without layout exceptions',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kwellaRiderControllerProvider.overrideWithValue(controller),
          ],
          child: const MaterialApp(home: RiderBookingScreen()),
        ),
      );

      expect(find.byKey(const Key('kwella_map_view')), findsOneWidget);
      expect(_mapMarkers(tester), isEmpty);

      controller.handleIncomingWebSocketEvent({
        'action': 'tripMatchConfirmed',
        'tripId': 'trip-001',
      });
      controller.handleIncomingWebSocketEvent({
        'action': 'liveDriverLocation',
        'latitude': -34.0123,
        'longitude': 18.6123,
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));

      final Marker firstMarker = _mapMarkers(tester).singleWhere(
        (m) => m.markerId == kDriverMarkerId,
      );
      expect(firstMarker.position, const LatLng(-34.0123, 18.6123));
      expect(
        find.textContaining('Tracking driver at -34.0123, 18.6123'),
        findsOneWidget,
      );

      controller.handleIncomingWebSocketEvent({
        'action': 'liveDriverLocation',
        'latitude': -34.0100,
        'longitude': 18.6200,
      });

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));

      expect(
        find.textContaining('Tracking driver at -34.0100, 18.6200'),
        findsOneWidget,
      );
      final Marker secondMarker = _mapMarkers(tester).singleWhere(
        (m) => m.markerId == kDriverMarkerId,
      );
      expect(secondMarker.position, const LatLng(-34.0100, 18.6200));
    },
  );

  testWidgets(
    'arrival banner renders instantly when geofence ARRIVED event occurs',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kwellaRiderControllerProvider.overrideWithValue(controller),
          ],
          child: const MaterialApp(home: RiderBookingScreen()),
        ),
      );

      controller.handleIncomingWebSocketEvent({
        'action': 'tripMatchConfirmed',
        'tripId': 'trip-002',
      });
      controller.handleIncomingWebSocketEvent({
        'action': 'geofenceTrigger',
        'geofence_status': 'ARRIVED',
      });

      await tester.pump();

      expect(
        find.text('Your driver has arrived! Meet them at the pickup point.'),
        findsOneWidget,
      );
    },
  );
}
