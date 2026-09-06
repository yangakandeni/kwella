import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kwella_core/kwella_core.dart';

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
  KwellaRiderController({
    KwellaLocationService? locationService,
    KwellaWebSocketGateway? gateway,
  })  : _locationService = locationService ?? KwellaLocationService.instance,
        _gateway = gateway ?? KwellaWebSocketGateway();

  final KwellaLocationService _locationService;
  final KwellaWebSocketGateway _gateway;
  String? _riderId;
  StreamSubscription<String>? _gatewaySubscription;
  RiderTripState _state = const RiderTripState();
  final StreamController<RiderTripState> _stateController =
      StreamController.broadcast();

  Stream<RiderTripState> get stateStream => _stateController.stream;
  RiderTripState get state => _state;
  Stream<List<Map<String, dynamic>>> get availableBidsStream =>
      stateStream.map((state) => state.availableBids);

  void dispose() {
    _gatewaySubscription?.cancel();
    _gatewaySubscription = null;
    _stateController.close();
  }

  /// Opens the real-time WebSocket connection to the bidding engine and
  /// starts forwarding decoded incoming frames into
  /// [handleIncomingWebSocketEvent]. Must be called (with a valid
  /// [riderId]/[accessToken]) before [requestTrip], [selectBid], or
  /// [submitRating] can actually reach the backend.
  Future<void> connect({
    required String riderId,
    required String accessToken,
  }) async {
    _riderId = riderId;
    await _gateway.connect(accessToken);
    _gatewaySubscription = _gateway.dataStream.listen((raw) {
      try {
        handleIncomingWebSocketEvent(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Malformed/unknown frame — ignore, matches existing tolerant
        // behavior elsewhere in this app.
      }
    });
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
    _pushWebSocketMessage({
      'action': 'requestTrip',
      'riderId': _riderId,
      'pickup_latitude': _state.pickupLat,
      'pickup_longitude': _state.pickupLng,
      'dropoff_latitude': _state.dropoffLat,
      'dropoff_longitude': _state.dropoffLng,
      'passenger_count': _state.passengerCount,
    });
    _emit(_state.copyWith(status: RiderTripStatus.searching));
  }

  void selectBid(String driverId) {
    _pushWebSocketMessage({
      'action': 'selectBid',
      'tripId': _state.tripId,
      'driverId': driverId,
    });
    _emit(_state.copyWith(status: RiderTripStatus.accepted));
  }

  /// Sets the rider's chosen payment method (e.g. `'CASH'`, `'CARD'`).
  void setPaymentMethod(String method) {
    _emit(_state.copyWith(paymentMethod: method));
  }

  /// Sends the rider's post-trip star rating for the driver.
  void submitRating(int rating) {
    _pushWebSocketMessage({
      'action': 'submitRating',
      'tripId': _state.tripId,
      'rating': rating,
      'target': 'DRIVER',
    });
  }

  void _pushWebSocketMessage(Map<String, dynamic> payload) {
    _gateway.send(jsonEncode(payload));
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
      final String? matchedDriverId = payload['driverId'] as String?;
      Map<String, dynamic>? matchedBid;
      if (matchedDriverId != null) {
        for (final bid in _state.bidMetrics) {
          if (bid['driverId'] == matchedDriverId) {
            matchedBid = bid;
            break;
          }
        }
      }

      final String? driverName =
          payload['driverName'] as String? ?? matchedBid?['driverName'] as String?;
      final dynamic ratingRaw =
          payload['rating'] ?? matchedBid?['rating'];
      final String? driverRating = ratingRaw != null ? '$ratingRaw' : null;
      final String? vehicleDescription = _combineVehicleFields(
            payload['vehicleColor'],
            payload['vehicleModel'],
          ) ??
          _combineVehicleFields(
            matchedBid?['vehicleColor'],
            matchedBid?['vehicleModel'],
          );
      final String? licensePlate = payload['licensePlate'] as String? ??
          matchedBid?['licensePlate'] as String?;

      _emit(
        _state.copyWith(
          status: RiderTripStatus.accepted,
          tripId: incomingTripId ?? _state.tripId,
          latestEvent: event,
          driverName: driverName,
          driverRating: driverRating,
          vehicleDescription: vehicleDescription,
          licensePlate: licensePlate,
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

  String? _combineVehicleFields(dynamic color, dynamic model) {
    if (color == null && model == null) {
      return null;
    }
    return '${color ?? ''} ${model ?? ''}'.trim();
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
