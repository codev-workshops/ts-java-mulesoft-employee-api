#!/usr/bin/env bash
# test-pto-balance.sh
# End-to-end integration tests for the PTO balance endpoint.
# Validates OAuth token flow, PTO balance retrieval, error handling,
# and direct DB-to-API accuracy — all without Salesforce.

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

# ── Counters ─────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

# ── Configuration ────────────────────────────────────────────
API_BASE_URL="${API_BASE_URL:-http://localhost:8081}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-mydb}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Helpers ──────────────────────────────────────────────────
pass() {
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "  ${GREEN}PASS${NC}: $1"
}

fail() {
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "  ${RED}FAIL${NC}: $1"
    [ -n "${2:-}" ] && echo -e "        ${RED}→ $2${NC}"
}

section() {
    echo ""
    echo -e "${YELLOW}▸ $1${NC}"
}

# Compare two numbers regardless of trailing-zero formatting
# e.g. 120.0 == 120.00
numeric_eq() {
    awk "BEGIN { exit !(($1 + 0) == ($2 + 0)) }"
}

# ── Prerequisite check ───────────────────────────────────────
section "Checking prerequisites"
for cmd in curl jq psql; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}ERROR${NC}: '$cmd' is required but not installed." >&2
        exit 1
    fi
done
echo "  curl, jq, psql — OK"

# ── Step 1: Seed test data ───────────────────────────────────
section "Step 1 — Seeding test data"
export PGPASSWORD="$DB_PASSWORD"
if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -f "$SCRIPT_DIR/seed-test-data.sql" -q 2>&1; then
    echo -e "${RED}ERROR${NC}: Failed to seed test data." >&2
    exit 1
fi
echo "  Test data seeded successfully."

# ── Step 2: Obtain OAuth token ───────────────────────────────
section "Step 2 — Obtaining OAuth token"
TOKEN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    "${API_BASE_URL}/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=test_client&client_secret=test_secret")

TOKEN_HTTP_CODE=$(echo "$TOKEN_RESPONSE" | tail -n1)
TOKEN_BODY=$(echo "$TOKEN_RESPONSE" | sed '$d')

ACCESS_TOKEN=$(echo "$TOKEN_BODY" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ]; then
    echo -e "${RED}ERROR${NC}: Failed to obtain access token." >&2
    echo "  HTTP $TOKEN_HTTP_CODE — $TOKEN_BODY"
    exit 1
fi
echo "  Access token obtained (HTTP $TOKEN_HTTP_CODE)."

# ── Step 3: Run test cases ───────────────────────────────────

# --- Test Case 1: Normal PTO balance -------------------------
section "Test 1 — Normal PTO balance (TEST_EMP001)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_BASE_URL}/api/TEST_EMP001/pto/balance" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    pass "HTTP status 200"
else
    fail "HTTP status expected 200, got $HTTP_CODE"
fi

EMP_ID=$(echo "$BODY" | jq -r '.employeeId // empty')
PTO_BAL=$(echo "$BODY" | jq -r '.ptoBalance // empty')
STATUS=$(echo "$BODY" | jq -r '.status // empty')

if [ "$EMP_ID" = "TEST_EMP001" ]; then
    pass "employeeId = TEST_EMP001"
else
    fail "employeeId expected TEST_EMP001, got '$EMP_ID'"
fi

if numeric_eq "${PTO_BAL:-0}" 120.00; then
    pass "ptoBalance = 120.00"
else
    fail "ptoBalance expected 120.00, got '$PTO_BAL'"
fi

if [ "$STATUS" = "success" ]; then
    pass "status = success"
else
    fail "status expected 'success', got '$STATUS'"
fi

# Save for Test 7 (DB accuracy)
TC1_API_BALANCE="$PTO_BAL"

# --- Test Case 2: Zero PTO balance ----------------------------
section "Test 2 — Zero PTO balance (TEST_EMP002)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_BASE_URL}/api/TEST_EMP002/pto/balance" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    pass "HTTP status 200"
else
    fail "HTTP status expected 200, got $HTTP_CODE"
fi

PTO_BAL=$(echo "$BODY" | jq -r '.ptoBalance // empty')
if numeric_eq "${PTO_BAL:-X}" 0.00; then
    pass "ptoBalance = 0.00"
else
    fail "ptoBalance expected 0.00, got '$PTO_BAL'"
fi

# --- Test Case 3: High PTO balance (boundary) ----------------
section "Test 3 — High PTO balance (TEST_EMP003)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_BASE_URL}/api/TEST_EMP003/pto/balance" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    pass "HTTP status 200"
else
    fail "HTTP status expected 200, got $HTTP_CODE"
fi

PTO_BAL=$(echo "$BODY" | jq -r '.ptoBalance // empty')
if numeric_eq "${PTO_BAL:-0}" 999.99; then
    pass "ptoBalance = 999.99"
else
    fail "ptoBalance expected 999.99, got '$PTO_BAL'"
fi

# --- Test Case 4: Employee not found (404) --------------------
section "Test 4 — Employee not found (TEST_EMP_MISSING)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_BASE_URL}/api/TEST_EMP_MISSING/pto/balance" \
    -H "Authorization: Bearer $ACCESS_TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "404" ]; then
    pass "HTTP status 404"
else
    fail "HTTP status expected 404, got $HTTP_CODE"
fi

HAS_ERROR=$(echo "$BODY" | jq -r '.error // empty')
if [ -n "$HAS_ERROR" ]; then
    pass "Response contains 'error' key"
else
    fail "Response missing 'error' key" "$BODY"
fi

# --- Test Case 5: No auth token (401) ------------------------
section "Test 5 — No Authorization header (TEST_EMP001)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_BASE_URL}/api/TEST_EMP001/pto/balance")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "401" ]; then
    pass "HTTP status 401"
else
    fail "HTTP status expected 401, got $HTTP_CODE"
fi

# --- Test Case 6: Invalid auth token (401) --------------------
section "Test 6 — Invalid Bearer token (TEST_EMP001)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_BASE_URL}/api/TEST_EMP001/pto/balance" \
    -H "Authorization: Bearer invalid_token_abc123")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "401" ]; then
    pass "HTTP status 401"
else
    fail "HTTP status expected 401, got $HTTP_CODE"
fi

# --- Test Case 7: Direct DB verification ---------------------
section "Test 7 — DB-to-API accuracy check (TEST_EMP001)"
DB_BALANCE=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -t -A -c "SELECT pto_balance FROM employee_pto WHERE employee_id = 'TEST_EMP001'")

if [ -z "$DB_BALANCE" ]; then
    fail "Could not retrieve pto_balance from DB"
else
    if numeric_eq "${TC1_API_BALANCE:-X}" "$DB_BALANCE"; then
        pass "API ptoBalance ($TC1_API_BALANCE) matches DB pto_balance ($DB_BALANCE)"
    else
        fail "API ptoBalance ($TC1_API_BALANCE) does NOT match DB pto_balance ($DB_BALANCE)"
    fi
fi

# ── Step 4: Cleanup ──────────────────────────────────────────
section "Step 4 — Cleaning up test data"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -q <<'EOF'
DELETE FROM employee_pto WHERE employee_id LIKE 'TEST_EMP%';
DELETE FROM api_clients  WHERE client_id = 'test_client';
EOF
echo "  Test data removed."

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Total : $TOTAL_COUNT"
echo -e "  ${GREEN}Passed${NC}: $PASS_COUNT"
echo -e "  ${RED}Failed${NC}: $FAIL_COUNT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
