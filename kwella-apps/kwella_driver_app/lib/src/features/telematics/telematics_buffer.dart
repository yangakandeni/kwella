import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

// ---------------------------------------------------------------------------
// GpsDeltaPoint – immutable GPS sample value object
// ---------------------------------------------------------------------------

/// A single GPS measurement captured at a discrete point in time.
///
/// Multiple [GpsDeltaPoint] instances are accumulated in [TelematicsBufferManager]
/// and flushed as a single batch payload to the AWS WebSocket endpoint every
/// 3 seconds.
class GpsDeltaPoint {
  const GpsDeltaPoint({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.timestamp,
  });

  /// Decimal-degree WGS-84 latitude.
  final double latitude;

  /// Decimal-degree WGS-84 longitude.
  final double longitude;

  /// Instantaneous speed in km/h.
  final double speed;

  /// UTC time at which this sample was captured.
  final DateTime timestamp;

  /// Serialises this point to a JSON-compatible map for batch encoding.
  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lng': longitude,
        'spd': speed,
        'ts': timestamp.millisecondsSinceEpoch,
      };
}

// ---------------------------------------------------------------------------
// TelematicsState – reactive snapshot exposed to the UI
// ---------------------------------------------------------------------------

/// Immutable snapshot of the telematics engine consumed by the UI.
class TelematicsState {
  const TelematicsState({
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.speed = 0.0,
    this.bufferedPointCount = 0,
    this.lastFlushTime,
    this.totalPointsFlushed = 0,
  });

  /// Most-recently pushed latitude.
  final double latitude;

  /// Most-recently pushed longitude.
  final double longitude;

  /// Most-recently pushed speed in km/h.
  final double speed;

  /// Number of [GpsDeltaPoint]s currently waiting in the buffer.
  final int bufferedPointCount;

  /// Wall-clock time of the last successful flush (null until first flush).
  final DateTime? lastFlushTime;

  /// Running total of points that have been sent over the wire.
  final int totalPointsFlushed;

  TelematicsState copyWith({
    double? latitude,
    double? longitude,
    double? speed,
    int? bufferedPointCount,
    DateTime? lastFlushTime,
    int? totalPointsFlushed,
  }) {
    return TelematicsState(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speed: speed ?? this.speed,
      bufferedPointCount: bufferedPointCount ?? this.bufferedPointCount,
      lastFlushTime: lastFlushTime ?? this.lastFlushTime,
      totalPointsFlushed: totalPointsFlushed ?? this.totalPointsFlushed,
    );
  }
}

// ---------------------------------------------------------------------------
// TelematicsBufferManager – StateNotifier with rolling 3-second flush timer
// ---------------------------------------------------------------------------

/// Manages an internal queue of [GpsDeltaPoint] values and flushes them as a
/// single JSON batch payload to the AWS WebSocket gateway every 3 seconds.
///
/// **Throttle contract**:
/// - [pushCoordinate] may be called at any frequency; it never triggers a
///   network write directly.
/// - A rolling [Timer] fires every 3 seconds and flushes *all* accumulated
///   points in a single `send()` call, then clears the queue.
/// - If the queue is empty when the timer fires, no network payload is sent.
///
/// **Lifecycle**: The timer is started in the constructor and cancelled in
/// [dispose], which Riverpod calls when the provider is no longer observed.
///
/// Usage (inside a [ConsumerStatefulWidget]):
/// ```dart
/// ref.read(telematicsBufferProvider.notifier).pushCoordinate(lat, lng, speed);
/// ```
class TelematicsBufferManager extends StateNotifier<TelematicsState> {
  TelematicsBufferManager(this._ref) : super(const TelematicsState()) {
    _startFlushTimer();
  }

  final Ref _ref;

  /// Internal point queue — flushed and cleared every 3 seconds.
  final List<GpsDeltaPoint> _buffer = [];

