#!/bin/bash
# =============================================================================
# Kwella Live Gateway Smoke-Testing Suite
# =============================================================================
# Usage:
#   ./scripts/smoke_test.sh
#
# Required environment (loaded automatically from .env at project root):
#   KWELLA_API_URL   — Base URL of the deployed API Gateway $default stage.
#                      The $default stage in API Gateway v2 is served from the
#                      *bare* endpoint (no stage path prefix). This is the value
#                      exported by Terraform's `http_api_endpoint` output.
#                      Example: https://dbmi2nczz8.execute-api.af-south-1.amazonaws.com/
#                      DO NOT append /production — that yields a 404 because
#                      the deployed stage name is "$default", not "production".
#
#   TEST_MOCK_JWT    — A valid Bearer token accepted by the custom authorizer.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Step 0: Load .env from the project root (sibling of scripts/)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a; source "${ENV_FILE}"; set +a
  echo -e "${YELLOW}[preflight] Loaded environment from ${ENV_FILE}${NC}"
else
  echo -e "${YELLOW}[preflight] No .env file found at ${ENV_FILE} — relying on shell environment.${NC}"
fi

# ---------------------------------------------------------------------------
# Step 1: Preflight validation — fail fast with actionable messages
# ---------------------------------------------------------------------------
PREFLIGHT_OK=true

if [[ -z "${KWELLA_API_URL:-}" ]]; then
  echo -e "${RED}[preflight] FATAL: KWELLA_API_URL is not set.${NC}"
  echo "  Set it to the bare API Gateway endpoint (Terraform output: http_api_endpoint)."
  echo "  Example: export KWELLA_API_URL=https://dbmi2nczz8.execute-api.af-south-1.amazonaws.com/"
  PREFLIGHT_OK=false
fi

if [[ -z "${TEST_MOCK_JWT:-}" ]]; then
  echo -e "${RED}[preflight] FATAL: TEST_MOCK_JWT is not set.${NC}"
  echo "  Set it to a valid Bearer token accepted by the kwella custom authorizer."
  PREFLIGHT_OK=false
fi

if [[ -z "${KWELLA_WS_URL:-}" ]]; then
  KWELLA_WS_URL="ws://localhost:3001"
  export KWELLA_WS_URL
  echo -e "${YELLOW}[preflight] KWELLA_WS_URL not set; defaulting to ${KWELLA_WS_URL}${NC}"
fi

# Warn (non-fatal) if the JWT still contains the placeholder 'signature' stub.
if echo "${TEST_MOCK_JWT:-}" | grep -q '\.signature$'; then
  echo -e "${YELLOW}[preflight] WARNING: TEST_MOCK_JWT ends with '.signature' — this looks like the"
  echo -e "  placeholder token from .env. Replace it with a valid Cognito JWT or sandbox"
  echo -e "  token or the custom authorizer will return 401/403 and all tests will fail.${NC}"
fi

if [[ "${PREFLIGHT_OK}" == "false" ]]; then
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 2: Validate URL structure — guard against common misconfiguration
# ---------------------------------------------------------------------------
# The deployed stage is named "$default" in API Gateway v2. Terraform's
# aws_apigatewayv2_stage with name = "$default" is served at the bare
# endpoint (no path prefix). A request to /production or /staging returns
# 404 "Not Found" because those stage names do not exist in this deployment.
if echo "${KWELLA_API_URL}" | grep -qE '/(production|staging|dev|development)/?$'; then
  echo -e "${RED}[preflight] FATAL: KWELLA_API_URL contains an explicit stage path prefix.${NC}"
  echo "  The deployed stage name is '\$default', which means API Gateway"
  echo "  serves routes from the bare endpoint with NO path prefix."
  echo ""
  echo "  Your URL:    ${KWELLA_API_URL}"
  CORRECTED_URL=$(echo "${KWELLA_API_URL}" | sed -E 's#/(production|staging|dev|development)/?$#/#')
  echo "  Correct URL: ${CORRECTED_URL}"
  echo ""
  echo "  Fix: Update KWELLA_API_URL in your .env to remove the stage path suffix."
  exit 1
fi

# Normalise: strip trailing slash so we can consistently append /route below.
BASE_URL="${KWELLA_API_URL%/}"

