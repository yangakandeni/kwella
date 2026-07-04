import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

/// Immutable snapshot of the driver's live position, derived from
/// [DriverLocationUpdateEvent] frames relayed over
/// [kwellaEventMultiplexerProvider].
class DriverTrackingState {
  const DriverTrackingState({
    this.isActive = false,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.bearing = 0.0,
    this.speed = 0.0,
    this.lastUpdated,
    this.anchorLatitude,
    this.anchorLongitude,
  });

  /// Whether at least one telematics fix has been received this session.
  final bool isActive;

  /// Most recently reported WGS-84 latitude.
  final double latitude;

  /// Most recently reported WGS-84 longitude.
  final double longitude;

  /// Heading in degrees, clockwise from true north (0-360). The driver
  /// device does not transmit heading, so this is derived from consecutive
  /// fixes.
  final double bearing;

  /// Most recently reported speed in km/h.
  final double speed;

  /// Wall-clock time the underlying GPS sample was captured.
  final DateTime? lastUpdated;

  /// Latitude of the first fix received this session, used as a stable
  /// reference point for rendering relative movement. Null until the first
  /// fix arrives.
  final double? anchorLatitude;

  /// Longitude of the first fix received this session. Null until the
  /// first fix arrives.
  final double? anchorLongitude;

  DriverTrackingState copyWith({
    bool? isActive,
    double? latitude,
    double? longitude,
    double? bearing,
    double? speed,
    DateTime? lastUpdated,
    double? anchorLatitude,
    double? anchorLongitude,
  }) {
    return DriverTrackingState(
      isActive: isActive ?? this.isActive,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      bearing: bearing ?? this.bearing,
      speed: speed ?? this.speed,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      anchorLatitude: anchorLatitude ?? this.anchorLatitude,
      anchorLongitude: anchorLongitude ?? this.anchorLongitude,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DriverTrackingState &&
          runtimeType == other.runtimeType &&
          isActive == other.isActive &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          bearing == other.bearing &&
          speed == other.speed &&
          lastUpdated == other.lastUpdated &&
          anchorLatitude == other.anchorLatitude &&
          anchorLongitude == other.anchorLongitude;

  @override
  int get hashCode =>
      isActive.hashCode ^
      latitude.hashCode ^
      longitude.hashCode ^
      bearing.hashCode ^
      speed.hashCode ^
      (lastUpdated?.hashCode ?? 0) ^
      (anchorLatitude?.hashCode ?? 0) ^
      (anchorLongitude?.hashCode ?? 0);

  @override
  String toString() {
    return 'DriverTrackingState(isActive: $isActive, latitude: $latitude, '
        'longitude: $longitude, bearing: $bearing, speed: $speed)';
  }
}

/// Listens to [kwellaEventMultiplexerProvider], filters for
/// [DriverLocationUpdateEvent] frames, and projects them into a clean
/// [DriverTrackingState] the map layer can render directly.
class DriverTrackingNotifier extends StateNotifier<DriverTrackingState> {
  DriverTrackingNotifier(this._ref) : super(const DriverTrackingState()) {
    _subscription = _ref.listen<AsyncValue<KwellaBiddingEvent>>(
      kwellaEventMultiplexerProvider,
      (previous, next) => next.whenData(_handleEvent),
    );
  }

  final Ref _ref;
  ProviderSubscription<AsyncValue<KwellaBiddingEvent>>? _subscription;

  void _handleEvent(KwellaBiddingEvent event) {
    if (!mounted) return;
    if (event is! DriverLocationUpdateEvent || event.points.isEmpty) return;

    var lat = state.latitude;
    var lng = state.longitude;
    var bearing = state.bearing;
    var hasPrevious = state.isActive;
    var anchorLat = state.anchorLatitude;
    var anchorLng = state.anchorLongitude;

    for (final point in event.points) {
      if (hasPrevious) {
        bearing =
            _bearingBetween(lat, lng, point.latitude, point.longitude) ??
                bearing;
      } else {
        anchorLat = point.latitude;
        anchorLng = point.longitude;
      }
      lat = point.latitude;
      lng = point.longitude;
      hasPrevious = true;
    }

    final latest = event.points.last;
    state = state.copyWith(
      isActive: true,
      latitude: latest.latitude,
      longitude: latest.longitude,
      bearing: bearing,
      speed: latest.speed,
      lastUpdated: latest.timestamp,
      anchorLatitude: anchorLat,
      anchorLongitude: anchorLng,
    );
  }

  /// Resets tracking back to its initial, inactive state (e.g. once a trip
  /// ends and there is no longer a live driver stream to follow).
  void reset() {
    state = const DriverTrackingState();
  }

  /// Great-circle initial bearing (forward azimuth) from one fix to the
  /// next, in degrees clockwise from true north. Returns `null` when the two
  /// fixes are effectively the same point, so the caller can keep the prior
  /// heading instead of snapping to due north.
  static double? _bearingBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    if (lat1 == lat2 && lng1 == lng2) return null;

    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final deltaLambda = (lng2 - lng1) * math.pi / 180;

    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);

    final theta = math.atan2(y, x);
    return (theta * 180 / math.pi + 360) % 360;
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}

/// Global provider for the rider-side live driver tracking state machine.
final driverTrackingProvider =
    StateNotifierProvider<DriverTrackingNotifier, DriverTrackingState>(
  (ref) => DriverTrackingNotifier(ref),
);
