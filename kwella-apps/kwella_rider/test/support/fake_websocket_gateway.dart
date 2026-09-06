import 'dart:async';
import 'dart:convert';

import 'package:kwella_core/kwella_core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FakeWebSocketGateway
// Test double for [KwellaWebSocketGateway] — subclasses it (rather than
// mocking it) so KwellaRiderController's requestTrip/selectBid/submitRating
// (and any other outgoing frame) can be asserted against real sent JSON
// without performing any real I/O, and incoming frames can be injected
// deterministically via [simulateIncomingFrame]. Mirrors the
// `_InstrumentedGateway` pattern documented in kwella_core's
// e2e_live_bidding_integration_test.dart.
//
// Shared by kwella_rider_controller_test.dart and
// integration_test/rider_full_flow_e2e_test.dart so both exercise the exact
// same fake rather than two independently-maintained copies.
// ─────────────────────────────────────────────────────────────────────────────
class FakeWebSocketGateway extends KwellaWebSocketGateway {
  final List<Map<String, dynamic>> sentPayloads = [];
  bool connected = false;
  String? lastAccessToken;
  final StreamController<String> _incomingController =
      StreamController<String>.broadcast();

  @override
  bool get isConnected => connected;

  @override
  Stream<String> get dataStream => _incomingController.stream;

  @override
  Future<void> connect(
    String accessToken, {
    String? overrideEndpointUrl,
  }) async {
    connected = true;
    lastAccessToken = accessToken;
  }

  @override
  void send(String payload) {
    sentPayloads.add(jsonDecode(payload) as Map<String, dynamic>);
  }

  @override
  void simulateIncomingFrame(String payload) {
    _incomingController.add(payload);
  }

  @override
  Future<void> disconnect() async {
    connected = false;
    await _incomingController.close();
  }
}
