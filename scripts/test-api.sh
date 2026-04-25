#!/usr/bin/env bash
# =============================================================================
# Revelio API Test Script
# Tests all endpoints — run against localhost or the deployed fly.io URL
# Usage: BASE_URL=https://revelio-api.fly.dev ./scripts/test-api.sh
# =============================================================================

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8430}"
PHONE="${TEST_PHONE:-+15555550100}"   # Dev mode: any phone works
OTP="${TEST_OTP:-123456}"             # Dev mode: any 6-digit code works
TOKEN=""                              # Populated after login

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}  ✓ $1${NC}"; }
fail() { echo -e "${RED}  ✗ $1${NC}"; }
info() { echo -e "${BLUE}  → $1${NC}"; }
section() { echo -e "\n${YELLOW}═══ $1 ═══${NC}"; }

check_status() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  local body="$4"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label (HTTP $actual)"
  else
    fail "$label — expected HTTP $expected, got $actual"
    echo "     Response: $body"
  fi
}

# =============================================================================
# HEALTH CHECK
# =============================================================================
section "Health Check"

# GET /health — no auth required — expect 200
info "GET /health"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" "${BASE_URL}/health")
body=$(cat /tmp/rev_body)
check_status "Health check" "200" "$resp" "$body"
echo "  $body"


# =============================================================================
# AUTH FLOWS
# =============================================================================
section "Auth: Request OTP"

# POST /auth/request-otp — valid phone — expect 200
info "POST /auth/request-otp (valid phone)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/auth/request-otp" \
  -H "Content-Type: application/json" \
  -d "{\"phone\": \"${PHONE}\"}")
body=$(cat /tmp/rev_body)
check_status "Request OTP - valid phone" "200" "$resp" "$body"

# POST /auth/request-otp — invalid phone — expect 400
info "POST /auth/request-otp (invalid phone)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/auth/request-otp" \
  -H "Content-Type: application/json" \
  -d '{"phone": "not-a-phone"}')
body=$(cat /tmp/rev_body)
check_status "Request OTP - invalid phone (400)" "400" "$resp" "$body"

# POST /auth/request-otp — missing phone — expect 400
info "POST /auth/request-otp (missing phone)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/auth/request-otp" \
  -H "Content-Type: application/json" \
  -d '{}')
body=$(cat /tmp/rev_body)
check_status "Request OTP - missing phone (400)" "400" "$resp" "$body"


section "Auth: Verify OTP + Capture Token"

# POST /auth/verify-otp — correct code (dev mock: any 6-digit) — expect 200 with token
info "POST /auth/verify-otp (valid code)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/auth/verify-otp" \
  -H "Content-Type: application/json" \
  -d "{\"phone\": \"${PHONE}\", \"code\": \"${OTP}\"}")
body=$(cat /tmp/rev_body)
check_status "Verify OTP - valid code" "200" "$resp" "$body"

# Extract token for subsequent requests
TOKEN=$(echo "$body" | grep -o '"token":"[^"]*"' | cut -d'"' -f4 || true)
if [[ -n "$TOKEN" ]]; then
  pass "Token captured (${TOKEN:0:30}...)"
else
  fail "No token in response — protected route tests will fail"
fi

# Extract userId for user-scoped routes
USER_ID=$(echo "$body" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
info "User ID: $USER_ID"

# POST /auth/verify-otp — wrong code — expect 401
info "POST /auth/verify-otp (invalid code)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/auth/verify-otp" \
  -H "Content-Type: application/json" \
  -d "{\"phone\": \"${PHONE}\", \"code\": \"000000\"}")
body=$(cat /tmp/rev_body)
check_status "Verify OTP - invalid code (401)" "401" "$resp" "$body"

# POST /auth/verify-otp — missing fields — expect 400
info "POST /auth/verify-otp (missing fields)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/auth/verify-otp" \
  -H "Content-Type: application/json" \
  -d '{"phone": "+15555550100"}')
body=$(cat /tmp/rev_body)
check_status "Verify OTP - missing code (400)" "400" "$resp" "$body"


section "Auth: Me Endpoint"

# GET /auth/me — with valid token — expect 200
info "GET /auth/me (authenticated)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/auth/me" \
  -H "Authorization: Bearer ${TOKEN}")
