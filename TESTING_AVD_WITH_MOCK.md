# Testing kwella_rider with Mock Orchestrator on Android Virtual Device

## Overview

This guide walks through setting up and testing the rider app's WebSocket connectivity to the mock orchestrator backend running on your host machine.

**Key Point:** Android Virtual Devices (AVD) cannot directly access `localhost`. They must route to the host via `10.0.2.2`.

## Prerequisites

- Android Studio with AVD configured
- Flutter SDK installed
- Python 3.8+ (for mock_orchestrator)
- Terminal access

## Architecture

```
Host Machine (your computer)
├── mock_orchestrator/
│   ├── WebSocket server (port 8788)
│   └── REST server (port 8790)
│
└── Android Virtual Device
    └── kwella_rider app
        ├── Connects to ws://10.0.2.2:8788 (WebSocket)
        └── Calls http://10.0.2.2:8790 (REST/Auth)
```

## Step 1: Start the Mock Orchestrator

Run the mock backend from the project root:

```bash
cd /Users/yanga/Documents/dev/projects/kwella
python3 scripts/mock_orchestrator/server.py
```

You should see output similar to:
```
Starting WebSocket server on 0.0.0.0:8788
Starting REST server on 0.0.0.0:8790
WebSocket server ready
REST server ready
```

## Step 2: Verify Host Machine Network Accessibility

Ensure the mock server ports are accessible:

```bash
# Check WebSocket port
nc -zv localhost 8788

# Check REST port
nc -zv localhost 8790

# Both should respond with "Connection successful"
```

## Step 3: Start AVD and Launch kwella_rider

In a new terminal, launch the rider app targeting the local environment:

```bash
cd /Users/yanga/Documents/dev/projects/kwella/kwella-apps/kwella_rider

# Clean previous build
flutter clean

# Get dependencies
flutter pub get

# Run with local environment configuration
# The KWELLA_ENV=local define routes all endpoints to 10.0.2.2
flutter run \
  --dart-define=KWELLA_ENV=local \
  --dart-define=KWELLA_MOCK_HOST=10.0.2.2 \
  --dart-define=KWELLA_MOCK_PORT=8788 \
  --dart-define=KWELLA_MOCK_REST_PORT=8790 \
  -v
```

The `-v` flag enables verbose logging so you can see all WebSocket connection diagnostics.

## Step 4: Monitor Logs for Connection Diagnostics

The enhanced logging will show you:

### Connection Lifecycle
```
[KwellaWebSocketGateway] Initiating connection...
[KwellaWebSocketGateway] Connecting to: ws://10.0.2.2:8788
[KwellaWebSocketGateway] ✓ Connected successfully
```

### Request Trip
```
[KwellaRiderController] Requesting trip with payload: {"action":"requestTrip",...}
  - riderId: rider-123
  - pickup: (-33.9249, 18.6324)
  - dropoff: (-33.9352, 18.6412)
  - passengers: 2
[KwellaWebSocketGateway] → Sending: {"action":"requestTrip",...}
```

### Incoming Bids
```
[KwellaWebSocketGateway] ← Received frame: {"action":"driverBidReceived",...}
[KwellaRiderController] ✓ Received driver bid offer(s)
  - tripId: trip-456
  - total bids: 1
  - bid[0]: driver=driver-789, fare=45.50
```

## Step 5: Test the User Flow in the App

1. **Auth Screen**: Enter any phone number (e.g., +27123456789) and OTP code
   - Mock Cognito will accept any code for testing

2. **Booking Screen**: Set pickup and dropoff locations
   - Mock location service returns test coordinates

3. **Tap "Find Drivers"**:
   - Watch logs for `Requesting trip with payload:`
   - You should see `✓ Connected successfully` in logs if connection succeeds
   - You should see `✓ Received driver bid offer(s)` within ~2s

4. **Bid Sheet Appears**:
   - The bottom sheet transitions to show available driver bids
   - Each bid shows driver name, vehicle, fare, and ETA

5. **Accept/Decline Bids**:
   - Tap Accept to transition to driver tracking
   - Tap Decline to remove that bid from the list

## Troubleshooting

### "Finding drivers…" Never Shows Bids

**Check logs for:**

```
[KwellaWebSocketGateway] ✗ Connection failed: ...
```

This means the WebSocket failed to connect. Possible causes:

1. **Mock server not running**: Verify port 8788 is listening
   ```bash
   nc -zv localhost 8788
   ```

2. **AVD cannot reach 10.0.2.2**: Test AVD network access
   ```bash
   # Inside AVD shell
   adb shell
   nc -zv 10.0.2.2 8788
   ```

3. **Environment not set to local**: Confirm the run command includes `--dart-define=KWELLA_ENV=local`
   - Without it, the app defaults to production AWS endpoints

### Connection Drops Unexpectedly

Look for:
```
[KwellaWebSocketGateway] Connection closed by remote peer
[KwellaWebSocketGateway] Scheduling reconnect attempt #1 in 2000ms
```

This is normal—the connection auto-reconnects with exponential backoff.

### Malformed Frame Errors

```
[KwellaRiderController] Failed to parse incoming frame: ...
```

This indicates the backend sent invalid JSON. Check:
1. Mock orchestrator logs for errors
2. Backend version compatibility

## Diagnostic Commands

### View WebSocket Traffic (on host)

```bash
# Using tcpdump to inspect WebSocket frames on port 8788
sudo tcpdump -i lo -n 'tcp port 8788' -A
```

### Check Mock Server Logs

```bash
# Mock orchestrator logs
# (appears in the terminal where you ran server.py)
# Look for connection attempts and frame dispatches
```

### Force Rebuild Flutter Cache

If changes to environment.dart aren't picked up:

```bash
flutter clean
rm -rf ios android .dart_tool pubspec.lock
flutter pub get
flutter run --dart-define=KWELLA_ENV=local -v
```

## Advanced: Physical Device Testing

To test on a real Android device instead of AVD:

1. Connect device via USB
2. Find your host machine's LAN IP:
   ```bash
   ifconfig | grep inet | grep -v 127.0.0.1
   # e.g., 192.168.1.100
   ```

3. Update mock server listening address (if needed):
   ```bash
   python3 scripts/mock_orchestrator/server.py --bind 0.0.0.0
   ```

4. Launch app targeting that IP:
   ```bash
   flutter run \
     --dart-define=KWELLA_ENV=local \
     --dart-define=KWELLA_MOCK_HOST=192.168.1.100 \
     -v
   ```

## Expected Behavior Summary

| Step | Expected Behavior | Logs |
|------|-------------------|------|
| Launch app | App starts, connects to mock auth | `Connecting to: ws://10.0.2.2:8788` |
| Enter booking screen | Ready to input locations | No errors in logs |
| Tap "Find Drivers" | Screen transitions to searching | `Requesting trip with payload:` |
| ~2s later | Bid sheet appears with driver offer(s) | `✓ Received driver bid offer(s)` |
| Tap Accept | Navigate to tracking screen | `selectBid` logged |
| Tap Decline | Bid removed from list | `declineBid` logged |

## Acceptance Criteria Verification

After completing this flow, verify:

- [x] WebSocket connects to `ws://10.0.2.2:8788`
- [x] `requestTrip` action dispatches with valid payload (lat, lng, passenger_count)
- [x] Driver bids appear dynamically on searching screen
- [x] Logs show explicit connection diagnostics and no silent failures
- [x] Disconnects/errors trigger automatic reconnection attempts

If all above pass, the AVD-to-mock connectivity is working correctly.
