import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final kwellaWebSocketGatewayProvider = Provider((ref) => KwellaWebSocketGateway());
/// Manages an AWS API Gateway v2 WebSocket connection for the Kwella
/// real-time bidding engine.
///
/// Usage:
/// ```dart
/// final gateway = KwellaWebSocketGateway();
/// await gateway.connect(wsEndpointUrl, accessToken);
/// gateway.dataStream.listen((frame) { /* process JSON frame */ });
/// // ...
/// await gateway.disconnect();
/// ```
class KwellaWebSocketGateway {
  WebSocketChannel? _channel;
  StreamController<String>? _controller;

  /// Returns `true` when an active WebSocket connection is open.
  bool get isConnected => _channel != null;

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

  /// Opens a WebSocket connection to [endpointUrl] (an AWS API Gateway v2
  /// WebSocket stage URL, e.g. `wss://oronlku519.execute-api.af-south-1.amazonaws.com/production`).
  ///
  /// [accessToken] is injected as the `Authorization` query parameter so the
  /// API Gateway WebSocket authorizer can validate the Cognito JWT on
  /// `$connect`.
  ///
  /// Calling [connect] while already connected will silently disconnect
  /// the existing channel first.
  Future<void> connect(String endpointUrl, String accessToken) async {
    // Close any existing connection cleanly before opening a new one.
    if (_channel != null) {
      await disconnect();
    }

    // Construct the authenticated WebSocket URI.
    final uri = Uri.parse(endpointUrl).replace(
      queryParameters: {'Authorization': accessToken},
    );

    _controller = StreamController<String>.broadcast();
    _channel = WebSocketChannel.connect(uri);

    // Await the protocol handshake to surface connection errors early.
    await _channel!.ready;

    // Forward incoming frames onto the broadcast controller.
    _channel!.stream.listen(
      (dynamic frame) {
        if (!_controller!.isClosed) {
          _controller!.add(frame.toString());
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!_controller!.isClosed) {
          _controller!.addError(error, stack);
        }
      },
      onDone: () {
        // The channel closed remotely — propagate the closure.
        if (!_controller!.isClosed) {
          _controller!.close();
        }
        _channel = null;
      },
      cancelOnError: false,
    );
  }

  /// Sends a raw JSON [payload] string over the open WebSocket channel.
  ///
  /// Throws a [StateError] if [connect] has not been called first.
  void send(String payload) {
    if (_channel == null) {
      throw StateError(
          'KwellaWebSocketGateway: cannot send — not connected.');
    }
    _channel!.sink.add(payload);
  }

  /// Closes the WebSocket connection and releases all stream resources.
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;

    if (_controller != null && !_controller!.isClosed) {
      await _controller!.close();
    }
    _controller = null;
  }
}
