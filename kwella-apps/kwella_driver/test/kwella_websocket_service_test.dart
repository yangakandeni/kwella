import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:kwella_driver/features/bidding/services/kwella_websocket_service.dart';

void main() {
  HttpServer? server;
  final List<WebSocket> activeSockets = [];

  setUp(() async {
    // Start a local loopback WebSocket server
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        activeSockets.add(socket);
        socket.listen((dynamic message) {
          if (message is String) {
            try {
              final data = jsonDecode(message);
              // Echo payload back to mock the AWS synchronous acknowledgment
              socket.add(jsonEncode(data));
            } catch (e) {
              socket.addError(e);
            }
          }
        });
      }
    });

    // Load mock environment variables
    dotenv.testLoad(fileInput: 'API_BASE_URL_WS=ws://${server!.address.address}:${server!.port}');
  });

  tearDown(() async {
    for (final socket in activeSockets) {
      await socket.close();
    }
    activeSockets.clear();
    await server?.close(force: true);
    
    // Reset service singleton for subsequent tests
    KwellaWebSocketService.reset();
  });

  test('KwellaWebSocketService connects, sends driver bid, and receives broadcast', () async {
    final service = KwellaWebSocketService();
    
    service.connect();
    
    // Wait for the connection to establish
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(service.isConnected, isTrue);

    final completer = Completer<Map<String, dynamic>>();
    final subscription = service.stream.listen((data) {
      if (!completer.isCompleted) {
        completer.complete(data);
      }
    });

    // Send driver bid
    await service.sendDriverBid(
      driverId: 'drv_123',
      riderId: 'rdr_456',
      amount: 150.50,
      estimatedPickup: '5 mins',
      broadcastPk: 'bcast_789',
    );

    // Wait for synchronous broadcast echo-back
    final received = await completer.future.timeout(const Duration(seconds: 3));
    expect(received['action'], equals('sendBid'));
    expect(received['driverId'], equals('drv_123'));
    expect(received['riderId'], equals('rdr_456'));
    expect(received['amount'], equals('150.50'));
    expect(received['estimatedPickup'], equals('5 mins'));
    expect(received['broadcastPk'], equals('bcast_789'));

    await subscription.cancel();
  });

  test('KwellaWebSocketService automatically reconnects upon connection drop', () async {
    final service = KwellaWebSocketService();
    
    service.connect();
    
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(service.isConnected, isTrue);

    // Close the server-side socket to trigger drop
    if (activeSockets.isNotEmpty) {
      await activeSockets.first.close();
    }

    // Service should detect disconnect internally
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(service.isConnected, isFalse);

    // Initial backoff is 1s, so wait 1.5s for reconnect to execute
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(service.isConnected, isTrue);
  });
}