# ---------------------------------------------------------------------------
# Generate a unique test run ID to keep smoke test runs idempotent.
# The vehicle REGISTER_VEHICLE action uses attribute_not_exists(PK) to prevent
# duplicate registration. Using a timestamped CATA sticker ensures each run
# creates a fresh record rather than colliding with a previous successful run.
# ---------------------------------------------------------------------------
TEST_RUN_ID=$(date +%Y%m%d%H%M%S)
TEST_USER_ID="driver-sipho-dlamini-${TEST_RUN_ID}"
TEST_CATA_STICKER="CT-TEST-${TEST_RUN_ID}"

echo "=== Kwella Live Gateway Smoke-Testing Suite ==="
echo "Targeting API Gateway: ${BASE_URL}"
echo "(Stage: \$default — bare endpoint, no path prefix)"
echo ""

# 1. SMOKE TEST: POST /identity/upsert — Driver profile creation
echo "[1/3] Testing POST /identity/upsert..."
IDENTITY_PAYLOAD=$(printf '{
  "user_id": "%s",
  "role": "DRIVER",
  "phone": "+27831234567",
  "assigned_cata_sticker": "%s"
}' "${TEST_USER_ID}" "${TEST_CATA_STICKER}")

RESPONSE_IDENTITY=$(curl -s -w "\n%{http_code}" \
  -X POST "${BASE_URL}/identity/upsert" \
  -H "Authorization: Bearer ${TEST_MOCK_JWT}" \
  -H "Content-Type: application/json" \
  -d "${IDENTITY_PAYLOAD}")

HTTP_STATUS_IDENTITY=$(echo "$RESPONSE_IDENTITY" | tail -n1)
BODY_IDENTITY=$(echo "$RESPONSE_IDENTITY" | sed '$d')

if [ "$HTTP_STATUS_IDENTITY" -eq 200 ] || [ "$HTTP_STATUS_IDENTITY" -eq 201 ]; then
  echo -e "${GREEN}✓ Identity Upsert Successful ($HTTP_STATUS_IDENTITY)${NC}"
  echo "Response: $BODY_IDENTITY"
elif [ "$HTTP_STATUS_IDENTITY" -eq 401 ] || [ "$HTTP_STATUS_IDENTITY" -eq 403 ]; then
  echo -e "${RED}✗ Identity Upsert Failed ($HTTP_STATUS_IDENTITY) — Authorizer rejected the token.${NC}"
  echo "  The custom authorizer returned $HTTP_STATUS_IDENTITY. Check that TEST_MOCK_JWT is a"
  echo "  valid, non-expired Cognito ID token and that the user is not suspended in DynamoDB."
  echo "Response: $BODY_IDENTITY"
  exit 1
else
  echo -e "${RED}✗ Identity Upsert Failed ($HTTP_STATUS_IDENTITY)${NC}"
  echo "Response: $BODY_IDENTITY"
  exit 1
fi

# 2. SMOKE TEST: POST /identity/vehicle — Vehicle CATA sticker binding
echo ""
echo "[2/3] Testing POST /identity/vehicle..."
VEHICLE_PAYLOAD=$(printf '{
  "cata_sticker": "%s",
  "make": "Suzuki",
  "model": "Ertiga",
  "owner_id": "USR#%s"
}' "${TEST_CATA_STICKER}" "${TEST_USER_ID}")

RESPONSE_VEHICLE=$(curl -s -w "\n%{http_code}" \
  -X POST "${BASE_URL}/identity/vehicle" \
  -H "Authorization: Bearer ${TEST_MOCK_JWT}" \
  -H "Content-Type: application/json" \
  -d "${VEHICLE_PAYLOAD}")

HTTP_STATUS_VEHICLE=$(echo "$RESPONSE_VEHICLE" | tail -n1)
BODY_VEHICLE=$(echo "$RESPONSE_VEHICLE" | sed '$d')

if [ "$HTTP_STATUS_VEHICLE" -eq 200 ] || [ "$HTTP_STATUS_VEHICLE" -eq 201 ]; then
  echo -e "${GREEN}✓ Vehicle CATA Binding Successful ($HTTP_STATUS_VEHICLE)${NC}"
  echo "Response: $BODY_VEHICLE"
