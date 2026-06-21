import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:kwella_mobile/features/location/services/kwella_location_service.dart';
import 'package:kwella_mobile/features/bidding/services/kwella_websocket_service.dart';
import 'package:kwella_mobile/features/location/presentation/controllers/kwella_telemetry_controller.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Subclasses KwellaLocationService and overrides @protected hooks so no
/// hardware or OS calls are made. Mirrors the pattern established in
/// kwella_location_service_test.dart.
class _FakeLocationService extends KwellaLocationService {
  _FakeLocationService() : super.forTesting();

  bool serviceEnabled = true;
  LocationPermission startingPermission = LocationPermission.always;

  /// Injected stream returned by [getPositionStream].
  Stream<Position> fakeStream = const Stream<Position>.empty();

  @override
  Future<bool> checkServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => startingPermission;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  LocationSettings buildLocationSettings() => const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        timeLimit: Duration(seconds: 5),
      );

  @override
  Stream<Position> getPositionStream(LocationSettings settings) => fakeStream;
}

/// A minimal [WebSocketSink] stub that records every `add()` call into a
/// list. No actual I/O takes place.
class _CapturingSink implements WebSocketSink {
  final List<String> captured = [];

  @override
  void add(dynamic data) {
    if (data is String) captured.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> get done async {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.drain<void>();
}

/// Subclasses [KwellaWebSocketService] so the capturing sink is injected
/// without touching any network layer.
class _FakeWebSocketService extends KwellaWebSocketService {
  _FakeWebSocketService() : super.forTesting();

  final _CapturingSink _fakeSink = _CapturingSink();

  List<String> get capturedPayloads => _fakeSink.captured;

  @override
  WebSocketSink get sink => _fakeSink;

  @override
  bool get isConnected => true;
}

// ---------------------------------------------------------------------------
// Helper: build a synthetic Position frame without the hardware stack.
// ---------------------------------------------------------------------------
Position _makePosition({
  required double latitude,
  required double longitude,
  double heading = 0,
  double speed = 0,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    altitude: 0,
    altitudeAccuracy: 0,
    accuracy: 5,
    speed: speed,
    speedAccuracy: 0,
    heading: heading,
    headingAccuracy: 0,
    timestamp: DateTime.now(),
  );
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  late _FakeLocationService locationService;
  late _FakeWebSocketService wsService;
  late KwellaTelemetryController controller;

  setUp(() {
    locationService = _FakeLocationService();
    wsService = _FakeWebSocketService();
    controller = KwellaTelemetryController(
      locationService: locationService,
      wsService: wsService,
    );
  });

  tearDown(() {
    controller.stopDriverTracking();
  });

  // ---- Core dispatch -------------------------------------------------------

  group('startDriverTracking — telemetry dispatch —', () {
    test(
      'pushes a correctly structured updateLocation JSON payload for each '
      'position frame emitted by the hardware stream',
      () async {
        // Arrange: inject two mock GPS frames.
        final frame1 = _makePosition(
          latitude: -33.9249,
          longitude: 18.4241,
          heading: 180.0,
          speed: 11.5,
        );
        final frame2 = _makePosition(
          latitude: -33.9270,
          longitude: 18.4255,
          heading: 175.0,
          speed: 13.0,
        );
        locationService.fakeStream = Stream.fromIterable([frame1, frame2]);

        // Act.
        await controller.startDriverTracking(driverId: 'USR#drv-12345');

        // Allow the stream to drain fully.
        await Future<void>.delayed(Duration.zero);

        // Assert: two payloads were captured on the sink.
        final payloads = wsService.capturedPayloads;
        expect(payloads.length, equals(2));

        // Decode and validate the first frame.
        final decoded1 = jsonDecode(payloads[0]) as Map<String, dynamic>;
        expect(decoded1['action'], equals('updateLocation'));
        expect(decoded1['driverId'], equals('USR#drv-12345'));
        expect(decoded1['latitude'], closeTo(-33.9249, 0.0001));
        expect(decoded1['longitude'], closeTo(18.4241, 0.0001));
        expect(decoded1['heading'], closeTo(180.0, 0.001));
        expect(decoded1['speed'], closeTo(11.5, 0.001));

        // Decode and validate the second frame.
        final decoded2 = jsonDecode(payloads[1]) as Map<String, dynamic>;
        expect(decoded2['action'], equals('updateLocation'));
        expect(decoded2['driverId'], equals('USR#drv-12345'));
        expect(decoded2['latitude'], closeTo(-33.9270, 0.0001));
        expect(decoded2['longitude'], closeTo(18.4255, 0.0001));
        expect(decoded2['heading'], closeTo(175.0, 0.001));
        expect(decoded2['speed'], closeTo(13.0, 0.001));
      },
    );

    test(
      'dispatches payload with all required JSON keys present',
      () async {
        locationService.fakeStream = Stream.fromIterable([
          _makePosition(
            latitude: -26.2041,
            longitude: 28.0473,
            heading: 90.0,
            speed: 8.3,
          ),
        ]);

        await controller.startDriverTracking(driverId: 'USR#drv-99999');
        await Future<void>.delayed(Duration.zero);

        final decoded =
            jsonDecode(wsService.capturedPayloads.first) as Map<String, dynamic>;

        // Every key mandated by the AWS route schema must be present.
        expect(decoded.containsKey('action'), isTrue);
        expect(decoded.containsKey('driverId'), isTrue);
        expect(decoded.containsKey('latitude'), isTrue);
        expect(decoded.containsKey('longitude'), isTrue);
        expect(decoded.containsKey('heading'), isTrue);
        expect(decoded.containsKey('speed'), isTrue);
      },
    );
  });

  // ---- Permission gate -----------------------------------------------------

  group('startDriverTracking — permission guard —', () {
    test(
      'does not start tracking when location permissions are denied',
      () async {
        locationService.serviceEnabled = true;
        locationService.startingPermission = LocationPermission.denied;
        // Override requestPermission to return denied permanently.
        // We cannot override here directly; use a custom subclass approach.

        // Use a service that always denies.
        final denyingLocation = _DenyingLocationService();
        final isolatedController = KwellaTelemetryController(
          locationService: denyingLocation,
          wsService: wsService,
        );

        await isolatedController.startDriverTracking(driverId: 'USR#drv-0');

        expect(isolatedController.isTracking, isFalse);
        expect(wsService.capturedPayloads, isEmpty);
      },
    );
  });

  // ---- Idempotent start ----------------------------------------------------

  group('startDriverTracking — idempotency —', () {
    test(
      'is a no-op when called while already tracking',
      () async {
        // Set up a stream that never completes so tracking stays active.
        final controller1 = StreamController<Position>();
        locationService.fakeStream = controller1.stream;

        await controller.startDriverTracking(driverId: 'USR#drv-12345');
        expect(controller.isTracking, isTrue);

        // Second call should be silently ignored — no assertion error.
        await controller.startDriverTracking(driverId: 'USR#drv-12345');
        expect(controller.isTracking, isTrue);

        controller1.close();
      },
    );
  });

  // ---- Safe teardown -------------------------------------------------------

  group('stopDriverTracking —', () {
    test(
      'cancels the stream subscription and sets isTracking to false',
      () async {
        final streamController = StreamController<Position>();
        locationService.fakeStream = streamController.stream;

        await controller.startDriverTracking(driverId: 'USR#drv-12345');
        expect(controller.isTracking, isTrue);

        controller.stopDriverTracking();

        expect(controller.isTracking, isFalse);

        // No more frames should be dispatched after stop.
        streamController.add(
          _makePosition(latitude: -1.0, longitude: 2.0),
        );
        await Future<void>.delayed(Duration.zero);

        expect(wsService.capturedPayloads, isEmpty);
        await streamController.close();
      },
    );

    test('is safe to call when tracking is not active', () {
      // Must not throw.
      expect(() => controller.stopDriverTracking(), returnsNormally);
    });
  });
}

// ---------------------------------------------------------------------------
// Helper doubles for specific edge-case tests
// ---------------------------------------------------------------------------

/// A [KwellaLocationService] stub that always denies permissions.
class _DenyingLocationService extends KwellaLocationService {
  _DenyingLocationService() : super.forTesting();

  @override
  Future<bool> checkServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.deniedForever;

  @override
  LocationSettings buildLocationSettings() =>
      const LocationSettings(accuracy: LocationAccuracy.high);

  @override
  Stream<Position> getPositionStream(LocationSettings settings) =>
      const Stream<Position>.empty();
}
