import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bidding/services/kwella_websocket_service.dart';
import '../../services/kwella_location_service.dart';

/// Automates real-time driver location tracking by bridging the hardware
/// position stream from [KwellaLocationService] directly into the live
/// WebSocket sink of [KwellaWebSocketService].
///
/// Lifecycle:
/// 1. Call [startDriverTracking] with the authenticated driver ID.
/// 2. The controller runs the full location permission handshake.
/// 3. On each GPS frame, a structured `updateLocation` payload is dispatched
///    through the WebSocket sink to the AWS API Gateway telemetry route.
/// 4. Call [stopDriverTracking] to cleanly cancel the stream and halt battery
///    drain when the driver goes offline or disconnects.
class KwellaTelemetryController {
  // ---------------------------------------------------------------------------
  // Dependencies — injectable for testing.
  // ---------------------------------------------------------------------------

  final KwellaLocationService _locationService;
  final KwellaWebSocketService _wsService;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  StreamSubscription<void>? _positionSubscription;

  /// Whether driver tracking is currently active.
  bool get isTracking => _positionSubscription != null;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  /// Creates a telemetry controller backed by the provided service instances.
  ///
  /// In production, use [KwellaTelemetryController.instance] or the
  /// [telemetryControllerProvider] Riverpod handle instead of constructing
  /// this directly.
  KwellaTelemetryController({
    KwellaLocationService? locationService,
    KwellaWebSocketService? wsService,
  })  : _locationService = locationService ?? KwellaLocationService.instance,
        _wsService = wsService ?? KwellaWebSocketService.instance;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Initiates real-time driver location tracking for [driverId].
  ///
  /// Steps:
  /// 1. Runs the permission handshake via [KwellaLocationService].
  /// 2. If permissions are denied, logs the failure and returns early without
  ///    throwing — the caller can check [isTracking] to confirm activation.
  /// 3. Subscribes to the high-accuracy position stream.
  /// 4. For each emitted [Position] frame, encodes a structured
  ///    `"updateLocation"` JSON payload and pushes it through the WebSocket
  ///    sink to the live AWS telemetry ingestion route.
  ///
  /// Calling this method while tracking is already active is a no-op.
  Future<void> startDriverTracking({required String driverId}) async {
    if (isTracking) {
      debugPrint(
        '[KwellaTelemetryController] startDriverTracking called while '
        'already tracking. Call stopDriverTracking() first.',
      );
      return;
    }

    debugPrint(
      '[KwellaTelemetryController] Starting tracking for driver: $driverId',
    );

    // Step 1 — Permission handshake.
    final bool granted =
        await _locationService.requestLocationPermissions();

    if (!granted) {
      debugPrint(
        '[KwellaTelemetryController] Location permissions not granted. '
        'Tracking aborted for driver: $driverId',
      );
      return;
    }

    // Step 2 — Subscribe to the hardware position stream.
    _positionSubscription = _locationService
        .startPositionStream()
        .listen(
          (position) {
            // Step 3 — Dispatch telemetry frame through the WebSocket sink.
            final payload = jsonEncode({
              'action': 'updateLocation',
              'driverId': driverId,
              'latitude': position.latitude,
              'longitude': position.longitude,
              'heading': position.heading,
              'speed': position.speed,
            });

            debugPrint(
              '[KwellaTelemetryController] Dispatching telemetry: $payload',
            );

            _wsService.sink.add(payload);
          },
          onError: (Object error, StackTrace stack) {
            debugPrint(
              '[KwellaTelemetryController] Position stream error: $error',
            );
          },
          onDone: () {
            debugPrint(
              '[KwellaTelemetryController] Position stream closed for '
              'driver: $driverId',
            );
            // Null the subscription reference so isTracking reflects reality.
            _positionSubscription = null;
          },
          cancelOnError: false,
        );

    debugPrint(
      '[KwellaTelemetryController] Tracking active for driver: $driverId',
    );
  }

  /// Cancels the underlying [StreamSubscription] and halts all telemetry
  /// dispatches.
  ///
  /// Safe to call even when tracking is not active.
  void stopDriverTracking() {
    if (!isTracking) {
      debugPrint(
        '[KwellaTelemetryController] stopDriverTracking called but '
        'tracking is not active.',
      );
      return;
    }

    _positionSubscription?.cancel();
    _positionSubscription = null;

    debugPrint('[KwellaTelemetryController] Tracking stopped. Stream cancelled.');
  }
}

// ---------------------------------------------------------------------------
// Riverpod v2 provider
// ---------------------------------------------------------------------------

/// A Riverpod [Provider] that exposes a [KwellaTelemetryController] scoped to
/// the widget tree.
///
/// Usage:
/// ```dart
/// final controller = ref.read(telemetryControllerProvider);
/// await controller.startDriverTracking(driverId: 'USR#drv-12345');
/// ```
///
/// The controller is automatically torn down when the provider is disposed
/// (e.g., when the widget subtree that reads it is removed).
final telemetryControllerProvider = Provider<KwellaTelemetryController>((ref) {
  final controller = KwellaTelemetryController();

  // Register teardown so stopDriverTracking is called when the provider scope
  // is destroyed, preventing battery drain from orphaned subscriptions.
  ref.onDispose(controller.stopDriverTracking);

  return controller;
});