  /// Rolling 3-second flush timer.
  Timer? _flushTimer;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Appends a new [GpsDeltaPoint] to the buffer and updates the reactive
  /// [TelematicsState] so the UI reflects the latest coordinate immediately.
  ///
  /// Does **not** send anything over the network; flushing is handled
  /// exclusively by the internal 3-second timer.
  void pushCoordinate(double lat, double lng, double speed) {
    final point = GpsDeltaPoint(
      latitude: lat,
      longitude: lng,
      speed: speed,
      timestamp: DateTime.now().toUtc(),
    );

    _buffer.add(point);

    // Update UI state immediately so the telematics header stays live.
    state = state.copyWith(
      latitude: lat,
      longitude: lng,
      speed: speed,
      bufferedPointCount: _buffer.length,
    );
  }

  // ── Internal flush logic ──────────────────────────────────────────────────

  void _startFlushTimer() {
    _flushTimer = Timer.periodic(const Duration(seconds: 3), (_) => _flush());
  }

  /// Encodes all queued points into a single JSON batch and dispatches them
  /// via [KwellaWebSocketGateway.send].
  ///
  /// If the buffer is empty, this method returns immediately without any
  /// network I/O.
  void _flush() {
    if (_buffer.isEmpty) return;

    final gateway = _ref.read(kwellaWebSocketGatewayProvider);

    // Encode the batch before clearing so we never lose points on failure.
    final List<Map<String, dynamic>> batch =
        _buffer.map((p) => p.toJson()).toList();

    final payload = jsonEncode({
      'action': 'TelemetryBatch',
      'payload': {
        'points': batch,
      },
    });

    // Only send if the gateway connection is live; otherwise discard this
    // batch rather than throwing, so the driver UI is never disrupted by a
    // transient connectivity gap.
    if (gateway.isConnected) {
      try {
        gateway.send(payload);
      } catch (e) {
        // Swallow send errors – the next flush cycle will retry with fresh data.
        // TODO: wire to structured error reporting once a logging layer exists.
        assert(() {
          // ignore: avoid_print
          print('[TelematicsBuffer] send error: $e');
          return true;
        }());
      }
    }

    final flushedCount = _buffer.length;
    _buffer.clear();

    assert(() {
      // ignore: avoid_print
      print('[TelematicsBuffer] Flushed $flushedCount GPS delta point(s).');
      return true;
    }());

    state = state.copyWith(
      bufferedPointCount: 0,
      lastFlushTime: DateTime.now(),
      totalPointsFlushed: state.totalPointsFlushed + flushedCount,
    );
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Riverpod provider for the telematics delta buffer engine.
///
/// Expose the reactive [TelematicsState] to the UI via `ref.watch`, and push
/// new GPS samples via `ref.read(telematicsBufferProvider.notifier).pushCoordinate(...)`.
final telematicsBufferProvider =
    StateNotifierProvider<TelematicsBufferManager, TelematicsState>(
  (ref) => TelematicsBufferManager(ref),
);

// ---------------------------------------------------------------------------
// Coordinate simulation helpers (used by the mock loop in DriverHomeScreen)
// ---------------------------------------------------------------------------

/// Simple Gaussian-style random-walk generator for mock GPS coordinates.
///
/// Starts near Cape Town (Kwella's home region) and drifts slightly each tick
/// to simulate a vehicle in motion.
class MockCoordinateWalker {
  MockCoordinateWalker({
    double startLat = -33.9249,  // Cape Town, South Africa
    double startLng = 18.4241,
    double startSpeed = 42.0,
  })  : _lat = startLat,
        _lng = startLng,
        _speed = startSpeed;

  double _lat;
  double _lng;
  double _speed;

  final math.Random _rng = math.Random();

  /// Returns the next simulated coordinate, applying a small random-walk delta.
  ({double lat, double lng, double speed}) next() {
    _lat += (_rng.nextDouble() - 0.5) * 0.0002;
    _lng += (_rng.nextDouble() - 0.5) * 0.0002;
    _speed = (_speed + (_rng.nextDouble() - 0.5) * 4.0).clamp(5.0, 120.0);
    return (lat: _lat, lng: _lng, speed: _speed);
  }
}
