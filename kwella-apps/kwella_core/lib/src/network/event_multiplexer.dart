import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'websocket_gateway.dart';
import 'bidding_events.dart';

/// Provides a unified, strongly-typed stream of bidding events by multiplexing
/// the raw JSON payload frames from the WebSocket gateway.
final kwellaEventMultiplexerProvider = StreamProvider<KwellaBiddingEvent>((ref) async* {
  final gateway = ref.watch(kwellaWebSocketGatewayProvider);

  if (!gateway.isConnected) {
    // We yield nothing if not connected yet, but we wait for it to be connected
    // This is handled by whoever manages connection lifecycle.
    // If you need to wait, you might just yield nothing. 
    // Usually the stream will start yielding once data comes in.
  }

  try {
    await for (final rawFrame in gateway.dataStream) {
      try {
        final Map<String, dynamic> jsonMap = jsonDecode(rawFrame);
        final event = KwellaBiddingEvent.fromJson(jsonMap);
        yield event;
      } catch (e) {
        // Silently swallow parse errors or log them, preventing the whole stream from crashing
        // in case of malformed JSON from the server.
        // TODO: integrate proper logging here.
      }
    }
  } on StateError {
    // If the dataStream is not ready, this catches the exception.
    // Stream will close or retry.
  }
});