body=$(cat /tmp/rev_body)
check_status "GET /auth/me - authenticated" "200" "$resp" "$body"
echo "  $body"

# GET /auth/me — no token — expect 401
info "GET /auth/me (no token)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" "${BASE_URL}/auth/me")
body=$(cat /tmp/rev_body)
check_status "GET /auth/me - no auth (401)" "401" "$resp" "$body"

# GET /auth/me — bad token — expect 401
info "GET /auth/me (invalid token)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/auth/me" \
  -H "Authorization: Bearer bad.token.here")
body=$(cat /tmp/rev_body)
check_status "GET /auth/me - invalid token (401)" "401" "$resp" "$body"


# =============================================================================
# SCAN ROUTES
# =============================================================================
section "Scan"

TEST_BARCODE="0028400426428"  # Doritos Nacho Cheese

# GET /scan/:barcode — known barcode — expect 200
info "GET /scan/${TEST_BARCODE}"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/scan/${TEST_BARCODE}")
body=$(cat /tmp/rev_body)
check_status "Scan barcode" "200" "$resp" "$body"

# GET /scan/:barcode — unknown barcode — expect 404
info "GET /scan/0000000000000 (unknown)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/scan/0000000000000")
body=$(cat /tmp/rev_body)
check_status "Scan unknown barcode (404)" "404" "$resp" "$body"

# POST /scan/history — record a scan
info "POST /scan/history"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/scan/history" \
  -H "Content-Type: application/json" \
  -d "{
    \"userId\": \"${USER_ID}\",
    \"barcode\": \"${TEST_BARCODE}\",
    \"productName\": \"Doritos Nacho Cheese\",
    \"brand\": \"Doritos\",
    \"category\": \"food\",
    \"score\": 32,
    \"grade\": \"F\",
    \"flags\": []
  }")
body=$(cat /tmp/rev_body)
check_status "POST /scan/history" "201" "$resp" "$body"

# POST /scan/history — missing barcode — expect 400
info "POST /scan/history (missing barcode)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/scan/history" \
  -H "Content-Type: application/json" \
  -d '{"userId": "test"}')
body=$(cat /tmp/rev_body)
check_status "POST /scan/history - missing barcode (400)" "400" "$resp" "$body"

# GET /scan/history — expect 200
info "GET /scan/history?userId=${USER_ID}"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/scan/history?userId=${USER_ID}")
body=$(cat /tmp/rev_body)
check_status "GET /scan/history" "200" "$resp" "$body"

# GET /scan/history — missing userId — expect 400
info "GET /scan/history (missing userId)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/scan/history")
body=$(cat /tmp/rev_body)
check_status "GET /scan/history - missing userId (400)" "400" "$resp" "$body"

# POST /scan/personalize
info "POST /scan/personalize"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/scan/personalize" \
  -H "Content-Type: application/json" \
  -d "{
    \"barcode\": \"${TEST_BARCODE}\",
    \"priorities\": [\"no_artificial_colors\", \"low_sodium\"]
  }")
body=$(cat /tmp/rev_body)
# 200 if product already cached, 404 if not cached yet
check_status "POST /scan/personalize" "200" "$resp" "$body"


# =============================================================================
# PRODUCTS ROUTES
# =============================================================================
section "Products"

# GET /products/search — expect 200
info "GET /products/search?q=doritos"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/products/search?q=doritos")
body=$(cat /tmp/rev_body)
check_status "GET /products/search" "200" "$resp" "$body"

# GET /products/search — with filters
info "GET /products/search?category=food&grade=A&limit=5"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/products/search?category=food&grade=A&limit=5")
body=$(cat /tmp/rev_body)
check_status "GET /products/search (filtered)" "200" "$resp" "$body"

# GET /products/trending — expect 200
info "GET /products/trending"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/products/trending?limit=5")
body=$(cat /tmp/rev_body)
check_status "GET /products/trending" "200" "$resp" "$body"

# GET /products/hall-of-shame — expect 200
info "GET /products/hall-of-shame"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/products/hall-of-shame?limit=5")
body=$(cat /tmp/rev_body)
check_status "GET /products/hall-of-shame" "200" "$resp" "$body"

# GET /products/hidden-gems — expect 200
info "GET /products/hidden-gems"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/products/hidden-gems?limit=5")
body=$(cat /tmp/rev_body)
check_status "GET /products/hidden-gems" "200" "$resp" "$body"

