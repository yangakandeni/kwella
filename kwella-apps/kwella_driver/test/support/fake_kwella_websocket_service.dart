import 'dart:async';
import 'dart:convert';

import 'package:kwella_driver/features/bidding/services/kwella_websocket_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A [WebSocketSink] test double that records every `add()` call verbatim
/// (as the raw JSON string), with no real socket I/O.
///
/// Shared by any test double that needs to assert on outgoing WebSocket
/// frames dispatched via `KwellaWebSocketService.sink`.
class FakeWebSocketSink implements WebSocketSink {
  /// Every payload passed to [add], in call order. Only [String] payloads
  /// are recorded — every production call site in this app sends JSON
  /// strings, so a non-string argument would indicate a bug.
  final List<String> sentPayloads = [];

  @override
  void add(dynamic data) {
    if (data is String) sentPayloads.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> get done async {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.drain<void>();
}

/// Shared [KwellaWebSocketService] test double.
///
/// Originally duplicated (in slightly different shapes) across
/// `bidding_provider_test.dart` and `bidding_marketplace_screen_test.dart`;
/// factored out here so every test — including the driver full-flow E2E
/// suite — exercises the exact same fake wiring and doesn't drift.
///
/// - Use [emit] to push an incoming server frame onto [bidStream]/[stream],
///   exactly as `KwellaWebSocketService._handleMessage` would after decoding
///   a raw text frame from the live socket.
/// - Use [emitError] to push a stream error (e.g. to exercise error-handling
///   paths in listeners).
/// - Read [sentPayloads] (raw JSON strings) or [sentMessages] (decoded maps)
///   to assert exactly what was dispatched via `sink.add(...)` — this is the
///   assertion surface for outgoing WebSocket contract frames such as
///   `sendBid`, `driverArrived`, `startTrip`, `confirmArrival`, and
///   `submitRating`.
class FakeKwellaWebSocketService implements KwellaWebSocketService {
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final FakeWebSocketSink _sink = FakeWebSocketSink();

  bool connectCalled = false;
  bool disposeCalled = false;
  bool hasListeners = false;

  FakeKwellaWebSocketService() {
    _controller.onListen = () => hasListeners = true;
    _controller.onCancel = () => hasListeners = false;
  }

  @override
  void connect() {
    connectCalled = true;
  }

  @override
  Stream<Map<String, dynamic>> get stream => _controller.stream;

  @override
  Stream<Map<String, dynamic>> get bidStream => _controller.stream;

  @override
  bool get isConnected => connectCalled && !disposeCalled;

  @override
  Future<void> sendDriverBid({
    required String driverId,
    required String riderId,
    required double amount,
    required String estimatedPickup,
    required String broadcastPk,
  }) async {
    // No-op — none of the current call sites under test exercise this path;
    // sink.add(...) (via [sentPayloads]/[sentMessages]) is the assertion
    // surface for outgoing frames instead.
  }

  @override
  void dispose() {
    disposeCalled = true;
    _controller.close();
  }

  @override
  WebSocketSink get sink => _sink;

  /// Raw JSON strings captured from every `sink.add(...)` call, in order.
  List<String> get sentPayloads => _sink.sentPayloads;

  /// Convenience: [sentPayloads] decoded into maps, in the same order.
  List<Map<String, dynamic>> get sentMessages => sentPayloads
      .map((payload) => jsonDecode(payload) as Map<String, dynamic>)
      .toList();

  /// Pushes an incoming server frame onto [bidStream]/[stream], as if it had
  /// just arrived over the live socket.
  void emit(Map<String, dynamic> data) {
    _controller.add(data);
  }

  /// Pushes a stream error onto [bidStream]/[stream].
  void emitError(Object error) {
    _controller.addError(error);
  }

  /// Closes the underlying broadcast controller. Call in `tearDown` for
  /// tests that don't otherwise dispose the service under test.
  void close() {
    _controller.close();
  }
}
