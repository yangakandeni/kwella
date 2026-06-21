import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A production-ready, thread-safe WebSocket service wrapper class that manages 
/// connection lifecycle, exponential backoff reconnects, and stream broadcasting.
class KwellaWebSocketService {
  // Singleton pattern for application-wide single instance
  static KwellaWebSocketService _instance = KwellaWebSocketService._internal();
  factory KwellaWebSocketService() => _instance;
  KwellaWebSocketService._internal();

  /// Public getter for the singleton instance
  static KwellaWebSocketService get instance => _instance;

  /// Exposes the real-time bid stream (alias for `stream` to support UI/Riverpod layers)
  Stream<Map<String, dynamic>> get bidStream => stream;

  /// Resets the singleton instance, primarily used for clean unit testing.
  @visibleForTesting
  static void reset() {
    _instance.dispose();
    _instance = KwellaWebSocketService._internal();
  }

  WebSocketChannel? _channel;
  bool _isConnecting = false;
  bool _isDisposed = false;

  // Reconnection backoff times in milliseconds
  final int _minBackoffMs = 1000;      // 1 second
  final int _maxBackoffMs = 30000;     // 30 seconds
  int _currentBackoffMs = 1000;
  Timer? _reconnectTimer;

  // Broadcast stream controller to dispatch decoded incoming updates
  final StreamController<Map<String, dynamic>> _broadcastController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Exposes the real-time message stream to UI listeners and Riverpod state providers
  Stream<Map<String, dynamic>> get stream => _broadcastController.stream;

  /// Check if the connection is currently alive and active
  bool get isConnected => _channel != null;

  /// Initialize and connect to the WebSocket server
  void connect() {
    if (_isDisposed) {
      debugPrint('[KwellaWebSocketService] Cannot connect. Service is disposed.');
      return;
    }
    if (_isConnecting) {
      debugPrint('[KwellaWebSocketService] Connection attempt already in progress.');
      return;
    }
    if (_channel != null) {
      debugPrint('[KwellaWebSocketService] Already connected.');
      return;
    }

    final url = dotenv.env['API_BASE_URL_WS'];
    if (url == null || url.isEmpty) {
      debugPrint('[KwellaWebSocketService] Error: API_BASE_URL_WS is not set in environment.');
      return;
    }

    _isConnecting = true;
    debugPrint('[KwellaWebSocketService] Connecting to WebSocket: $url');

    try {
      // Connect using IOWebSocketChannel
      final uri = Uri.parse(url);
      _channel = IOWebSocketChannel.connect(uri);
      _isConnecting = false;

      // Listen to the incoming stream
      _channel!.stream.listen(
        (dynamic message) {
          _handleMessage(message);
        },
        onError: (dynamic error) {
          debugPrint('[KwellaWebSocketService] Stream error encountered: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[KwellaWebSocketService] Stream connection completed (closed by host).');
          _handleDisconnect();
        },
        cancelOnError: true,
      );

      debugPrint('[KwellaWebSocketService] Connection established successfully.');
    } catch (e) {
      _isConnecting = false;
      debugPrint('[KwellaWebSocketService] Connection exception occurred: $e');
      _handleDisconnect();
    }
  }

  /// Process the raw incoming message, parsing to JSON map
  void _handleMessage(dynamic message) {
    // A successful message receipt confirms connection is alive; reset backoff
    _currentBackoffMs = _minBackoffMs;

    if (message is String) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic>) {
          _broadcastController.add(decoded);
        } else {
          debugPrint('[KwellaWebSocketService] Decoded JSON is not a Map: $message');
        }
      } catch (e) {
        debugPrint('[KwellaWebSocketService] Failed to parse JSON message: $e. Raw: $message');
      }
    } else {
      debugPrint('[KwellaWebSocketService] Received message is not a String: $message');
    }
  }

  /// Disconnect state management and scheduling automatic reconnection
  void _handleDisconnect() {
    if (_isDisposed) return;

    // Clean up current channel reference
    try {
      _channel?.sink.close();
    } catch (e) {
      debugPrint('[KwellaWebSocketService] Error closing sink: $e');
    }
    _channel = null;

    // Cancel any existing reconnect timers to prevent multiple concurrent routines
    _reconnectTimer?.cancel();

    debugPrint('[KwellaWebSocketService] Disconnected. Scheduling reconnect in ${_currentBackoffMs / 1000}s.');
    _reconnectTimer = Timer(Duration(milliseconds: _currentBackoffMs), () {
      // Exponential backoff logic with maximum ceiling
      _currentBackoffMs = min(_currentBackoffMs * 2, _maxBackoffMs);
      connect();
    });
  }

  /// Dispatch Driver Bid payload down the WebSocket sink
  Future<void> sendDriverBid({
    required String driverId,
    required String riderId,
    required double amount,
    required String estimatedPickup,
    required String broadcastPk,
  }) async {
    final currentChannel = _channel;
    if (currentChannel == null) {
      final errorMsg = 'Cannot send driver bid. WebSocket is not connected.';
      debugPrint('[KwellaWebSocketService] $errorMsg');
      throw StateError(errorMsg);
    }

    final payload = {
      'action': 'sendBid',
      'driverId': driverId,
      'riderId': riderId,
      'amount': amount.toStringAsFixed(2),
      'estimatedPickup': estimatedPickup,
      'broadcastPk': broadcastPk,
    };

    try {
      final jsonPayload = jsonEncode(payload);
      debugPrint('[KwellaWebSocketService] Dispatching bid: $jsonPayload');
      currentChannel.sink.add(jsonPayload);
    } catch (e) {
      debugPrint('[KwellaWebSocketService] Exception while dispatching bid: $e');
      rethrow;
    }
  }

  /// Clean up resources, close connections, and terminate broadcast streams
  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (e) {
      debugPrint('[KwellaWebSocketService] Error closing sink during dispose: $e');
    }
    _channel = null;
    _broadcastController.close();
    debugPrint('[KwellaWebSocketService] Service instance disposed.');
  }
}