# GET /products/recently-added — expect 200
info "GET /products/recently-added"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/products/recently-added?limit=5")
body=$(cat /tmp/rev_body)
check_status "GET /products/recently-added" "200" "$resp" "$body"


# =============================================================================
# INGREDIENTS ROUTES
# =============================================================================
section "Ingredients"

# GET /ingredients/:name — expect 200 (public ping stub)
info "GET /ingredients/red-40"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/ingredients/red-40")
body=$(cat /tmp/rev_body)
check_status "GET /ingredients/:name" "200" "$resp" "$body"

# GET /ingredients/:name/explain — authenticated — expect 200
info "GET /ingredients/red-40/explain (authenticated)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/ingredients/red-40/explain?category=food&priorities=no_artificial_colors" \
  -H "Authorization: Bearer ${TOKEN}")
body=$(cat /tmp/rev_body)
# 200 success or 500 if OpenAI not configured
if [[ "$resp" == "200" || "$resp" == "500" ]]; then
  pass "GET /ingredients/:name/explain - auth required works (HTTP $resp)"
else
  fail "GET /ingredients/:name/explain - unexpected HTTP $resp"
  echo "  $body"
fi

# GET /ingredients/:name/explain — unauthenticated — expect 401
info "GET /ingredients/red-40/explain (no auth)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/ingredients/red-40/explain")
body=$(cat /tmp/rev_body)
check_status "GET /ingredients/:name/explain - no auth (401)" "401" "$resp" "$body"


# =============================================================================
# ALTERNATIVES ROUTES
# =============================================================================
section "Alternatives"

# GET /alternatives/:barcode — expect 200
info "GET /alternatives/${TEST_BARCODE}"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/alternatives/${TEST_BARCODE}")
body=$(cat /tmp/rev_body)
check_status "GET /alternatives/:barcode" "200" "$resp" "$body"
echo "  $body"


# =============================================================================
# PANTRY ROUTES
# =============================================================================
section "Pantry"

# POST /pantry — add item — expect 201
info "POST /pantry"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/pantry" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\": \"${USER_ID}\", \"barcode\": \"${TEST_BARCODE}\"}")
body=$(cat /tmp/rev_body)
check_status "POST /pantry (add item)" "201" "$resp" "$body"

# POST /pantry — missing fields — expect 400
info "POST /pantry (missing barcode)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/pantry" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "test-user"}')
body=$(cat /tmp/rev_body)
check_status "POST /pantry - missing barcode (400)" "400" "$resp" "$body"

# GET /pantry — expect 200
info "GET /pantry?user_id=${USER_ID}"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/pantry?user_id=${USER_ID}")
body=$(cat /tmp/rev_body)
check_status "GET /pantry" "200" "$resp" "$body"

# GET /pantry — missing user_id — expect 400
info "GET /pantry (missing user_id)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" "${BASE_URL}/pantry")
body=$(cat /tmp/rev_body)
check_status "GET /pantry - missing user_id (400)" "400" "$resp" "$body"

# GET /pantry/score — household score — expect 200
info "GET /pantry/score?user_id=${USER_ID}"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/pantry/score?user_id=${USER_ID}")
body=$(cat /tmp/rev_body)
check_status "GET /pantry/score" "200" "$resp" "$body"
echo "  $body"

# DELETE /pantry/:barcode — expect 200 or 404
info "DELETE /pantry/${TEST_BARCODE}?user_id=${USER_ID}"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X DELETE "${BASE_URL}/pantry/${TEST_BARCODE}?user_id=${USER_ID}")
body=$(cat /tmp/rev_body)
if [[ "$resp" == "200" || "$resp" == "404" ]]; then
  pass "DELETE /pantry/:barcode (HTTP $resp)"
else
  fail "DELETE /pantry/:barcode - unexpected HTTP $resp"
fi


# =============================================================================
# PROFILES ROUTES
# =============================================================================
section "Profiles"

# GET /profiles/:id — expect 200
info "GET /profiles/${USER_ID}"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/profiles/${USER_ID}")
body=$(cat /tmp/rev_body)
check_status "GET /profiles/:id" "200" "$resp" "$body"

