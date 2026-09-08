#!/bin/bash
# Test runner for kwella_rider against mock_orchestrator on Android Virtual Device
# Usage: ./scripts/test_rider_avd_local.sh

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RIDER_DIR="$PROJECT_ROOT/kwella-apps/kwella_rider"
MOCK_DIR="$PROJECT_ROOT/scripts/mock_orchestrator"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== kwella_rider AVD + Mock Orchestrator Test ===${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}[1/4] Checking prerequisites...${NC}"

if ! command -v flutter &> /dev/null; then
    echo -e "${RED}✗ Flutter not found. Please install Flutter SDK.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Flutter found${NC}"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python3 not found. Please install Python 3.8+${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Python3 found${NC}"

if ! command -v adb &> /dev/null; then
    echo -e "${RED}✗ adb not found. Please ensure Android SDK is installed.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ adb found${NC}"

# Verify mock orchestrator exists
if [ ! -f "$MOCK_DIR/server.py" ]; then
    echo -e "${RED}✗ Mock orchestrator not found at $MOCK_DIR/server.py${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Mock orchestrator found${NC}"
echo ""

# Check if mock server is already running
echo -e "${YELLOW}[2/4] Checking mock server status...${NC}"
if nc -z localhost 8788 2>/dev/null; then
    echo -e "${GREEN}✓ Mock server already running on port 8788${NC}"
else
    echo -e "${YELLOW}⚠ Mock server not running. Starting it now...${NC}"
    cd "$PROJECT_ROOT"
    python3 "$MOCK_DIR/server.py" &
    MOCK_PID=$!
    sleep 3

    if nc -z localhost 8788 2>/dev/null; then
        echo -e "${GREEN}✓ Mock server started (PID: $MOCK_PID)${NC}"
    else
        echo -e "${RED}✗ Failed to start mock server${NC}"
        exit 1
    fi
fi
echo ""

# Check AVD/device
echo -e "${YELLOW}[3/4] Checking Android device/AVD...${NC}"
DEVICE_COUNT=$(adb devices | grep -c "device$")
if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo -e "${RED}✗ No Android devices or AVDs found. Please start an AVD.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Android device/AVD found${NC}"
DEVICE_ID=$(adb devices | grep "device$" | head -1 | awk '{print $1}')
echo -e "${GREEN}  Device: $DEVICE_ID${NC}"
echo ""

# Launch rider app
echo -e "${YELLOW}[4/4] Launching kwella_rider...${NC}"
echo -e "${GREEN}Build parameters:${NC}"
echo "  - Environment: local"
echo "  - Mock Host: 10.0.2.2"
echo "  - Mock WebSocket Port: 8788"
echo "  - Mock REST Port: 8790"
echo ""

cd "$RIDER_DIR"
echo -e "${YELLOW}Running: flutter run --dart-define=KWELLA_ENV=local -v${NC}"
echo ""

flutter run \
  --dart-define=KWELLA_ENV=local \
  --dart-define=KWELLA_MOCK_HOST=10.0.2.2 \
  --dart-define=KWELLA_MOCK_PORT=8788 \
  --dart-define=KWELLA_MOCK_REST_PORT=8790 \
  -v

echo ""
echo -e "${GREEN}=== Test Complete ===${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Log in with any phone number and OTP code"
echo "2. Set pickup and dropoff locations"
echo "3. Tap 'Find Drivers'"
echo "4. Watch logs for '[KwellaWebSocketGateway] ✓ Connected successfully'"
echo "5. Within ~2s, you should see driver bids appear"
echo ""
echo -e "${YELLOW}Troubleshooting:${NC}"
echo "- Check logs for '[KwellaWebSocketGateway]' entries"
echo "- Verify mock server is running: nc -zv localhost 8788"
echo "- Run inside AVD: adb shell nc -zv 10.0.2.2 8788"
echo ""
