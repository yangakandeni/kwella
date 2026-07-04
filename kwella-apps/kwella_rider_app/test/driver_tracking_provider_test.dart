import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:kwella_rider_app/src/features/tracking/driver_tracking_notifier.dart';

void main() {
  group('DriverTrackingNotifier Unit Tests', () {
    late ProviderContainer container;
    late StreamController<KwellaBiddingEvent> mockStreamController;

    setUp(() {
      mockStreamController = StreamController<KwellaBiddingEvent>.broadcast();
      container = ProviderContainer(
        overrides: [
          kwellaEventMultiplexerProvider.overrideWith((ref) {
            return mockStreamController.stream;
          }),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      mockStreamController.close();
    });

    test('initial state is inactive with no coordinates', () {
      final state = container.read(driverTrackingProvider);
      expect(state.isActive, isFalse);
      expect(state.anchorLatitude, isNull);
      expect(state.anchorLongitude, isNull);
    });

    test('first telemetry batch activates tracking and sets the anchor', () async {
      container.read(driverTrackingProvider.notifier);

      mockStreamController.add(DriverLocationUpdateEvent([
        TelemetryPoint(
          latitude: -33.9249,
          longitude: 18.4241,
          speed: 42.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        ),
      ]));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(driverTrackingProvider);
      expect(state.isActive, isTrue);
      expect(state.latitude, equals(-33.9249));
      expect(state.longitude, equals(18.4241));
      expect(state.speed, equals(42.0));
      expect(state.anchorLatitude, equals(-33.9249));
      expect(state.anchorLongitude, equals(18.4241));
    });

    test('second fix derives a bearing without moving the anchor', () async {
      container.read(driverTrackingProvider.notifier);

      mockStreamController.add(DriverLocationUpdateEvent([
        TelemetryPoint(
          latitude: -33.9249,
          longitude: 18.4241,
          speed: 10.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        ),
      ]));
      await Future<void>.delayed(Duration.zero);

      mockStreamController.add(DriverLocationUpdateEvent([
        TelemetryPoint(
          latitude: -33.9239,
          longitude: 18.4241,
          speed: 15.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(4000, isUtc: true),
        ),
      ]));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(driverTrackingProvider);
      expect(state.latitude, equals(-33.9239));
      // Moving due north (increasing latitude) should yield a ~0° bearing.
      expect(state.bearing, closeTo(0.0, 0.5));
      expect(state.anchorLatitude, equals(-33.9249));
      expect(state.anchorLongitude, equals(18.4241));
    });

    test('non-telemetry events are ignored', () async {
      container.read(driverTrackingProvider.notifier);

      mockStreamController.add(const RideCancelledEvent(rideId: 'ride_1'));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(driverTrackingProvider);
      expect(state.isActive, isFalse);
    });

    test('reset clears tracking back to its initial state', () async {
      container.read(driverTrackingProvider.notifier);

      mockStreamController.add(DriverLocationUpdateEvent([
        TelemetryPoint(
          latitude: -33.9249,
          longitude: 18.4241,
          speed: 42.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        ),
      ]));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(driverTrackingProvider).isActive, isTrue);

      container.read(driverTrackingProvider.notifier).reset();

      final state = container.read(driverTrackingProvider);
      expect(state.isActive, isFalse);
      expect(state.anchorLatitude, isNull);
    });
  });
}