# GET /profiles/:id — unknown id — expect 404
info "GET /profiles/00000000-0000-0000-0000-000000000000"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/profiles/00000000-0000-0000-0000-000000000000")
body=$(cat /tmp/rev_body)
check_status "GET /profiles/:id - unknown (404)" "404" "$resp" "$body"

# PATCH /profiles/:id — update priorities — expect 200
info "PATCH /profiles/${USER_ID}"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X PATCH "${BASE_URL}/profiles/${USER_ID}" \
  -H "Content-Type: application/json" \
  -d '{"priorities": ["no_artificial_colors", "low_sodium"], "allergies": ["peanuts"], "goals": ["weight_loss"]}')
body=$(cat /tmp/rev_body)
check_status "PATCH /profiles/:id" "200" "$resp" "$body"

# PATCH /profiles/:id — empty body — expect 400
info "PATCH /profiles/${USER_ID} (empty)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X PATCH "${BASE_URL}/profiles/${USER_ID}" \
  -H "Content-Type: application/json" \
  -d '{}')
body=$(cat /tmp/rev_body)
check_status "PATCH /profiles/:id - empty body (400)" "400" "$resp" "$body"

# GET /profiles/:id/members — expect 200
info "GET /profiles/${USER_ID}/members"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/profiles/${USER_ID}/members")
body=$(cat /tmp/rev_body)
check_status "GET /profiles/:id/members" "200" "$resp" "$body"

# POST /profiles/:id/members — add family member — expect 201
info "POST /profiles/${USER_ID}/members"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/profiles/${USER_ID}/members" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Child", "is_child": true, "allergies": ["dairy"], "goals": ["avoid_sugar"]}')
body=$(cat /tmp/rev_body)
check_status "POST /profiles/:id/members" "201" "$resp" "$body"

# Extract member id for delete
MEMBER_ID=$(echo "$body" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*' || true)

# POST /profiles/:id/members — missing name — expect 400
info "POST /profiles/${USER_ID}/members (no name)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/profiles/${USER_ID}/members" \
  -H "Content-Type: application/json" \
  -d '{}')
body=$(cat /tmp/rev_body)
check_status "POST /profiles/:id/members - no name (400)" "400" "$resp" "$body"

# DELETE /profiles/:id/members/:memberId — expect 200 or 404
if [[ -n "$MEMBER_ID" ]]; then
  info "DELETE /profiles/${USER_ID}/members/${MEMBER_ID}"
  resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
    -X DELETE "${BASE_URL}/profiles/${USER_ID}/members/${MEMBER_ID}")
  body=$(cat /tmp/rev_body)
  check_status "DELETE /profiles/:id/members/:memberId" "200" "$resp" "$body"
fi


# =============================================================================
# SCANS ROUTES (full history with filtering)
# =============================================================================
section "Scans (history)"

# GET /scans — paginated — expect 200
info "GET /scans?userId=${USER_ID}&page=1&limit=10"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/scans?userId=${USER_ID}&page=1&limit=10")
body=$(cat /tmp/rev_body)
check_status "GET /scans (paginated)" "200" "$resp" "$body"

# GET /scans — with filters
info "GET /scans (filtered: category=food, grade=F)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/scans?userId=${USER_ID}&category=food&grade=F")
body=$(cat /tmp/rev_body)
check_status "GET /scans (filtered)" "200" "$resp" "$body"

# GET /scans — missing userId — expect 400
info "GET /scans (missing userId)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" "${BASE_URL}/scans")
body=$(cat /tmp/rev_body)
check_status "GET /scans - missing userId (400)" "400" "$resp" "$body"

# GET /scans/insights — expect 200
info "GET /scans/insights?userId=${USER_ID}"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/scans/insights?userId=${USER_ID}")
body=$(cat /tmp/rev_body)
check_status "GET /scans/insights" "200" "$resp" "$body"
echo "  $body"

# DELETE /scans/:id — 404 for nonexistent
info "DELETE /scans/99999?userId=${USER_ID} (nonexistent)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X DELETE "${BASE_URL}/scans/99999?userId=${USER_ID}")
body=$(cat /tmp/rev_body)
check_status "DELETE /scans/:id - nonexistent (404)" "404" "$resp" "$body"


# =============================================================================
# REFERRALS ROUTES
# =============================================================================
section "Referrals"

