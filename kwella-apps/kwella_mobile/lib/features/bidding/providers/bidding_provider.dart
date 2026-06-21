import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bidding_state.dart';
import '../services/kwella_websocket_service.dart';

/// A Riverpod StateNotifier that manages real-time marketplace bidding state.
class BiddingNotifier extends StateNotifier<BiddingState> {
  final KwellaWebSocketService _wsService;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  final List<Map<String, dynamic>> _bidBuffer = [];

  BiddingNotifier({KwellaWebSocketService? wsService})
      : _wsService = wsService ?? KwellaWebSocketService.instance,
        super(const BiddingState.initial()) {
    _connectAndSubscribe();
  }

  void _connectAndSubscribe() {
    state = const BiddingState.connecting();
    try {
      _wsService.connect();
      _subscription = _wsService.bidStream.listen(
        _onMessageReceived,
        onError: (dynamic error) {
          state = BiddingState.error(message: error.toString());
        },
        cancelOnError: false,
      );
    } catch (e) {
      state = BiddingState.error(message: e.toString());
    }
  }

  void _onMessageReceived(Map<String, dynamic> data) {
    if (_isDriverBid(data)) {
      final unpacked = _unpackBid(data);
      _bidBuffer.add(unpacked);
      state = BiddingState.active(activeBids: List.unmodifiable(_bidBuffer));
    }
  }

  /// Check if the map event matches our normalized driver bid schema keys.
  bool _isDriverBid(Map<String, dynamic> data) {
    final hasDriver = data.containsKey('driverId') || data.containsKey('driver_id');
    final hasRider = data.containsKey('riderId') || data.containsKey('rider_id');
    final hasAmount = data.containsKey('amount') || data.containsKey('counter_fare');
    return hasDriver && hasRider && hasAmount;
  }

  /// Unpacks the driver bid payload into standardized camelCase keys.
  Map<String, dynamic> _unpackBid(Map<String, dynamic> data) {
    return {
      'driverId': data['driverId'] ?? data['driver_id'],
      'riderId': data['riderId'] ?? data['rider_id'],
      'amount': data['amount'] ?? data['counter_fare'],
      'estimatedPickup': data['estimatedPickup'] ?? data['estimated_pickup'] ?? '',
      'broadcastPk': data['broadcastPk'] ?? data['broadcast_pk'] ?? '',
    };
  }

  @override
  void dispose() {
    // Gracefully close and cancel stream subscription to guarantee no memory leaks
    _subscription?.cancel();
    super.dispose();
  }
}

/// A global provider exposing the BiddingNotifier and its BiddingState.
final biddingProvider = StateNotifierProvider<BiddingNotifier, BiddingState>((ref) {
  return BiddingNotifier();
});
