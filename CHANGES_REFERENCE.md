# Code Changes Reference

## 1. WebSocket Gateway (`kwella_core/lib/src/network/websocket_gateway.dart`)

### Import Added (Line 3)
```dart
import 'package:flutter/foundation.dart';
```

### Key Changes

#### a) Connection Initiation (Line ~127)
```dart
// Added logging
if (kDebugMode) {
  debugPrint('[KwellaWebSocketGateway] Initiating connection...');
}
```

#### b) Open Connection Method (Lines ~138-158)
```dart
// Added target logging
if (kDebugMode) {
  debugPrint('[KwellaWebSocketGateway] Connecting to: $target');
}

// Added success logging
if (kDebugMode) {
  debugPrint('[KwellaWebSocketGateway] ✓ Connected successfully');
}

// Added error logging
} catch (error, stackTrace) {
  if (kDebugMode) {
    debugPrint('[KwellaWebSocketGateway] ✗ Connection failed: $error');
    debugPrint('Stack trace: $stackTrace');
  }
  // ... rest of error handling
}
```

#### c) Stream Listener (Lines ~178-196)
```dart
// Added frame logging
if (kDebugMode) {
  debugPrint('[KwellaWebSocketGateway] ← Received frame: $frame');
}

// Added error logging
onError: (Object error, StackTrace stack) {
  if (kDebugMode) {
    debugPrint('[KwellaWebSocketGateway] ✗ Stream error: $error');
    debugPrint('Stack trace: $stack');
  }
  // ...
}

// Added done logging
onDone: () {
  if (kDebugMode) {
    debugPrint('[KwellaWebSocketGateway] Connection closed by remote peer');
  }
  // ...
}
```

#### d) Send Method (Lines ~235-242)
```dart
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
```

#### e) Reconnect Scheduling (Lines ~212-228)
```dart
// Added logging
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
```

#### f) Unexpected Closure (Lines ~200-206)
```dart
void _handleUnexpectedClosure() {
  _channel = null;
  if (_manualDisconnect) return;
  if (kDebugMode) {
    debugPrint('[KwellaWebSocketGateway] Unexpected closure detected; scheduling reconnect...');
  }
  _setStatus(WebSocketStatus.disconnected);
  _scheduleReconnect();
}
```

#### g) Disconnect Method (Lines ~268-275)
```dart
Future<void> disconnect() async {
  if (kDebugMode) {
    debugPrint('[KwellaWebSocketGateway] Disconnecting...');
  }
  // ... rest of implementation
}
```

---

## 2. Rider Controller (`kwella_rider/lib/features/booking/presentation/controllers/kwella_rider_controller.dart`)

### Import Added (Line 3)
```dart
import 'package:flutter/foundation.dart';
```

### Key Changes

#### a) Connect Method (Lines ~62-77)
```dart
Future<void> connect({
  required String riderId,
  required String accessToken,
}) async {
  _riderId = riderId;
  if (kDebugMode) {
    debugPrint('[KwellaRiderController] Connecting with riderId=$riderId');
  }
  await _gateway.connect(accessToken);
  _gatewaySubscription = _gateway.dataStream.listen((raw) {
    try {
      handleIncomingWebSocketEvent(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[KwellaRiderController] Failed to parse incoming frame: $e');
        debugPrint('Raw frame: $raw');
      }
    }
  });
}
```

#### b) Request Trip Method (Lines ~163-182)
```dart
void requestTrip({bool autoAccept = false}) {
  final payload = {
    'action': 'requestTrip',
    'riderId': _riderId,
    'pickup_latitude': _state.pickupLat,
    'pickup_longitude': _state.pickupLng,
    'dropoff_latitude': _state.dropoffLat,
    'dropoff_longitude': _state.dropoffLng,
    'passenger_count': _state.passengerCount,
  };
  if (kDebugMode) {
    debugPrint('[KwellaRiderController] Requesting trip with payload: ${jsonEncode(payload)}');
    debugPrint('  - riderId: $_riderId');
    debugPrint('  - pickup: (${_state.pickupLat}, ${_state.pickupLng})');
    debugPrint('  - dropoff: (${_state.dropoffLat}, ${_state.dropoffLng})');
    debugPrint('  - passengers: ${_state.passengerCount}');
  }
  _pushWebSocketMessage(payload);
  _emit(
    _state.copyWith(
      status: RiderTripStatus.searching,
      autoAcceptEnabled: autoAccept,
    ),
  );
}
```