elif [ "$HTTP_STATUS_VEHICLE" -eq 401 ] || [ "$HTTP_STATUS_VEHICLE" -eq 403 ]; then
  echo -e "${RED}✗ Vehicle CATA Binding Failed ($HTTP_STATUS_VEHICLE) — Authorizer rejected the token.${NC}"
  echo "  The custom authorizer returned $HTTP_STATUS_VEHICLE. Check that TEST_MOCK_JWT is a"
  echo "  valid, non-expired Cognito ID token and that the user is not suspended in DynamoDB."
  echo "Response: $BODY_VEHICLE"
  exit 1
else
  echo -e "${RED}✗ Vehicle CATA Binding Failed ($HTTP_STATUS_VEHICLE)${NC}"
  echo "Response: $BODY_VEHICLE"
  exit 1
fi

# 3. SMOKE TEST: POST /ledger/trip-fee — Self-balancing ledger entry
# Uses TEST_USER_ID from test 1 so the driver profile exists in DynamoDB.
echo ""
echo "[3/3] Testing POST /ledger/trip-fee..."
LEDGER_PAYLOAD=$(printf '{\n  "tripId": "trip-%s",\n  "driverId": "%s",\n  "amount": 15.00,\n  "paymentMethod": "CASH",\n  "isPlatformHoliday": false\n}' "${TEST_RUN_ID}" "${TEST_USER_ID}")

RESPONSE_LEDGER=$(curl -s -w "\n%{http_code}" \
  -X POST "${BASE_URL}/ledger/trip-fee" \
  -H "Authorization: Bearer ${TEST_MOCK_JWT}" \
  -H "Content-Type: application/json" \
  -d "${LEDGER_PAYLOAD}")

HTTP_STATUS_LEDGER=$(echo "$RESPONSE_LEDGER" | tail -n1)
BODY_LEDGER=$(echo "$RESPONSE_LEDGER" | sed '$d')

if [ "$HTTP_STATUS_LEDGER" -eq 200 ] || [ "$HTTP_STATUS_LEDGER" -eq 201 ]; then
  echo -e "${GREEN}✓ Ledger Entry Successful ($HTTP_STATUS_LEDGER)${NC}"
  echo "Response: $BODY_LEDGER"
elif [ "$HTTP_STATUS_LEDGER" -eq 401 ] || [ "$HTTP_STATUS_LEDGER" -eq 403 ]; then
  echo -e "${RED}✗ Ledger Entry Failed ($HTTP_STATUS_LEDGER) — Authorizer rejected the token.${NC}"
  echo "  The custom authorizer returned $HTTP_STATUS_LEDGER. Check that TEST_MOCK_JWT is a"
  echo "  valid, non-expired Cognito ID token and that the user is not suspended in DynamoDB."
  echo "Response: $BODY_LEDGER"
  exit 1
else
  echo -e "${RED}✗ Ledger Entry Failed ($HTTP_STATUS_LEDGER)${NC}"
  echo "Response: $BODY_LEDGER"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 4: Local simulation hook — orchestrate the Python marketplace trip simulator
# ---------------------------------------------------------------------------
SIMULATOR_SCRIPT="${PROJECT_ROOT}/scripts/simulate_marketplace_trip.py"

if [[ ! -f "${SIMULATOR_SCRIPT}" ]]; then
  echo -e "${RED}[simulator] FATAL: Missing simulation script at ${SIMULATOR_SCRIPT}.${NC}"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo -e "${RED}[simulator] FATAL: python3 is not available in PATH.${NC}"
  echo "  Install Python 3 and ensure 'python3' resolves to the runtime used for local orchestration."
  exit 1
fi

echo ""
echo -e "${YELLOW}[simulator] Launching local marketplace simulation via python3 scripts/simulate_marketplace_trip.py${NC}"
if ! python3 "${SIMULATOR_SCRIPT}"; then
  EXIT_CODE=$?
  echo ""
  echo -e "${RED}========================================================${NC}"
  echo -e "${RED}[simulator] ERROR: Local simulation failed with exit code ${EXIT_CODE}.${NC}"
  echo -e "${RED}  Review the simulator output for state exceptions, payload drift, or timeout failures.${NC}"
  echo -e "${RED}========================================================${NC}"
  exit ${EXIT_CODE}
fi

echo ""
echo -e "${GREEN}=== LOCAL MARKETPLACE SIMULATION PASSED ===${NC}"

echo ""
echo -e "${GREEN}=== ALL SMOKE TESTS PASSED CLEANLY ===${NC}"