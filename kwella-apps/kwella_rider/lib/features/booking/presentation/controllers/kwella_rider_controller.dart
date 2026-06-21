import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  void updatePickupLocation(String pickupLocation) {
    _emit(_state.copyWith(pickupLocation: pickupLocation));
  }

  void updateDropoffLocation(String dropoffLocation) {
    _emit(_state.copyWith(dropoffLocation: dropoffLocation));
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
