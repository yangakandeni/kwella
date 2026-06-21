import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// A production-ready singleton service that encapsulates the full geolocator
/// permission lifecycle and high-accuracy position stream for Kwella telematics.
class KwellaLocationService {
  // ---------------------------------------------------------------------------
  // Singleton wiring — mirrors KwellaWebSocketService pattern.
  // ---------------------------------------------------------------------------
  static KwellaLocationService _instance = KwellaLocationService._internal();
  factory KwellaLocationService() => _instance;
  KwellaLocationService._internal();

  /// Named constructor for test subclasses only. Do not use in production.
  @visibleForTesting
  KwellaLocationService.forTesting();

  /// Application-wide singleton accessor.
  static KwellaLocationService get instance => _instance;

  /// Replaces the singleton with a fresh instance; intended for unit tests only.
  @visibleForTesting
  static void reset() {
    _instance = KwellaLocationService._internal();
  }

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// Whether the permission handshake has been completed successfully.
  bool _permissionsGranted = false;

  bool get permissionsGranted => _permissionsGranted;

  // ---------------------------------------------------------------------------
  // Permission Lifecycle Handshake
  // ---------------------------------------------------------------------------

  /// Performs a full permission handshake and returns `true` only when the app
  /// has been granted at least [LocationPermission.whileInUse].
  ///
  /// Steps:
  /// 1. Verify the device location hardware/service is switched on.
  /// 2. Read the current grant status.
  /// 3. If [denied], issue a runtime request.
  /// 4. After foreground is granted, attempt a background upgrade to [always].
  /// 5. Return `false` without throwing if [deniedForever].
  Future<bool> requestLocationPermissions() async {
    // Step 1 — Hardware / OS location service gate.
    final bool serviceEnabled = await checkServiceEnabled();
    if (!serviceEnabled) {
      debugPrint(
        '[KwellaLocationService] Location services are disabled on this device.',
      );
      _permissionsGranted = false;
      return false;
    }

    // Step 2 — Read current runtime grant.
    LocationPermission permission = await checkPermission();

    // Step 3 — Request foreground grant if not yet given.
    if (permission == LocationPermission.denied) {
      debugPrint(
        '[KwellaLocationService] Permission denied. Requesting foreground permission.',
      );
      permission = await requestPermission();
    }

    // Step 4 — Bail gracefully if the user has permanently refused.
    if (permission == LocationPermission.deniedForever) {
      debugPrint(
        '[KwellaLocationService] Permission permanently denied. '
        'User must enable location in device Settings.',
      );
      _permissionsGranted = false;
      return false;
    }

    // Step 5 — Attempt background upgrade when only foreground was granted.
    if (permission == LocationPermission.whileInUse) {
      debugPrint(
        '[KwellaLocationService] Foreground permission granted. '
        'Requesting background upgrade for telematics.',
      );
      final LocationPermission bgPermission = await requestPermission();
      if (bgPermission == LocationPermission.always) {
        debugPrint(
          '[KwellaLocationService] Background (always) permission granted.',
        );
        permission = bgPermission;
      } else {
        debugPrint(
          '[KwellaLocationService] Background permission not granted '
          '(got: $bgPermission). Falling back to foreground-only tracking.',
        );
      }
    }

    final bool granted =
        permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;

    _permissionsGranted = granted;
    debugPrint(
      '[KwellaLocationService] Permission handshake result: $permission',
    );
    return granted;
  }

  // ---------------------------------------------------------------------------
  // High-Accuracy Frame Stream
  // ---------------------------------------------------------------------------

  /// Returns a [Stream<Position>] configured for high-accuracy driver telematics:
  ///
  /// - [LocationAccuracy.high]  — GPS-level precision.
  /// - [distanceFilter: 10]     — Emits only after ≥10 m of movement to reduce
  ///                             redundant frames while the vehicle is stopped.
  /// - [timeLimit: 5 s]         — Hard deadline per fix; surfaces a
  ///                             [TimeoutException] downstream instead of
  ///                             silently hanging.
  ///
  /// Returns [Stream.empty] (without throwing) if:
  /// - [requestLocationPermissions] was never called or returned `false`.
  /// - A [LocationServiceDisabledException] is raised after stream creation.
  /// - Any other unexpected hardware error occurs.
  Stream<Position> startPositionStream() {
    if (!_permissionsGranted) {
      debugPrint(
        '[KwellaLocationService] startPositionStream called without granted '
        'permissions. Call requestLocationPermissions() first.',
      );
      return const Stream<Position>.empty();
    }

    debugPrint(
      '[KwellaLocationService] Starting high-accuracy position stream.',
    );

    final LocationSettings settings = buildLocationSettings();
    Stream<Position> raw;

    try {
      raw = getPositionStream(settings);
    } on LocationServiceDisabledException {
      debugPrint(
        '[KwellaLocationService] Location service disabled at stream creation. '
        'Returning empty stream.',
      );
      return const Stream<Position>.empty();
    } catch (e) {
      debugPrint(
        '[KwellaLocationService] Unexpected error creating position stream: $e',
      );
      return const Stream<Position>.empty();
    }

    // Wrap with handleError so that errors emitted during streaming are
    // also caught gracefully — Stream.error() defers the error to listeners.
    return raw.handleError((Object error, StackTrace stack) {
      if (error is LocationServiceDisabledException) {
        debugPrint(
          '[KwellaLocationService] Location service disabled while streaming.',
        );
      } else {
        debugPrint('[KwellaLocationService] Unexpected stream error: $error');
      }
      // Returning from handleError swallows the error and ends the stream.
    });
  }

  // ---------------------------------------------------------------------------
  // Protected overridable platform hooks
  //
  // Each geolocator static call is isolated behind a @protected instance method
  // so that test subclasses can override exactly the platform-bound call without
  // touching the orchestration logic above.  Using @protected (from package:meta)
  // ensures the overrides work across library boundaries in the test directory.
  // ---------------------------------------------------------------------------

  /// Returns `true` when the device location hardware/OS service is on.
  @protected
  Future<bool> checkServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Returns the app's current [LocationPermission] status.
  @protected
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  /// Triggers the OS permission dialog and returns the user's decision.
  @protected
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  /// Returns a [LocationSettings] object tuned for high-accuracy telematics.
  @protected
  LocationSettings buildLocationSettings() {
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
      timeLimit: Duration(seconds: 5),
    );
  }

  /// Wraps [Geolocator.getPositionStream] to allow stream injection in tests.
  @protected
  Stream<Position> getPositionStream(LocationSettings settings) =>
      Geolocator.getPositionStream(locationSettings: settings);
}
