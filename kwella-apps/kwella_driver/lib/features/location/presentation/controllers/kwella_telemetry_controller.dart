import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bidding/models/active_ride_offer.dart';
import '../../../bidding/services/kwella_websocket_service.dart';
import '../../services/kwella_location_service.dart';

/// State object representing the telemetry, geofencing, and active ride-offer
/// status of the driver.
@immutable
class TelemetryState {
  final bool isTracking;
  final bool isWithinGeofenceRadius;

  /// The currently active ride offer broadcast from the marketplace, or [null]
  /// when no offer is pending (either not yet received or already expired /
  /// accepted).
  final ActiveRideOffer? activeOffer;

  /// Seconds remaining in the current offer countdown window [0–15].
  /// Meaningful only when [activeOffer] is non-null.
  final int offerSecondsRemaining;

  /// Total earnings for the current shift.
  final double dailyEarningsTotal;

  /// The net earnings of the last completed trip.
  final double? lastNetEarnings;

  /// The trip id of the currently active trip once a bid has been selected
  /// by the rider (populated from the `bidSelected` server push), or [null]
  /// when there is no active trip.
  final String? activeTripId;

  /// The bid amount most recently submitted via [submitBid], retained so it
  /// can be echoed back as `final_bid_amount` when [confirmArrival] fires at
  /// the end of the trip. [null] when no bid has been submitted yet.
  final double? pendingBidAmount;

  const TelemetryState({
    required this.isTracking,
    required this.isWithinGeofenceRadius,
    this.activeOffer,
    this.offerSecondsRemaining = 0,
    this.dailyEarningsTotal = 0.0,
    this.lastNetEarnings,
    this.activeTripId,
    this.pendingBidAmount,
  });

