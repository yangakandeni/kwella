import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bidding/services/kwella_websocket_service.dart';
import '../../services/kwella_location_service.dart';

/// State object representing the telemetry and geofencing status of the driver.
@immutable
class TelemetryState {
  final bool isTracking;
  final bool isWithinGeofenceRadius;

  const TelemetryState({
    required this.isTracking,
    required this.isWithinGeofenceRadius,
  });

  TelemetryState copyWith({
    bool? isTracking,
    bool? isWithinGeofenceRadius,
  }) {
    return TelemetryState(
      isTracking: isTracking ?? this.isTracking,
      isWithinGeofenceRadius: isWithinGeofenceRadius ?? this.isWithinGeofenceRadius,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TelemetryState &&
          runtimeType == other.runtimeType &&
          isTracking == other.isTracking &&
          isWithinGeofenceRadius == other.isWithinGeofenceRadius;

  @override
  int get hashCode => isTracking.hashCode ^ isWithinGeofenceRadius.hashCode;

  @override
  String toString() =>
      'TelemetryState(isTracking: $isTracking, isWithinGeofenceRadius: $isWithinGeofenceRadius)';
}

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
class KwellaTelemetryController extends StateNotifier<TelemetryState> {
  // ---------------------------------------------------------------------------
  // Dependencies — injectable for testing.
  // ---------------------------------------------------------------------------

  final KwellaLocationService _locationService;
  final KwellaWebSocketService _wsService;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  StreamSubscription<void>? _positionSubscription;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  /// Whether driver tracking is currently active.
  bool get isTracking => state.isTracking;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  /// Creates a telemetry controller backed by the provided service instances.
  ///
  /// In production, use the [telemetryControllerProvider] Riverpod handle.
  KwellaTelemetryController({
    KwellaLocationService? locationService,
    KwellaWebSocketService? wsService,
  })  : _locationService = locationService ?? KwellaLocationService.instance,
        _wsService = wsService ?? KwellaWebSocketService.instance,
        super(const TelemetryState(isTracking: false, isWithinGeofenceRadius: false));

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
    if (state.isTracking) {
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

    state = state.copyWith(isTracking: true);

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
            state = state.copyWith(isTracking: false);
          },
          cancelOnError: false,
        );

    // Intercept geofencing status response flags on WebSocket stream channel
    _wsSubscription = _wsService.bidStream.listen(
      (data) {
        final flags = data['flags'];
        if (flags is Map && flags['geofence_status'] == 'ARRIVED') {
          debugPrint('[KwellaTelemetryController] Geofence ARRIVED status intercepted.');
          state = state.copyWith(isWithinGeofenceRadius: true);
        }
      },
      onError: (Object error) {
        debugPrint('[KwellaTelemetryController] WebSocket telemetry subscription error: $error');
      },
    );

    debugPrint(
      '[KwellaTelemetryController] Tracking active for driver: $driverId',
    );
  }

  /// Dispatches a manual arrival confirmation event over the WebSocket channel
  /// and resets the local geofence alert state.
  Future<void> confirmArrival({
    required String driverId,
    required String tripId,
  }) async {
    final payload = jsonEncode({
      'action': 'confirmArrival',
      'driverId': driverId,
      'tripId': tripId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    debugPrint('[KwellaTelemetryController] Dispatching confirmArrival: $payload');
    _wsService.sink.add(payload);

    state = state.copyWith(isWithinGeofenceRadius: false);
  }

  /// Cancels the underlying [StreamSubscription] and halts all telemetry
  /// dispatches.
  ///
  /// Safe to call even when tracking is not active.
  void stopDriverTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;

    _wsSubscription?.cancel();
    _wsSubscription = null;

    if (mounted) {
      state = state.copyWith(
        isTracking: false,
        isWithinGeofenceRadius: false,
      );
    }

    debugPrint('[KwellaTelemetryController] Tracking stopped. Streams cancelled and geofence flags reset.');
  }

  @override
  void dispose() {
    stopDriverTracking();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Riverpod v2 provider
// ---------------------------------------------------------------------------

/// A Riverpod [StateNotifierProvider] that exposes a [KwellaTelemetryController] and its state.
///
/// Usage:
/// ```dart
/// final state = ref.watch(telemetryControllerProvider);
/// final controller = ref.read(telemetryControllerProvider.notifier);
/// await controller.startDriverTracking(driverId: 'USR#drv-12345');
/// ```
final telemetryControllerProvider =
    StateNotifierProvider<KwellaTelemetryController, TelemetryState>((ref) {
  return KwellaTelemetryController();
});
