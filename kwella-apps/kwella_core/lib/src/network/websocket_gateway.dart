import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/environment.dart';

/// Riverpod provider that vends a [KwellaWebSocketGateway] pre-configured
/// with the production [KwellaEnvironment.webSocketEndpointUrl].
///
/// Override this provider in tests using `ProviderContainer(overrides: [...])`.
final kwellaWebSocketGatewayProvider = Provider<KwellaWebSocketGateway>(
  (ref) => KwellaWebSocketGateway(
    endpointUrl: KwellaEnvironment.current.webSocketEndpointUrl,
  ),
);

/// Riverpod stream provider exposing the live [WebSocketStatus] of the
/// gateway vended by [kwellaWebSocketGatewayProvider].
///
/// UI layers can watch this to render a "Connecting..." banner whenever
/// the connection drops and an automatic reconnect attempt is underway.
final kwellaWebSocketStatusProvider = StreamProvider<WebSocketStatus>((ref) {
  final gateway = ref.watch(kwellaWebSocketGatewayProvider);
  return gateway.statusStream;
});

/// Connection lifecycle states for [KwellaWebSocketGateway].
enum WebSocketStatus {
  disconnected,
  connecting,
  connected,
}

/// Manages an AWS API Gateway v2 WebSocket connection for the Kwella
/// real-time bidding engine.
///
/// Instantiated by [kwellaWebSocketGatewayProvider] with the production
/// [KwellaEnvironment.webSocketEndpointUrl].  Pass a different [endpointUrl]
/// to the constructor (or override the provider) to target a different stage
/// (e.g. staging, local mock server).
///
/// Unexpected socket closures/errors trigger automatic reconnection with
/// exponential backoff (2s, 4s, 8s, capped at 16s), and any [send] calls
/// made while disconnected are journaled and flushed in order once the
/// connection is re-established.
///
/// Usage:
/// ```dart
/// final gateway = KwellaWebSocketGateway();
/// await gateway.connect(accessToken);          // uses configured endpointUrl
/// gateway.dataStream.listen((frame) { /* process JSON frame */ });
/// // ...
/// await gateway.disconnect();
/// ```
class KwellaWebSocketGateway {
  /// The AWS API Gateway v2 WebSocket stage URL that this gateway targets.
  ///
  /// Defaults to [KwellaEnvironment.current]'s `webSocketEndpointUrl` when
  /// constructed without an explicit value — i.e. the stage selected by the
  /// `KWELLA_ENV` compile-time define (`local` mock orchestrator, `staging`,
  /// otherwise production). Directly defaulting to [kWebSocketEndpointUrl]
  /// here would silently send `--dart-define=KWELLA_ENV=local` builds at the
  /// live production stack.
  final String endpointUrl;

  static const Duration _initialBackoff = Duration(seconds: 2);
  static const Duration _maxBackoff = Duration(seconds: 16);

  WebSocketChannel? _channel;
  StreamController<String>? _controller;
  final StreamController<WebSocketStatus> _statusController =
      StreamController<WebSocketStatus>.broadcast();

  WebSocketStatus _status = WebSocketStatus.disconnected;
  int _retryCount = 0;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;
  String? _lastAccessToken;
  String? _lastOverrideEndpointUrl;

  /// For testing/simulation purposes: stores raw JSON payloads sent via [send].
  final List<String> sentMessages = [];

  /// Outbound payloads submitted via [send] while disconnected, held in
  /// chronological order until the next successful reconnection flushes them.
  final List<String> _outboundJournal = [];

  KwellaWebSocketGateway({
    String? endpointUrl,
  }) : endpointUrl =
            endpointUrl ?? KwellaEnvironment.current.webSocketEndpointUrl;

  /// Returns `true` when an active WebSocket connection is open.
  bool get isConnected => _channel != null;

  /// The current [WebSocketStatus] of this gateway.
  WebSocketStatus get status => _status;

  /// Broadcast stream of [WebSocketStatus] transitions, suitable for driving
  /// a UI "Connecting..." banner. See [kwellaWebSocketStatusProvider].
  Stream<WebSocketStatus> get statusStream => _statusController.stream;

  /// Exposes decoded UTF-8 JSON frames emitted by the backend bidding engine
  /// as a broadcast stream.
  ///
  /// Subscribers receive raw JSON strings that can be decoded with
  /// `dart:convert jsonDecode`.
  Stream<String> get dataStream {
    final ctrl = _controller;
    if (ctrl == null || ctrl.isClosed) {
      throw StateError(
          'KwellaWebSocketGateway: call connect() before listening to dataStream.');
    }
    return ctrl.stream;
  }

  /// Opens a WebSocket connection.
  ///
  /// If [overrideEndpointUrl] is omitted, [endpointUrl] (set at construction
  /// time from [KwellaEnvironment]) is used.  Pass an explicit value only when
  /// you need to direct a single call to a different stage.
  ///
  /// [accessToken] is injected as the `Authorization` query parameter so the
  /// API Gateway WebSocket authorizer can validate the Cognito JWT on
  /// `$connect`.
  ///
  /// Calling [connect] while already connected will silently disconnect
  /// the existing channel first. A successful [connect] cancels any pending
  /// automatic reconnect attempt and re-arms auto-reconnect for future drops.
  Future<void> connect(String accessToken, {String? overrideEndpointUrl}) async {
    _manualDisconnect = false;
    _lastAccessToken = accessToken;
    _lastOverrideEndpointUrl = overrideEndpointUrl;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (kDebugMode) {
      debugPrint('[KwellaWebSocketGateway] Initiating connection...');
    }
    await _openConnection(accessToken, overrideEndpointUrl: overrideEndpointUrl);
  }

