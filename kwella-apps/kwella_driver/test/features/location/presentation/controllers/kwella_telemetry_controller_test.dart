import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:kwella_driver/features/location/services/kwella_location_service.dart';
import 'package:kwella_driver/features/bidding/services/kwella_websocket_service.dart';
import 'package:kwella_driver/features/location/presentation/controllers/kwella_telemetry_controller.dart';

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
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  bool _connected = true;
  bool connectCalled = false;

  List<String> get capturedPayloads => _fakeSink.captured;

  void feedMessage(Map<String, dynamic> message) {
    _controller.add(message);
  }

  @override
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  @override
  Stream<Map<String, dynamic>> get bidStream => _controller.stream;

  @override
  WebSocketSink get sink => _fakeSink;

  @override
  bool get isConnected => _connected;

  @override
  void connect() {
    connectCalled = true;
    _connected = true;
  }

  void close() {
    _controller.close();
  }
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
// Helper: build a well-formed rideOfferAvailable payload map.
// ---------------------------------------------------------------------------
Map<String, dynamic> _makeRideOfferPayload({
  String tripId = 'TRIP#test-001',
  String pickupLocation = 'Cape Town CBD',
  String dropoffLocation = 'V&A Waterfront',
  double baseFare = 45.50,
  DateTime? expiresAt,
}) {
  final expiry =
      expiresAt ?? DateTime.now().toUtc().add(const Duration(seconds: 15));
  return {
    'action': 'rideOfferAvailable',
    'tripId': tripId,
    'pickupLocation': pickupLocation,
    'dropoffLocation': dropoffLocation,
    'baseFare': baseFare,
    'expiresAt': expiry.toIso8601String(),
  };
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
    wsService.close();
  });

  // ---- Core dispatch -------------------------------------------------------

  group('startDriverTracking — telemetry dispatch —', () {
    test('pushes a correctly structured updateLocation JSON payload for each '
        'position frame emitted by the hardware stream', () async {
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
    });

    test('dispatches payload with all required JSON keys present', () async {
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
    });
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
    test('is a no-op when called while already tracking', () async {
      // Set up a stream that never completes so tracking stays active.
      final controller1 = StreamController<Position>();
      locationService.fakeStream = controller1.stream;

      await controller.startDriverTracking(driverId: 'USR#drv-12345');
      expect(controller.isTracking, isTrue);

      // Second call should be silently ignored — no assertion error.
      await controller.startDriverTracking(driverId: 'USR#drv-12345');
      expect(controller.isTracking, isTrue);

      controller1.close();
    });
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
        streamController.add(_makePosition(latitude: -1.0, longitude: 2.0));
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

  // ---- Geofencing triggers --------------------------------------------------

  group('Geofencing Handshake —', () {
    test(
      'updates isWithinGeofenceRadius when WebSocket message carries geofence_status ARRIVED',
      () async {
        locationService.fakeStream = const Stream<Position>.empty();

        await controller.startDriverTracking(driverId: 'USR#drv-12345');
        expect(controller.state.isWithinGeofenceRadius, isFalse);

        // Simulate websocket event
        wsService.feedMessage({
          'status': 'Telemetry Latched',
          'flags': {'geofence_status': 'ARRIVED'},
        });

        // Allow microtasks to complete
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.isWithinGeofenceRadius, isTrue);
      },
    );

    test(
      'confirmArrival sends confirmArrival action and resets geofence radius state',
      () async {
        locationService.fakeStream = const Stream<Position>.empty();

        await controller.startDriverTracking(driverId: 'USR#drv-12345');

        // Set arrived status
        wsService.feedMessage({
          'flags': {'geofence_status': 'ARRIVED'},
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.isWithinGeofenceRadius, isTrue);

        // Confirm arrival
        await controller.confirmArrival(
          driverId: 'USR#drv-12345',
          tripId: 'trip-abc-123',
        );

        // Assert state reset
        expect(controller.state.isWithinGeofenceRadius, isFalse);

        // Assert network confirmation message dispatched
        expect(wsService.capturedPayloads.length, equals(1));
        final decoded =
            jsonDecode(wsService.capturedPayloads.first)
                as Map<String, dynamic>;
        expect(decoded['action'], equals('confirmArrival'));
        expect(decoded['driverId'], equals('USR#drv-12345'));
        expect(decoded['tripId'], equals('trip-abc-123'));
        expect(decoded.containsKey('timestamp'), isTrue);
      },
    );

    test(
      'stopDriverTracking cancels subscriptions and resets geofence state',
      () async {
        final streamController = StreamController<Position>();
        locationService.fakeStream = streamController.stream;

        await controller.startDriverTracking(driverId: 'USR#drv-12345');
        expect(controller.isTracking, isTrue);

        wsService.feedMessage({
          'flags': {'geofence_status': 'ARRIVED'},
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.isWithinGeofenceRadius, isTrue);

        controller.stopDriverTracking();

        expect(controller.state.isWithinGeofenceRadius, isFalse);
        expect(controller.isTracking, isFalse);

        await streamController.close();
      },
    );
  });

  // ---- Ride Offer Hydration ------------------------------------------------

  group('Ride Offer — state hydration —', () {
    test('receiving rideOfferAvailable event hydrates activeOffer and starts '
        'the countdown at 15 seconds', () async {
      locationService.fakeStream = const Stream<Position>.empty();
      await controller.startDriverTracking(driverId: 'USR#drv-12345');

      // Initially no offer is present.
      expect(controller.state.activeOffer, isNull);
      expect(controller.state.offerSecondsRemaining, equals(0));

      // Feed the marketplace event.
      final payload = _makeRideOfferPayload(
        tripId: 'TRIP#hydrate-001',
        pickupLocation: 'Cape Town CBD',
        dropoffLocation: 'V&A Waterfront',
        baseFare: 55.00,
      );
      wsService.feedMessage(payload);

      // Wait for the stream event to be processed.
      await Future<void>.delayed(Duration.zero);

      final offer = controller.state.activeOffer;
      expect(offer, isNotNull);
      expect(offer!.tripId, equals('TRIP#hydrate-001'));
      expect(offer.pickupLocation, equals('Cape Town CBD'));
      expect(offer.dropoffLocation, equals('V&A Waterfront'));
      expect(offer.baseFare, closeTo(55.00, 0.001));
      expect(controller.state.offerSecondsRemaining, equals(15));
    });

    test('all required ActiveRideOffer fields are correctly parsed from the '
        'WebSocket payload', () async {
      locationService.fakeStream = const Stream<Position>.empty();
      await controller.startDriverTracking(driverId: 'USR#drv-12345');

      final expiresAt = DateTime.utc(
        2024,
        6,
        21,
        8,
        0,
        15,
      ); // fixed for assertion

      wsService.feedMessage({
        'action': 'rideOfferAvailable',
        'tripId': 'TRIP#field-check',
        'pickupLocation': 'Sandton City',
        'dropoffLocation': 'OR Tambo International',
        'baseFare': 320.75,
        'expiresAt': expiresAt.toIso8601String(),
      });

      await Future<void>.delayed(Duration.zero);

      final offer = controller.state.activeOffer!;
      expect(offer.tripId, equals('TRIP#field-check'));
      expect(offer.pickupLocation, equals('Sandton City'));
      expect(offer.dropoffLocation, equals('OR Tambo International'));
      expect(offer.baseFare, closeTo(320.75, 0.001));
      expect(offer.expiresAt, equals(expiresAt));
    });

    test('a second rideOfferAvailable event replaces the previous offer and '
        'resets the countdown to 15', () async {
      locationService.fakeStream = const Stream<Position>.empty();
      await controller.startDriverTracking(driverId: 'USR#drv-12345');

      // Feed first offer.
      wsService.feedMessage(_makeRideOfferPayload(tripId: 'TRIP#first'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.activeOffer?.tripId, equals('TRIP#first'));

      // Feed a replacement offer immediately.
      wsService.feedMessage(
        _makeRideOfferPayload(tripId: 'TRIP#second', baseFare: 99.00),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.activeOffer?.tripId, equals('TRIP#second'));
      expect(controller.state.activeOffer?.baseFare, closeTo(99.00, 0.001));
      // Countdown must have been reset to 15.
      expect(controller.state.offerSecondsRemaining, equals(15));
    });

    test('a malformed rideOfferAvailable payload is gracefully ignored without '
        'throwing or corrupting existing state', () async {
      locationService.fakeStream = const Stream<Position>.empty();
      await controller.startDriverTracking(driverId: 'USR#drv-12345');

      // Feed a valid offer first so we can assert state is unchanged.
      wsService.feedMessage(_makeRideOfferPayload(tripId: 'TRIP#valid'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.activeOffer?.tripId, equals('TRIP#valid'));

      // Feed a malformed offer (missing required fields).
      wsService.feedMessage({
        'action': 'rideOfferAvailable',
        // Missing tripId, pickupLocation, etc.
        'baseFare': 'not-a-number',
      });
      await Future<void>.delayed(Duration.zero);

      // The previous valid offer must remain unchanged.
      expect(controller.state.activeOffer?.tripId, equals('TRIP#valid'));
    });

    test(
      'handlePushNotificationClick hydrates the active offer and starts the countdown',
      () async {
        locationService.fakeStream = const Stream<Position>.empty();
        wsService._connected = false;

        final payload = {
          'action': 'rideOfferAvailable',
          'tripId': 'TRIP#push-001',
          'pickupLocation': 'Woodstock',
          'dropoffLocation': 'Sea Point',
          'base_fare': 128.50,
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 15))
              .toIso8601String(),
        };

        controller.handlePushNotificationClick(payload);

        expect(
          wsService.connectCalled,
          isTrue,
          reason: 'The WebSocket service must reconnect when disconnected.',
        );

        expect(controller.state.activeOffer, isNotNull);
        expect(controller.state.activeOffer?.tripId, equals('TRIP#push-001'));
        expect(controller.state.offerSecondsRemaining, equals(15));
      },
    );

    test(
      'stopDriverTracking clears an active offer and resets the countdown',
      () async {
        final posStream = StreamController<Position>();
        locationService.fakeStream = posStream.stream;
        await controller.startDriverTracking(driverId: 'USR#drv-12345');

        wsService.feedMessage(_makeRideOfferPayload(tripId: 'TRIP#stop-test'));
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.activeOffer, isNotNull);

        controller.stopDriverTracking();

        expect(controller.state.activeOffer, isNull);
        expect(controller.state.offerSecondsRemaining, equals(0));

        await posStream.close();
      },
    );
  });

  // ---- Countdown Timer Expiry ----------------------------------------------

  group('Ride Offer — countdown timer expiry —', () {
    test(
      'the countdown decrements by 1 each second and the offer is purged when '
      'it reaches zero',
      () async {
        locationService.fakeStream = const Stream<Position>.empty();
        await controller.startDriverTracking(driverId: 'USR#drv-12345');

        wsService.feedMessage(_makeRideOfferPayload(tripId: 'TRIP#expire-001'));
        await Future<void>.delayed(Duration.zero);

        // Countdown should be at 15 immediately after hydration.
        expect(controller.state.offerSecondsRemaining, equals(15));
        expect(controller.state.activeOffer, isNotNull);

        // Advance fake time by 16 seconds — one past the countdown boundary.
        await Future<void>.delayed(const Duration(seconds: 16));

        // The offer must have been purged.
        expect(
          controller.state.activeOffer,
          isNull,
          reason: 'Offer should be null after the 15-second countdown expires',
        );
        expect(controller.state.offerSecondsRemaining, equals(0));
      },
      // This test relies on a real Timer, so set a generous timeout.
      timeout: const Timeout(Duration(seconds: 25)),
    );

    test(
      'the countdown is still live at 1 second before expiry',
      () async {
        locationService.fakeStream = const Stream<Position>.empty();
        await controller.startDriverTracking(driverId: 'USR#drv-12345');

        wsService.feedMessage(
          _makeRideOfferPayload(tripId: 'TRIP#expire-partial'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.offerSecondsRemaining, equals(15));

        // Advance 14 seconds — offer should still be active.
        await Future<void>.delayed(const Duration(seconds: 14));

        expect(
          controller.state.activeOffer,
          isNotNull,
          reason: 'Offer should still be present at t+14s',
        );
        expect(
          controller.state.offerSecondsRemaining,
          inInclusiveRange(0, 2),
          reason: 'Remaining seconds should be between 0 and 2 at t+14s',
        );
      },
      timeout: const Timeout(Duration(seconds: 25)),
    );
  });

  // ---- Wallet Settlement tests ----------------------------------------------

  group('Wallet Settlement —', () {
    test(
      'receiving WalletSettled message updates dailyEarningsTotal and lastNetEarnings',
      () async {
        locationService.fakeStream = const Stream<Position>.empty();
        await controller.startDriverTracking(driverId: 'USR#drv-12345');

        expect(controller.state.dailyEarningsTotal, equals(0.0));
        expect(controller.state.lastNetEarnings, isNull);

        // Simulate WalletSettled event
        wsService.feedMessage({
          'status': 'WalletSettled',
          'net_earnings': 120.50,
          'updated_daily_total': 450.00,
        });

        // Allow microtasks to complete
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.dailyEarningsTotal, equals(450.00));
        expect(controller.state.lastNetEarnings, equals(120.50));
      },
    );

    test(
      'clearLastNetEarnings resets lastNetEarnings to null without mutating dailyEarningsTotal',
      () async {
        locationService.fakeStream = const Stream<Position>.empty();
        await controller.startDriverTracking(driverId: 'USR#drv-12345');

        wsService.feedMessage({
          'status': 'WalletSettled',
          'net_earnings': 85.00,
          'updated_daily_total': 170.00,
        });
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.lastNetEarnings, equals(85.00));
        expect(controller.state.dailyEarningsTotal, equals(170.00));

        controller.clearLastNetEarnings();

        expect(controller.state.lastNetEarnings, isNull);
        expect(controller.state.dailyEarningsTotal, equals(170.00));
      },
    );
  });

  // ---- submitBid — counter-proposal / acceptance ----

  group('Ride Offer — submitBid (counter-proposal/acceptance) —', () {
    test('submitBid dispatches a correctly structured sendBid payload with the '
        'targeted bid_amount to the WebSocket sink', () async {
      locationService.fakeStream = const Stream<Position>.empty();
      await controller.startDriverTracking(driverId: 'USR#drv-12345');

      // Hydrate an active offer first so the context is realistic.
      wsService.feedMessage(
        _makeRideOfferPayload(tripId: 'TRIP#bid-001', baseFare: 120.0),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.activeOffer, isNotNull);

      // Act — driver taps "+R15" counter-bid.
      await controller.submitBid(
        driverId: 'USR#drv-12345',
        tripId: 'TRIP#bid-001',
        bidAmount: 135.0,
      );

      // Assert: exactly one payload was captured (location stream is empty,
      // so the only sink.add() comes from submitBid).
      expect(wsService.capturedPayloads.length, equals(1));
      final decoded =
          jsonDecode(wsService.capturedPayloads.first) as Map<String, dynamic>;
      expect(decoded['action'], equals('sendBid'));
      expect(decoded['driverId'], equals('USR#drv-12345'));
      expect(decoded['tripId'], equals('TRIP#bid-001'));
      expect(decoded['bid_amount'], closeTo(135.0, 0.001));
    });

    test(
      'submitBid with base fare amount dispatches bid_amount equal to baseFare',
      () async {
        locationService.fakeStream = const Stream<Position>.empty();
        await controller.startDriverTracking(driverId: 'USR#drv-12345');

        wsService.feedMessage(
          _makeRideOfferPayload(tripId: 'TRIP#bid-base', baseFare: 90.0),
        );
        await Future<void>.delayed(Duration.zero);

        await controller.submitBid(
          driverId: 'USR#drv-12345',
          tripId: 'TRIP#bid-base',
          bidAmount: 90.0,
        );

        final decoded =
            jsonDecode(wsService.capturedPayloads.first)
                as Map<String, dynamic>;
        expect(decoded['bid_amount'], closeTo(90.0, 0.001));
      },
    );

    test(
      'submitBid with +R30 counter dispatches bid_amount equal to baseFare + 30',
      () async {
        locationService.fakeStream = const Stream<Position>.empty();
        await controller.startDriverTracking(driverId: 'USR#drv-12345');

        wsService.feedMessage(
          _makeRideOfferPayload(tripId: 'TRIP#bid-r30', baseFare: 200.0),
        );
        await Future<void>.delayed(Duration.zero);

        await controller.submitBid(
          driverId: 'USR#drv-12345',
          tripId: 'TRIP#bid-r30',
          bidAmount: 230.0,
        );

        final decoded =
            jsonDecode(wsService.capturedPayloads.first)
                as Map<String, dynamic>;
        expect(decoded['bid_amount'], closeTo(230.0, 0.001));
      },
    );

    test('submitBid cancels the countdown timer and clears activeOffer state '
        'to prevent double-submitting', () async {
      locationService.fakeStream = const Stream<Position>.empty();
      await controller.startDriverTracking(driverId: 'USR#drv-12345');

      wsService.feedMessage(_makeRideOfferPayload(tripId: 'TRIP#bid-reset'));
      await Future<void>.delayed(Duration.zero);

      // Offer and countdown must be live before the bid.
      expect(controller.state.activeOffer, isNotNull);
      expect(controller.state.offerSecondsRemaining, equals(15));

      await controller.submitBid(
        driverId: 'USR#drv-12345',
        tripId: 'TRIP#bid-reset',
        bidAmount: 60.0,
      );

      // Both offer and countdown must be reset after submission.
      expect(controller.state.activeOffer, isNull);
      expect(controller.state.offerSecondsRemaining, equals(0));
    });

    test('submitBid payload contains all required JSON keys', () async {
      locationService.fakeStream = const Stream<Position>.empty();
      await controller.startDriverTracking(driverId: 'USR#drv-12345');

      wsService.feedMessage(_makeRideOfferPayload(tripId: 'TRIP#bid-keys'));
      await Future<void>.delayed(Duration.zero);

      await controller.submitBid(
        driverId: 'USR#drv-12345',
        tripId: 'TRIP#bid-keys',
        bidAmount: 75.0,
      );

      final decoded =
          jsonDecode(wsService.capturedPayloads.first) as Map<String, dynamic>;
      expect(decoded.containsKey('action'), isTrue);
      expect(decoded.containsKey('driverId'), isTrue);
      expect(decoded.containsKey('tripId'), isTrue);
      expect(decoded.containsKey('bid_amount'), isTrue);
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
