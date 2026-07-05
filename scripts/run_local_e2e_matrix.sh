#!/bin/bash
# =============================================================================
# Kwella Local Dual-Simulator E2E Orchestrator
# =============================================================================
# Launches kwella_rider_app on a booted iOS Simulator and kwella_driver_app on
# a booted Android Emulator, side by side, so the marketplace trip flow
# (broadcast -> bid -> accept -> arrive -> in-transit -> complete) can be
# driven interactively across both apps at once.
#
# Usage:
#   ./scripts/run_local_e2e_matrix.sh
#
# Prerequisites:
#   - An iOS Simulator booted (Xcode > Simulator, or `open -a Simulator`).
#   - An Android Emulator booted (Android Studio AVD Manager, or `emulator`).
#   - Both visible to `flutter devices`.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RIDER_APP_DIR="${PROJECT_ROOT}/kwella-apps/kwella_rider_app"
DRIVER_APP_DIR="${PROJECT_ROOT}/kwella-apps/kwella_driver_app"

# ---------------------------------------------------------------------------
# Step 1: Discover booted device IDs from `flutter devices`
# ---------------------------------------------------------------------------
echo "=== Kwella Local E2E Matrix ==="
echo ""
echo "[preflight] Querying flutter devices..."

if ! command -v flutter >/dev/null 2>&1; then
  echo -e "${RED}[preflight] FATAL: 'flutter' is not on PATH.${NC}"
  exit 1
fi

DEVICES_JSON=$(flutter devices --machine)

IOS_DEVICE_ID=$(echo "${DEVICES_JSON}" | python3 -c '
import json, sys
devices = json.load(sys.stdin)
for d in devices:
    if d.get("platform", "").startswith("ios") and d.get("emulator"):
        print(d["id"])
        break
')

ANDROID_DEVICE_ID=$(echo "${DEVICES_JSON}" | python3 -c '
import json, sys
devices = json.load(sys.stdin)
for d in devices:
    if d.get("platform", "").startswith("android") and d.get("emulator"):
        print(d["id"])
        break
')

if [[ -z "${IOS_DEVICE_ID}" ]]; then
  echo -e "${RED}[preflight] FATAL: No booted iOS Simulator found.${NC}"
  echo "  Boot one first, e.g.: open -a Simulator"
  exit 1
fi
echo -e "${GREEN}[preflight] iOS Simulator found: ${IOS_DEVICE_ID}${NC}"

if [[ -z "${ANDROID_DEVICE_ID}" ]]; then
  echo -e "${RED}[preflight] FATAL: No booted Android Emulator found.${NC}"
  echo "  Boot one first, e.g.: emulator -avd <avd_name>"
  exit 1
fi
echo -e "${GREEN}[preflight] Android Emulator found: ${ANDROID_DEVICE_ID}${NC}"

# ---------------------------------------------------------------------------
# Step 2: Launch both apps concurrently, keeping them attached in foreground
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[launch] Starting kwella_rider_app on iOS Simulator (${IOS_DEVICE_ID})...${NC}"
echo -e "${YELLOW}[launch] Starting kwella_driver_app on Android Emulator (${ANDROID_DEVICE_ID})...${NC}"
echo ""
echo "Both flutter run sessions are attached below (hot-reload keys work per-pane"
echo "if run in separate terminals). Press Ctrl+C to stop both."
echo ""

cleanup() {
  echo ""
  echo -e "${YELLOW}[cleanup] Stopping both flutter run processes...${NC}"
  kill "${RIDER_PID}" "${DRIVER_PID}" 2>/dev/null || true
  wait "${RIDER_PID}" "${DRIVER_PID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

(
  cd "${RIDER_APP_DIR}"
  flutter run -d "${IOS_DEVICE_ID}"
) &
RIDER_PID=$!

(
  cd "${DRIVER_APP_DIR}"
  flutter run -d "${ANDROID_DEVICE_ID}"
) &
DRIVER_PID=$!

wait "${RIDER_PID}" "${DRIVER_PID}"