  Future<void> _openConnection(String accessToken,
      {String? overrideEndpointUrl}) async {
    // Close any existing connection cleanly before opening a new one.
    if (_channel != null) {
      await _closeChannel();
    }

    _setStatus(WebSocketStatus.connecting);

    final target = overrideEndpointUrl ?? endpointUrl;
    final parsedUri = Uri.parse(target);

    if (kDebugMode) {
      debugPrint('[KwellaWebSocketGateway] Connecting to: $target');
    }

    // Construct the authenticated WebSocket URI, preserving any query parameters.
    final uri = parsedUri.replace(
      queryParameters: {
        ...parsedUri.queryParameters,
        'Authorization': accessToken,
      },
    );

    _controller = StreamController<String>.broadcast();
    _channel = WebSocketChannel.connect(uri);

    try {
      // Await the protocol handshake to surface connection errors early.
      await _channel!.ready;
      if (kDebugMode) {
        debugPrint('[KwellaWebSocketGateway] ✓ Connected successfully');
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[KwellaWebSocketGateway] ✗ Connection failed: $error');
        debugPrint('Stack trace: $stackTrace');
      }
      _channel = null;
      _setStatus(WebSocketStatus.disconnected);
      _scheduleReconnect();
      rethrow;
    }

    // Handshake succeeded — reset backoff and flush anything journaled
    // while we were disconnected.
    _retryCount = 0;
    _setStatus(WebSocketStatus.connected);
    _flushOutboundJournal();

    // Forward incoming frames onto the broadcast controller.
    _channel!.stream.listen(
      (dynamic frame) {
        if (kDebugMode) {
          debugPrint('[KwellaWebSocketGateway] ← Received frame: $frame');
        }
        if (!_controller!.isClosed) {
          _controller!.add(frame.toString());
        }
      },
      onError: (Object error, StackTrace stack) {
        if (kDebugMode) {
          debugPrint('[KwellaWebSocketGateway] ✗ Stream error: $error');
          debugPrint('Stack trace: $stack');
        }
        if (!_controller!.isClosed) {
          _controller!.addError(error, stack);
        }
        _handleUnexpectedClosure();
      },
      onDone: () {
        if (kDebugMode) {
          debugPrint('[KwellaWebSocketGateway] Connection closed by remote peer');
        }
        // The channel closed remotely — propagate the closure.
        if (!_controller!.isClosed) {
          _controller!.close();
        }
        _handleUnexpectedClosure();
      },
      cancelOnError: false,
    );
  }

  /// Reacts to a socket closure/error that was not initiated by [disconnect].
  void _handleUnexpectedClosure() {
    _channel = null;
    if (_manualDisconnect) return;
    if (kDebugMode) {
      debugPrint('[KwellaWebSocketGateway] Unexpected closure detected; scheduling reconnect...');
    }
    _setStatus(WebSocketStatus.disconnected);
    _scheduleReconnect();
  }

  /// Schedules the next reconnect attempt using exponential backoff:
  /// `delay = min(initialDelay * pow(2, retryCount), maxDelay)`.
  void _scheduleReconnect() {
    if (_manualDisconnect || _lastAccessToken == null) return;

    _reconnectTimer?.cancel();
    final delayMs = min(
      _initialBackoff.inMilliseconds * pow(2, _retryCount).toInt(),
      _maxBackoff.inMilliseconds,
    );
    _retryCount++;

    if (kDebugMode) {
      debugPrint('[KwellaWebSocketGateway] Scheduling reconnect attempt #$_retryCount in ${delayMs}ms');
    }

    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_manualDisconnect || _lastAccessToken == null) return;
      if (kDebugMode) {
        debugPrint('[KwellaWebSocketGateway] Attempting reconnect...');
      }
      _openConnection(_lastAccessToken!,
          overrideEndpointUrl: _lastOverrideEndpointUrl);
    });
  }

  /// Sends a raw JSON [payload] string over the open WebSocket channel.
  ///
  /// If currently disconnected, [payload] is appended to the outbound
  /// journal instead of throwing, and will be flushed in chronological
  /// order once the connection is re-established.
  void send(String payload) {
    if (_channel == null) {
      if (kDebugMode) {
        debugPrint('[KwellaWebSocketGateway] Channel disconnected; journaling message: $payload');
      }
      _outboundJournal.add(payload);
      return;
    }
    if (kDebugMode) {
      debugPrint('[KwellaWebSocketGateway] → Sending: $payload');
    }
    sentMessages.add(payload);
    _channel!.sink.add(payload);
  }

  /// Replays journaled payloads (oldest first) through [send], then clears
  /// the journal.
  void _flushOutboundJournal() {
    if (_outboundJournal.isEmpty) return;
    final pending = List<String>.of(_outboundJournal);
    _outboundJournal.clear();
    for (final payload in pending) {
      send(payload);
    }
  }

  /// For testing/simulation purposes: allows manual injection of an incoming
  /// JSON frame onto the [dataStream] broadcast stream.
  void simulateIncomingFrame(String payload) {
    final ctrl = _controller;
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(payload);
    }
  }

  /// Closes the WebSocket connection and releases all stream resources.
  ///
  /// This is treated as an intentional disconnect — no automatic reconnect
  /// attempt is scheduled afterwards.
  Future<void> disconnect() async {
    if (kDebugMode) {
      debugPrint('[KwellaWebSocketGateway] Disconnecting...');
    }
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _closeChannel();
    _setStatus(WebSocketStatus.disconnected);
  }

  Future<void> _closeChannel() async {
    await _channel?.sink.close();
    _channel = null;

    if (_controller != null && !_controller!.isClosed) {
      await _controller!.close();
    }
    _controller = null;
  }

  void _setStatus(WebSocketStatus newStatus) {
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
  }
}