#### c) Handle Driver Bid (Lines ~247-283)
```dart
if (action == 'driverBidReceived') {
  final List<Map<String, dynamic>> newBidMetrics =
      List<Map<String, dynamic>>.from(_state.bidMetrics);
  if (payload.containsKey('bidMetrics')) {
    final dynamic bidMetrics = payload['bidMetrics'];
    if (bidMetrics is List) {
      newBidMetrics.addAll(bidMetrics.whereType<Map<String, dynamic>>());
    }
  }
  if (kDebugMode) {
    debugPrint('[KwellaRiderController] ✓ Received driver bid offer(s)');
    debugPrint('  - tripId: $incomingTripId');
    debugPrint('  - total bids: ${newBidMetrics.length}');
    for (int i = 0; i < newBidMetrics.length; i++) {
      final bid = newBidMetrics[i];
      debugPrint('  - bid[$i]: driver=${bid['driverId']}, fare=${bid['fare'] ?? bid['bidAmount']}');
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
  if (_state.autoAcceptEnabled && newBidMetrics.isNotEmpty) {
    final String? firstDriverId =
        newBidMetrics.first['driverId'] as String?;
    if (firstDriverId != null) {
      if (kDebugMode) {
        debugPrint('[KwellaRiderController] Auto-accepting first bid from $firstDriverId');
      }
      selectBid(firstDriverId);
    }
  }
  return;
}
```

#### d) Trip Broadcast Event (Lines ~286-298)
```dart
if (status == 'TripBroadcast') {
  final fare = _parseFare(payload['calculated_fare']);
  if (kDebugMode) {
    debugPrint('[KwellaRiderController] Trip broadcast: tripId=$incomingTripId, fare=$fare');
  }
  _emit(
    _state.copyWith(
      tripId: incomingTripId ?? _state.tripId,
      offeredFare: fare,
    ),
  );
  return;
}
```

#### e) Fare Updated Event (Lines ~300-313)
```dart
if (status == 'FareUpdated') {
  final fare = _parseFare(payload['base_fare']);
  if (kDebugMode) {
    debugPrint('[KwellaRiderController] Fare updated: tripId=$incomingTripId, newFare=$fare');
  }
  _emit(
    _state.copyWith(
      tripId: incomingTripId ?? _state.tripId,
      offeredFare: fare,
    ),
  );
  return;
}
```

#### f) Trip Completed Event (Lines ~376-382)
```dart
if (status == 'WalletSettled') {
  if (kDebugMode) {
    debugPrint('[KwellaRiderController] Trip completed: wallet settled');
  }
  _emit(
    _state.copyWith(status: RiderTripStatus.completed, latestEvent: event),
  );
  return;
}
```

#### g) Unhandled Events (Lines ~384-388)
```dart
if (kDebugMode) {
  debugPrint('[KwellaRiderController] Unhandled WebSocket event: action=$action, status=$status');
  debugPrint('  - payload: $payload');
}
```

---

## Summary of Changes

### Modified Files: 2
- `kwella-apps/kwella_core/lib/src/network/websocket_gateway.dart` (8 logging additions)
- `kwella-apps/kwella_rider/lib/features/booking/presentation/controllers/kwella_rider_controller.dart` (12 logging additions)

### New Files: 4
- `TESTING_AVD_WITH_MOCK.md` (comprehensive guide)
- `scripts/test_rider_avd_local.sh` (automated test script)
- `AVD_WEBSOCKET_FIX_SUMMARY.md` (technical summary)
- `QUICK_START_AVD_MOCK.md` (quick reference)
- `CHANGES_REFERENCE.md` (this file)

### Total Logging Points: 20+
- Connection lifecycle: 7 points
- Message transmission: 2 points
- Reconnection: 3 points
- Incoming frames: 3 points
- Trip management: 5 points

### Lines of Code Added: ~50 (all guarded by `kDebugMode`)
### Impact on Release Builds: Zero (all logging stripped)
### API Changes: None
### Breaking Changes: None