# POST /referrals/creator-apply — expect 201 or 409 if already applied
info "POST /referrals/creator-apply"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/referrals/creator-apply" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"${USER_ID}\",
    \"follower_count\": 5000,
    \"platform\": \"instagram\",
    \"social_handle\": \"@testrevelio\"
  }")
body=$(cat /tmp/rev_body)
if [[ "$resp" == "201" || "$resp" == "409" ]]; then
  pass "POST /referrals/creator-apply (HTTP $resp)"
else
  fail "POST /referrals/creator-apply - unexpected HTTP $resp"
  echo "  $body"
fi

# POST /referrals/creator-apply — missing fields — expect 400
info "POST /referrals/creator-apply (missing fields)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/referrals/creator-apply" \
  -H "Content-Type: application/json" \
  -d '{"user_id": "test"}')
body=$(cat /tmp/rev_body)
check_status "POST /referrals/creator-apply - missing fields (400)" "400" "$resp" "$body"

# GET /referrals/my-stats — with x-user-id header — 200 or 404
info "GET /referrals/my-stats"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/referrals/my-stats" \
  -H "x-user-id: ${USER_ID}")
body=$(cat /tmp/rev_body)
if [[ "$resp" == "200" || "$resp" == "404" ]]; then
  pass "GET /referrals/my-stats (HTTP $resp)"
else
  fail "GET /referrals/my-stats - unexpected HTTP $resp"
  echo "  $body"
fi

# GET /referrals/my-stats — no auth — expect 401
info "GET /referrals/my-stats (no auth)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/referrals/my-stats")
body=$(cat /tmp/rev_body)
check_status "GET /referrals/my-stats - no auth (401)" "401" "$resp" "$body"

# POST /referrals/apply — test code apply
info "POST /referrals/apply"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/referrals/apply" \
  -H "Content-Type: application/json" \
  -d '{"referral_code": "TESTCODE99", "user_id": "some-other-user-id"}')
body=$(cat /tmp/rev_body)
# 201, 404 (code not found), or 409 (already attributed) are all valid
if [[ "$resp" == "201" || "$resp" == "404" || "$resp" == "409" ]]; then
  pass "POST /referrals/apply (HTTP $resp)"
else
  fail "POST /referrals/apply - unexpected HTTP $resp"
  echo "  $body"
fi

# GET /referrals/payout-history — expect 200, 401, or 404
info "GET /referrals/payout-history"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  "${BASE_URL}/referrals/payout-history" \
  -H "x-user-id: ${USER_ID}")
body=$(cat /tmp/rev_body)
if [[ "$resp" == "200" || "$resp" == "404" ]]; then
  pass "GET /referrals/payout-history (HTTP $resp)"
else
  fail "GET /referrals/payout-history - unexpected HTTP $resp"
  echo "  $body"
fi


# =============================================================================
# WEBHOOKS
# =============================================================================
section "Webhooks"

# POST /webhooks/revenuecat — no signature — expect 401 or 200 (dev allows if no secret set)
info "POST /webhooks/revenuecat (test event)"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" \
  -X POST "${BASE_URL}/webhooks/revenuecat" \
  -H "Content-Type: application/json" \
  -d '{
    "event": {
      "type": "INITIAL_PURCHASE",
      "app_user_id": "test-user-webhook",
      "price": 9.99,
      "id": "test-event-001"
    }
  }')
body=$(cat /tmp/rev_body)
# 200 if no REVENUECAT_WEBHOOK_SECRET set (dev mode), 401 if signature required
if [[ "$resp" == "200" || "$resp" == "401" ]]; then
  pass "POST /webhooks/revenuecat (HTTP $resp)"
else
  fail "POST /webhooks/revenuecat - unexpected HTTP $resp"
  echo "  $body"
fi


# =============================================================================
# PRIVACY PAGE
# =============================================================================
section "Privacy Policy"

# GET /privacy — expect 200 HTML
info "GET /privacy"
resp=$(curl -s -o /tmp/rev_body -w "%{http_code}" "${BASE_URL}/privacy")
body=$(cat /tmp/rev_body)
check_status "GET /privacy (HTML page)" "200" "$resp" "$body"


# =============================================================================
# SUMMARY
# =============================================================================
section "Done"
echo ""
echo -e "${YELLOW}Test run complete. Review any failures above.${NC}"
echo -e "  Base URL: ${BASE_URL}"
echo -e "  Token:    ${TOKEN:0:50}..."
echo ""
