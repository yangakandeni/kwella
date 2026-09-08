# Quick Start: Testing kwella_rider on AVD with Mock Orchestrator

## The 3-Step Test

### Step 1: Start Mock Server (Terminal 1)
```bash
cd /Users/yanga/Documents/dev/projects/kwella
python3 scripts/mock_orchestrator/server.py
```

Expected output:
```
Starting WebSocket server on 0.0.0.0:8788
Starting REST server on 0.0.0.0:8790
WebSocket server ready
REST server ready
```

### Step 2: Launch Rider App (Terminal 2)

**Option A: Using the automated script (recommended)**
```bash
cd /Users/yanga/Documents/dev/projects/kwella
./scripts/test_rider_avd_local.sh
```

**Option B: Manual launch**
```bash
cd /Users/yanga/Documents/dev/projects/kwella/kwella-apps/kwella_rider
flutter run \
  --dart-define=KWELLA_ENV=local \
  --dart-define=KWELLA_MOCK_HOST=10.0.2.2 \
  --dart-define=KWELLA_MOCK_PORT=8788 \
  --dart-define=KWELLA_MOCK_REST_PORT=8790 \
  -v
```

### Step 3: Test in App

1. **Login:** Enter any phone number + any OTP code
2. **Booking:** Set pickup and dropoff locations
3. **Find Drivers:** Tap "Find Drivers" button
4. **Watch logs:** Look for these success indicators:
   ```
   ✓ Connected successfully
   Requesting trip with payload:
   ✓ Received driver bid offer(s)
   ```
5. **Verify:** Bid card appears on screen within ~2 seconds

## What to Watch For

### ✅ Success Indicators in Logs

```
[KwellaWebSocketGateway] ✓ Connected successfully
[KwellaRiderController] Requesting trip with payload: {...}
[KwellaWebSocketGateway] → Sending: {"action":"requestTrip",...}
[KwellaWebSocketGateway] ← Received frame: {"action":"driverBidReceived",...}
[KwellaRiderController] ✓ Received driver bid offer(s)
```

### ❌ Failure Indicators (and how to fix)

| Error | Cause | Fix |
|-------|-------|-----|
| `✗ Connection failed` | Mock server not running | Start mock server (Step 1) |
| `Unhandled exception: Connection refused` | Port 8788 blocked | Verify mock on port 8788: `nc -zv localhost 8788` |
| No logs for connection | App not in local mode | Add `--dart-define=KWELLA_ENV=local` |
| "Finding drivers..." never ends | WebSocket connected but no bids | Check mock server logs for errors |

## Detailed Guides

For complete documentation and troubleshooting:
- **Full Setup Guide:** `TESTING_AVD_WITH_MOCK.md`
- **Technical Summary:** `AVD_WEBSOCKET_FIX_SUMMARY.md`

## Network Architecture

```
Host Machine (you)
├── Mock Server
│   ├── WebSocket: 0.0.0.0:8788
│   └── REST: 0.0.0.0:8790
│
Android Virtual Device
└── kwella_rider App
    ├── ws://10.0.2.2:8788 (WebSocket)
    └── http://10.0.2.2:8790 (REST/Auth)
```

Note: AVD devices use `10.0.2.2` to reach host machine's loopback.

## Troubleshooting

### Mock server won't start
```bash
# Check if ports are already in use
nc -zv localhost 8788
nc -zv localhost 8790

# Kill any existing processes on those ports
lsof -ti:8788 | xargs kill -9
lsof -ti:8790 | xargs kill -9
```

### Flutter won't recognize changes
```bash
cd kwella-apps/kwella_rider
flutter clean
flutter pub get
flutter run --dart-define=KWELLA_ENV=local -v
```

### AVD can't reach 10.0.2.2
```bash
# Test from inside AVD
adb shell
nc -zv 10.0.2.2 8788
```

## Success Criteria

All of these must be true:

- [x] WebSocket connects to `ws://10.0.2.2:8788`
- [x] Logs show: `[KwellaWebSocketGateway] ✓ Connected successfully`
- [x] Logs show: `[KwellaRiderController] Requesting trip with payload:`
- [x] Logs show: `[KwellaRiderController] ✓ Received driver bid offer(s)`
- [x] Bid card appears on screen within ~2 seconds
- [x] No silent failures (all errors logged explicitly)

Once all above pass, the AVD ↔ Mock WebSocket connectivity is working correctly.
