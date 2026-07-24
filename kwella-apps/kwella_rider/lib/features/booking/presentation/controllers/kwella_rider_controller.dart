import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../location/services/kwella_location_service.dart';
import 'rider_trip_state.dart';

final kwellaRiderControllerProvider =
    Provider.autoDispose<KwellaRiderController>((ref) {
      final controller = KwellaRiderController();
      ref.onDispose(controller.dispose);
      return controller;
    });

final riderTripStateProvider = StreamProvider.autoDispose<RiderTripState>((
  ref,
) {
  final controller = ref.watch(kwellaRiderControllerProvider);
  return controller.stateStream;
});

final availableBidsProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      final controller = ref.watch(kwellaRiderControllerProvider);
      return controller.availableBidsStream;
    });

class KwellaRiderController {
  KwellaRiderController({KwellaLocationService? locationService})
      : _locationService = locationService ?? KwellaLocationService.instance;

  final KwellaLocationService _locationService;
  RiderTripState _state = const RiderTripState();
  final StreamController<RiderTripState> _stateController =
      StreamController.broadcast();
  StreamSink<String>? _webSocketSink;

  Stream<RiderTripState> get stateStream => _stateController.stream;
  RiderTripState get state => _state;
  Stream<List<Map<String, dynamic>>> get availableBidsStream =>
      stateStream.map((state) => state.availableBids);

  void dispose() {
    _webSocketSink = null;
    _stateController.close();
  }

  void connectWebSocketSink(StreamSink<String> sink) {
    _webSocketSink = sink;
  }

  void _emit(RiderTripState nextState) {
    _state = nextState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void setPassengerCount(int count) {
    if (count < 1 || count > 6) {
      return;
    }
    _emit(_state.copyWith(passengerCount: count));
  }

  /// Updates the pickup point. [lat]/[lng] should be supplied when the rider
  /// picked a Places suggestion, so later autocomplete lookups (for either
  /// field) can bias their results toward this coordinate; free-text edits
  /// omit them and keep whatever coordinate was last resolved.
  void updatePickupLocation(String pickupLocation, {double? lat, double? lng}) {
    _emit(
      _state.copyWith(
        pickupLocation: pickupLocation,
        pickupLocationStatus: PickupLocationStatus.resolved,
        pickupLat: lat,
        pickupLng: lng,
      ),
    );
  }

  /// Defaults the pickup point to the rider's current device location (or
  /// the emulator/simulator's mocked fix during development) via
  /// [KwellaLocationService]. Falls back to [PickupLocationStatus.unavailable]
  /// — leaving the pickup field open for manual entry — if location access is
  /// denied, disabled, or the lookup otherwise fails.
  Future<void> resolvePickupLocation() async {
    _emit(_state.copyWith(pickupLocationStatus: PickupLocationStatus.loading));

    final bool granted = await _locationService.requestLocationPermissions();
    if (!granted) {
      _emit(
        _state.copyWith(pickupLocationStatus: PickupLocationStatus.unavailable),
      );
      return;
    }

    final Position? position = await _locationService.getCurrentPosition();
    if (position == null) {
      _emit(
        _state.copyWith(pickupLocationStatus: PickupLocationStatus.unavailable),
      );
      return;
    }

    final String? address = await _locationService.resolveAddressLabel(
      position.latitude,
      position.longitude,
    );
    final String label = address ??
        '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';

    _emit(
      _state.copyWith(
        pickupLocation: label,
        pickupLocationStatus: PickupLocationStatus.resolved,
        pickupLat: position.latitude,
        pickupLng: position.longitude,
      ),
    );
  }

  /// Updates the dropoff point. [lat]/[lng] should be supplied when the rider
  /// picked a Places suggestion with already-known coordinates (e.g. a
  /// previous destination), so future routing/distance calculations don't
  /// need a fresh Places lookup; free-text edits omit them and keep whatever
  /// coordinate was last resolved.
  void updateDropoffLocation(String dropoffLocation, {double? lat, double? lng}) {
    _emit(
      _state.copyWith(
        dropoffLocation: dropoffLocation,
        dropoffLat: lat,
        dropoffLng: lng,
      ),
    );
  }

  void requestTrip() {
    _emit(_state.copyWith(status: RiderTripStatus.searching));
    // Live WebSocket lookup loop should begin here in the rider booking flow.
  }

  void selectBid(String driverId) {
    _pushWebSocketMessage({
      'action': 'selectBid',
      'tripId': _state.tripId,
      'driverId': driverId,
    });
    _emit(_state.copyWith(status: RiderTripStatus.accepted));
  }

  void _pushWebSocketMessage(Map<String, dynamic> payload) {
    final String message = jsonEncode(payload);
    _webSocketSink?.add(message);
  }

  void handleIncomingWebSocketEvent(Map<String, dynamic> payload) {
    final String? action = payload['action'] as String?;
    final String? status = payload['status'] as String?;
    final String? incomingTripId = payload['tripId'] as String?;
    final Map<String, dynamic> event = Map.unmodifiable(payload);

    if (action == 'driverBidReceived') {
      final List<Map<String, dynamic>> newBidMetrics =
          List<Map<String, dynamic>>.from(_state.bidMetrics);
      if (payload.containsKey('bidMetrics')) {
        final dynamic bidMetrics = payload['bidMetrics'];
        if (bidMetrics is List) {
          newBidMetrics.addAll(bidMetrics.whereType<Map<String, dynamic>>());
        }
      }
      _emit(
        _state.copyWith(
          status: RiderTripStatus.biddingOpen,
          tripId: incomingTripId ?? _state.tripId,
          bidMetrics: newBidMetrics,
          latestEvent: event,
        ),
      );
      return;
    }

    if (action == 'tripMatchConfirmed') {
      _emit(
        _state.copyWith(
          status: RiderTripStatus.accepted,
          tripId: incomingTripId ?? _state.tripId,
          latestEvent: event,
        ),
      );
      return;
    }

    if (action == 'geofenceTrigger') {
      _emit(
        _state.copyWith(status: RiderTripStatus.arrived, latestEvent: event),
      );
      return;
    }

    if (action == 'liveDriverLocation') {
      final DriverLocation? liveLocation = _parseDriverLocationFromPayload(
        payload,
      );
      if (liveLocation != null) {
        _emit(
          _state.copyWith(
            currentDriverLocation: liveLocation,
            latestEvent: event,
          ),
        );
      }
      return;
    }

    if (status == 'WalletSettled') {
      _emit(
        _state.copyWith(status: RiderTripStatus.completed, latestEvent: event),
      );
      return;
    }
  }

  DriverLocation? _parseDriverLocationFromPayload(
    Map<String, dynamic> payload,
  ) {
    final dynamic latitude = payload['latitude'];
    final dynamic longitude = payload['longitude'];
    if (latitude is num && longitude is num) {
      return DriverLocation(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      );
    }
    return null;
  }
}
