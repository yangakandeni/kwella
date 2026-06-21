import 'dart:async';

import 'rider_trip_state.dart';

class KwellaRiderController {
  RiderTripState _state = const RiderTripState();
  final StreamController<RiderTripState> _stateController =
      StreamController.broadcast();

  Stream<RiderTripState> get stateStream => _stateController.stream;
  RiderTripState get state => _state;

  void dispose() {
    _stateController.close();
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

  void handleIncomingWebSocketEvent(Map<String, dynamic> payload) {
    final String? action = payload['action'] as String?;
    final String? status = payload['status'] as String?;
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
          bidMetrics: newBidMetrics,
          latestEvent: event,
        ),
      );
      return;
    }

    if (action == 'tripMatchConfirmed') {
      _emit(
        _state.copyWith(status: RiderTripStatus.accepted, latestEvent: event),
      );
      return;
    }

    if (action == 'geofenceTrigger') {
      _emit(
        _state.copyWith(status: RiderTripStatus.arrived, latestEvent: event),
      );
      return;
    }

    if (status == 'WalletSettled') {
      _emit(
        _state.copyWith(status: RiderTripStatus.completed, latestEvent: event),
      );
      return;
    }
  }
}