  TelemetryState copyWith({
    bool? isTracking,
    bool? isWithinGeofenceRadius,
    // Use a sentinel to allow explicitly nulling activeOffer and lastNetEarnings.
    Object? activeOffer = _sentinel,
    int? offerSecondsRemaining,
    double? dailyEarningsTotal,
    Object? lastNetEarnings = _sentinel,
    Object? activeTripId = _sentinel,
    Object? pendingBidAmount = _sentinel,
  }) {
    return TelemetryState(
      isTracking: isTracking ?? this.isTracking,
      isWithinGeofenceRadius:
          isWithinGeofenceRadius ?? this.isWithinGeofenceRadius,
      activeOffer: identical(activeOffer, _sentinel)
          ? this.activeOffer
          : activeOffer as ActiveRideOffer?,
      offerSecondsRemaining:
          offerSecondsRemaining ?? this.offerSecondsRemaining,
      dailyEarningsTotal: dailyEarningsTotal ?? this.dailyEarningsTotal,
      lastNetEarnings: identical(lastNetEarnings, _sentinel)
          ? this.lastNetEarnings
          : lastNetEarnings as double?,
      activeTripId: identical(activeTripId, _sentinel)
          ? this.activeTripId
          : activeTripId as String?,
      pendingBidAmount: identical(pendingBidAmount, _sentinel)
          ? this.pendingBidAmount
          : pendingBidAmount as double?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TelemetryState &&
          runtimeType == other.runtimeType &&
          isTracking == other.isTracking &&
          isWithinGeofenceRadius == other.isWithinGeofenceRadius &&
          activeOffer == other.activeOffer &&
          offerSecondsRemaining == other.offerSecondsRemaining &&
          dailyEarningsTotal == other.dailyEarningsTotal &&
          lastNetEarnings == other.lastNetEarnings &&
          activeTripId == other.activeTripId &&
          pendingBidAmount == other.pendingBidAmount;

  @override
  int get hashCode => Object.hash(
    isTracking,
    isWithinGeofenceRadius,
    activeOffer,
    offerSecondsRemaining,
    dailyEarningsTotal,
    lastNetEarnings,
    activeTripId,
    pendingBidAmount,
  );

  @override
  String toString() =>
      'TelemetryState('
      'isTracking: $isTracking, '
      'isWithinGeofenceRadius: $isWithinGeofenceRadius, '
      'activeOffer: $activeOffer, '
      'offerSecondsRemaining: $offerSecondsRemaining, '
      'dailyEarningsTotal: $dailyEarningsTotal, '
      'lastNetEarnings: $lastNetEarnings, '
      'activeTripId: $activeTripId, '
      'pendingBidAmount: $pendingBidAmount)';
}

// Sentinel object used to distinguish "not passed" from explicit null in copyWith.
const _sentinel = Object();

// ---------------------------------------------------------------------------
// Offer countdown duration
// ---------------------------------------------------------------------------

const _kOfferCountdownSeconds = 15;

/// Automates real-time driver location tracking by bridging the hardware
/// position stream from [KwellaLocationService] directly into the live
/// WebSocket sink of [KwellaWebSocketService].
///
/// Extended to intercept `"rideOfferAvailable"` marketplace events and
/// manage a 15-second countdown timer that auto-dismisses the offer when
/// it expires.
///
/// Lifecycle:
/// 1. Call [startDriverTracking] with the authenticated driver ID.
/// 2. The controller runs the full location permission handshake.
/// 3. On each GPS frame, a structured `updateLocation` payload is dispatched
///    through the WebSocket sink to the AWS API Gateway telemetry route.
/// 4. When a `rideOfferAvailable` event is received, the offer is parsed,
///    stored in [TelemetryState.activeOffer], and a 15-second ticker starts.
/// 5. Call [stopDriverTracking] to cleanly cancel the stream and halt battery
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

  /// Internal periodic ticker for the ride-offer countdown.
  Timer? _offerCountdownTimer;

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
  }) : _locationService = locationService ?? KwellaLocationService.instance,
       _wsService = wsService ?? KwellaWebSocketService.instance,
       super(
         const TelemetryState(isTracking: false, isWithinGeofenceRadius: false),
       );

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
  /// 5. Also subscribes to the WebSocket stream to intercept geofencing status
  ///    flags and `rideOfferAvailable` marketplace broadcasts.
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
    final bool granted = await _locationService.requestLocationPermissions();

    if (!granted) {
      debugPrint(
        '[KwellaTelemetryController] Location permissions not granted. '
        'Tracking aborted for driver: $driverId',
      );
      return;
    }

    state = state.copyWith(isTracking: true);

    // Step 2 — Subscribe to the hardware position stream.
    _positionSubscription = _locationService.startPositionStream().listen(
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
        debugPrint('[KwellaTelemetryController] Position stream error: $error');
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

    // Step 4 — Intercept WebSocket events for geofencing & ride offers.
    _wsSubscription = _wsService.bidStream.listen(
      (data) {
        final action = data['action'];
        final status = data['status'];

        // --- Wallet settlement --------------------------------------------------
        if (status == 'WalletSettled') {
          debugPrint(
            '[KwellaTelemetryController] WalletSettled status intercepted: $data',
          );
          final double updatedDailyTotal =
              (data['updated_daily_total'] as num?)?.toDouble() ?? 0.0;
          final double netEarnings =
              (data['net_earnings'] as num?)?.toDouble() ?? 0.0;
          state = state.copyWith(
            dailyEarningsTotal: updatedDailyTotal,
            lastNetEarnings: netEarnings,
          );
        }

        // --- Geofencing: ARRIVED flag ------------------------------------------
        final flags = data['flags'];
        if (flags is Map && flags['geofence_status'] == 'ARRIVED') {
          debugPrint(
            '[KwellaTelemetryController] Geofence ARRIVED status intercepted.',
          );
          state = state.copyWith(isWithinGeofenceRadius: true);
        }

        // --- Ride offer: rideOfferAvailable broadcast --------------------------
        if (action == 'rideOfferAvailable') {
          debugPrint(
            '[KwellaTelemetryController] rideOfferAvailable received: $data',
          );
          _handleIncomingRideOffer(data);
        }

        // --- Bid selection: bidSelected push -------------------------------
        if (action == 'bidSelected') {
          debugPrint(
            '[KwellaTelemetryController] bidSelected received: $data',
          );
          state = state.copyWith(activeTripId: data['tripId'] as String?);
        }
      },
      onError: (Object error) {
        debugPrint(
          '[KwellaTelemetryController] WebSocket telemetry subscription error: $error',
        );
      },
    );

    debugPrint(
      '[KwellaTelemetryController] Tracking active for driver: $driverId',
    );
  }

  /// Dispatches a pickup-arrival confirmation event (`driverArrived`) over
  /// the WebSocket channel and resets the local geofence alert state.
  ///
  /// This transitions the trip status `ACCEPTED` → `ARRIVED` on the backend.
  Future<void> driverArrived({required String driverId}) async {
    final payload = jsonEncode({
      'action': 'driverArrived',
      'tripId': state.activeTripId,
      'driverId': driverId,
    });

    debugPrint(
      '[KwellaTelemetryController] Dispatching driverArrived: $payload',
    );
    _wsService.sink.add(payload);

    state = state.copyWith(isWithinGeofenceRadius: false);
  }

  /// Dispatches a `startTrip` event over the WebSocket channel once the
  /// driver begins the trip with the passenger onboard.
  ///
  /// This transitions the trip status `ARRIVED` → `IN_PROGRESS` on the
  /// backend.
  Future<void> startTrip({required String driverId}) async {
    final payload = jsonEncode({
      'action': 'startTrip',
      'driverId': driverId,
      'tripId': state.activeTripId,
    });

    debugPrint('[KwellaTelemetryController] Dispatching startTrip: $payload');
    _wsService.sink.add(payload);
  }

  /// Dispatches a destination-arrival confirmation event (`confirmArrival`)
  /// over the WebSocket channel, including the required [finalBidAmount].
  ///
  /// This transitions the trip status `IN_PROGRESS` → `COMPLETED` on the
  /// backend and triggers payout.
  Future<void> confirmArrival({
    required String driverId,
    required double finalBidAmount,
  }) async {
    final payload = jsonEncode({
      'action': 'confirmArrival',
      'driverId': driverId,
      'tripId': state.activeTripId,
      'final_bid_amount': finalBidAmount,
    });

    debugPrint(
      '[KwellaTelemetryController] Dispatching confirmArrival: $payload',
    );
    _wsService.sink.add(payload);
  }

  /// Dispatches a counter-bid or base fare acceptance bid over the WebSocket channel
  /// and resets the local ride-offer state.
  Future<void> submitBid({
    required String driverId,
    required String tripId,
    required double bidAmount,
  }) async {
    final payload = jsonEncode({
      'action': 'sendBid',
      'driverId': driverId,
      'riderId': state.activeOffer?.riderId,
      'tripId': tripId,
      'amount': bidAmount,
    });

    debugPrint('[KwellaTelemetryController] Dispatching submitBid: $payload');
    _wsService.sink.add(payload);

    _cancelOfferCountdown();
    state = state.copyWith(
      activeOffer: null,
      offerSecondsRemaining: 0,
      pendingBidAmount: bidAmount,
    );
  }

  /// Dispatches a `submitRating` event over the WebSocket channel to rate
  /// the rider at the end of a trip. No push is sent to the other party.
  Future<void> submitRating({
    required String driverId,
    required int rating,
  }) async {
    final payload = jsonEncode({
      'action': 'submitRating',
      'driverId': driverId,
      'tripId': state.activeTripId,
      'rating': rating,
      'target': 'RIDER',
    });

    debugPrint(
      '[KwellaTelemetryController] Dispatching submitRating: $payload',
    );
    _wsService.sink.add(payload);
  }

  /// Handles a user tap on the push notification banner by hydrating an active
  /// ride offer and forcing the WebSocket service to reconnect if needed.
  void handlePushNotificationClick(Map<String, dynamic> data) {
    if (!_wsService.isConnected) {
      debugPrint(
        '[KwellaTelemetryController] WebSocket disconnected. Reconnecting due to push notification click.',
      );
      _wsService.connect();
    }

    try {
      final offer = ActiveRideOffer.fromJson(data);
      _hydrateRideOffer(offer);
    } catch (e) {
      debugPrint(
        '[KwellaTelemetryController] Failed to hydrate offer from push notification: $e',
      );
    }
  }

  /// Resets the last net earnings to null to prevent displaying the toast UI multiple times.
  void clearLastNetEarnings() {
    state = state.copyWith(lastNetEarnings: null);
  }

  /// Cancels the underlying [StreamSubscription] and halts all telemetry
  /// dispatches. Also cancels any active ride-offer countdown timer.
  ///
  /// Safe to call even when tracking is not active.
  void stopDriverTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;

    _wsSubscription?.cancel();
    _wsSubscription = null;

    _cancelOfferCountdown();

    if (mounted) {
      state = state.copyWith(
        isTracking: false,
        isWithinGeofenceRadius: false,
        activeOffer: null,
        offerSecondsRemaining: 0,
        lastNetEarnings: null,
      );
    }

    debugPrint(
      '[KwellaTelemetryController] Tracking stopped. Streams cancelled and geofence flags reset.',
    );
  }

  @override
  void dispose() {
    stopDriverTracking();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Private — ride offer handling
  // ---------------------------------------------------------------------------

  /// Parses the incoming [data] map into an [ActiveRideOffer], stores it in
  /// state, and starts the 15-second countdown timer.
  void _handleIncomingRideOffer(Map<String, dynamic> data) {
    try {
      final offer = ActiveRideOffer.fromJson(data);
      _hydrateRideOffer(offer);
    } catch (e) {
      debugPrint(
        '[KwellaTelemetryController] Failed to parse rideOfferAvailable payload: $e',
      );
    }
  }

  void _hydrateRideOffer(ActiveRideOffer offer) {
    _cancelOfferCountdown();

    state = state.copyWith(
      activeOffer: offer,
      offerSecondsRemaining: _kOfferCountdownSeconds,
    );

    _startOfferCountdown();
  }

  /// Starts a periodic 1-second ticker that decrements [offerSecondsRemaining]
  /// and nulls out [activeOffer] when the countdown reaches zero.
  void _startOfferCountdown() {
    _offerCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _cancelOfferCountdown();
        return;
      }

      final remaining = state.offerSecondsRemaining - 1;

      if (remaining <= 0) {
        // Offer has expired — dismiss it cleanly.
        _cancelOfferCountdown();
        debugPrint(
          '[KwellaTelemetryController] Ride offer expired. Dismissing.',
        );
        state = state.copyWith(activeOffer: null, offerSecondsRemaining: 0);
      } else {
        state = state.copyWith(offerSecondsRemaining: remaining);
      }
    });
  }

  /// Cancels the countdown timer and clears the internal reference.
  void _cancelOfferCountdown() {
    _offerCountdownTimer?.cancel();
    _offerCountdownTimer = null;
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
