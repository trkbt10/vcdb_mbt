#!/usr/bin/env bash
#
# vcdb E2E Test Script
# Tests the HTTP server with real API calls (vcdb-style)
#

# Don't use set -e since we want tests to continue even if assertions fail

HOST="${VCDB_HOST:-localhost}"
PORT="${VCDB_PORT:-6333}"
BASE_URL="http://${HOST}:${PORT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[PASS]${NC} $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_error() {
  echo -e "${RED}[FAIL]${NC} $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_section() {
  echo ""
  echo -e "${YELLOW}━━━ $1 ━━━${NC}"
}

# Assert response contains expected string
assert_contains() {
  local response="$1"
  local expected="$2"
  local test_name="$3"

  if echo "$response" | grep -qF "$expected"; then
    log_success "$test_name"
    return 0
  else
    log_error "$test_name"
    echo "  Expected to contain: $expected"
    echo "  Got: $response"
    return 1
  fi
}

# Assert HTTP status code
assert_status() {
  local status="$1"
  local expected="$2"
  local test_name="$3"

  if [ "$status" -eq "$expected" ]; then
    log_success "$test_name"
    return 0
  else
    log_error "$test_name"
    echo "  Expected status: $expected, Got: $status"
    return 1
  fi
}

# Wait for server to be ready
wait_for_server() {
  log_info "Waiting for server at $BASE_URL..."
  local max_attempts=30
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if curl -s "$BASE_URL/healthz" > /dev/null 2>&1; then
      log_info "Server is ready!"
      return 0
    fi
    sleep 0.5
    attempt=$((attempt + 1))
  done

  log_error "Server did not start within ${max_attempts} attempts"
  exit 1
}

# Cleanup function
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    log_info "Stopping server (PID: $SERVER_PID)..."
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
  fi
  # Remove test storage
  rm -rf ./test_storage
}

trap cleanup EXIT

#
# Main test script
#

echo ""
echo "╔════════════════════════════════════════╗"
echo "║       vcdb E2E Test Suite              ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Start server in background
log_info "Starting vcdb server..."
rm -rf ./test_storage

# Build if needed
if [ ! -f dist/server.js ]; then
  log_info "Building TypeScript..."
  npm run build
fi

if command -v bun &> /dev/null; then
  bun run dist/server.js --port $PORT --storage ./test_storage &
  SERVER_PID=$!
elif command -v node &> /dev/null; then
  node dist/server.js --port $PORT --storage ./test_storage &
  SERVER_PID=$!
else
  log_error "Neither bun nor node found. Please install one of them."
  exit 1
fi

wait_for_server

# ============================
log_section "Health & Info"
# ============================

# Test 1: Health check
RESPONSE=$(curl -s "$BASE_URL/healthz")
assert_contains "$RESPONSE" '"status":"ok"' "GET /healthz returns ok"

# Test 2: Service info
RESPONSE=$(curl -s "$BASE_URL/")
assert_contains "$RESPONSE" '"name":"vcdb"' "GET / returns service info"
assert_contains "$RESPONSE" '"version"' "GET / includes version"

# ============================
log_section "Collections CRUD"
# ============================

# Test 3: List collections (empty)
RESPONSE=$(curl -s "$BASE_URL/collections")
assert_contains "$RESPONSE" '"collections":[]' "GET /collections returns empty list"

# Test 4: Create collection
RESPONSE=$(curl -s -X POST "$BASE_URL/collections/products" \
  -H "Content-Type: application/json" \
  -d '{"vectors":{"size":4,"distance":"Cosine"}}')
assert_contains "$RESPONSE" '"status":"ok"' "POST /collections/products creates collection"

# Test 5: Create second collection
RESPONSE=$(curl -s -X POST "$BASE_URL/collections/users" \
  -H "Content-Type: application/json" \
  -d '{"dim":3,"metric":"L2"}')
assert_contains "$RESPONSE" '"status":"ok"' "POST /collections/users creates collection"

# Test 6: List collections (should have 2)
RESPONSE=$(curl -s "$BASE_URL/collections")
assert_contains "$RESPONSE" '"products"' "GET /collections includes products"
assert_contains "$RESPONSE" '"users"' "GET /collections includes users"

# Test 7: Get collection info
RESPONSE=$(curl -s "$BASE_URL/collections/products")
assert_contains "$RESPONSE" '"name":"products"' "GET /collections/products returns info"
assert_contains "$RESPONSE" '"vectors_count":0' "Collection has 0 vectors initially"

# Test 8: Duplicate collection fails
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/collections/products" \
  -H "Content-Type: application/json" \
  -d '{}')
assert_status "$STATUS" 400 "POST duplicate collection returns 400"

# ============================
log_section "Points CRUD"
# ============================

# Test 9: Upsert single point
RESPONSE=$(curl -s -X PUT "$BASE_URL/collections/products/points" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {"id": 1, "vector": [0.1, 0.2, 0.3, 0.4], "payload": {"name": "Apple", "price": 1.50}}
    ]
  }')
assert_contains "$RESPONSE" '"status":"ok"' "PUT /points upserts point"
assert_contains "$RESPONSE" '"upserted":1' "Upserted 1 point"

# Test 10: Upsert batch
RESPONSE=$(curl -s -X PUT "$BASE_URL/collections/products/points" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {"id": 2, "vector": [0.2, 0.3, 0.4, 0.5], "payload": {"name": "Banana", "price": 0.75}},
      {"id": 3, "vector": [0.9, 0.1, 0.0, 0.0], "payload": {"name": "Orange", "price": 2.00}},
      {"id": 4, "vector": [0.1, 0.1, 0.9, 0.1], "payload": {"name": "Grape", "price": 3.50}},
      {"id": 5, "vector": [0.5, 0.5, 0.5, 0.5], "payload": {"name": "Melon", "price": 5.00}}
    ]
  }')
assert_contains "$RESPONSE" '"upserted":4' "Batch upsert 4 points"

# Test 11: Check collection count
RESPONSE=$(curl -s "$BASE_URL/collections/products")
assert_contains "$RESPONSE" '"vectors_count":5' "Collection now has 5 vectors"

# Test 12: Get point by ID
RESPONSE=$(curl -s "$BASE_URL/collections/products/points/1")
assert_contains "$RESPONSE" '"id":1' "GET /points/1 returns point"
assert_contains "$RESPONSE" '"name":"Apple"' "Point has correct payload"
assert_contains "$RESPONSE" '"vector"' "Point includes vector"

# Test 13: Get non-existent point
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/collections/products/points/999")
assert_status "$STATUS" 404 "GET non-existent point returns 404"

# Test 14: Update point (upsert existing)
RESPONSE=$(curl -s -X PUT "$BASE_URL/collections/products/points" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {"id": 1, "vector": [0.15, 0.25, 0.35, 0.45], "payload": {"name": "Apple", "price": 1.75, "organic": true}}
    ]
  }')
assert_contains "$RESPONSE" '"upserted":1' "Update existing point"

# Verify update
RESPONSE=$(curl -s "$BASE_URL/collections/products/points/1")
assert_contains "$RESPONSE" '"price":1.75' "Point price updated"
assert_contains "$RESPONSE" '"organic":true' "Point has new field"

# ============================
log_section "Search"
# ============================

# Test 15: Basic search
RESPONSE=$(curl -s -X POST "$BASE_URL/collections/products/points/search" \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, 0.3, 0.4],
    "limit": 3
  }')
assert_contains "$RESPONSE" '"result"' "Search returns results"
assert_contains "$RESPONSE" '"score"' "Results include scores"
assert_contains "$RESPONSE" '"id":1' "Apple is in top results (most similar)"

# Test 16: Search with limit
RESPONSE=$(curl -s -X POST "$BASE_URL/collections/products/points/search" \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.5, 0.5, 0.5, 0.5],
    "limit": 2
  }')
# Count results
RESULT_COUNT=$(echo "$RESPONSE" | grep -o '"id":' | wc -l | tr -d ' ')
if [ "$RESULT_COUNT" -eq 2 ]; then
  log_success "Search limit=2 returns exactly 2 results"
else
  log_error "Search limit=2 should return 2 results, got $RESULT_COUNT"
fi

# Test 17: Search with_payload=false
RESPONSE=$(curl -s -X POST "$BASE_URL/collections/products/points/search" \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, 0.3, 0.4],
    "limit": 1,
    "with_payload": false
  }')
if echo "$RESPONSE" | grep -q '"payload"'; then
  log_error "Search with_payload=false should not include payload"
else
  log_success "Search with_payload=false excludes payload"
fi

# Test 18: Search with_vector=true
RESPONSE=$(curl -s -X POST "$BASE_URL/collections/products/points/search" \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.1, 0.2, 0.3, 0.4],
    "limit": 1,
    "with_vector": true
  }')
assert_contains "$RESPONSE" '"vector"' "Search with_vector=true includes vector"

# ============================
log_section "Delete Operations"
# ============================

# Test 19: Delete point
RESPONSE=$(curl -s -X DELETE "$BASE_URL/collections/products/points/5")
assert_contains "$RESPONSE" '"status":"ok"' "DELETE /points/5 succeeds"

# Verify deletion
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/collections/products/points/5")
assert_status "$STATUS" 404 "Deleted point returns 404"

# Test 20: Check collection count after delete
RESPONSE=$(curl -s "$BASE_URL/collections/products")
assert_contains "$RESPONSE" '"vectors_count":4' "Collection now has 4 vectors"

# Test 21: Delete collection
RESPONSE=$(curl -s -X DELETE "$BASE_URL/collections/users")
assert_contains "$RESPONSE" '"status":"ok"' "DELETE /collections/users succeeds"

# Verify deletion
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/collections/users")
assert_status "$STATUS" 404 "Deleted collection returns 404"

# ============================
log_section "Error Handling"
# ============================

# Test 22: Invalid JSON body
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$BASE_URL/collections/products/points" \
  -H "Content-Type: application/json" \
  -d 'not valid json')
# Should handle gracefully (either 400 or parse as empty)
if [ "$STATUS" -eq 400 ] || [ "$STATUS" -eq 200 ]; then
  log_success "Invalid JSON handled gracefully"
else
  log_error "Invalid JSON should return 400 or 200, got $STATUS"
fi

# Test 23: Dimension mismatch
RESPONSE=$(curl -s -X PUT "$BASE_URL/collections/products/points" \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {"id": 100, "vector": [0.1, 0.2], "payload": {}}
    ]
  }')
assert_contains "$RESPONSE" '"error"' "Dimension mismatch returns error"

# Test 24: Non-existent collection
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/collections/nonexistent")
assert_status "$STATUS" 404 "Non-existent collection returns 404"

# Test 25: Unknown route
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/unknown/route")
assert_status "$STATUS" 404 "Unknown route returns 404"

# ============================
log_section "Persistence"
# ============================

# Test 26: Data persists to disk
if [ -f "./test_storage/products/data.json" ]; then
  log_success "Collection data persisted to disk"
else
  log_error "Collection data not found on disk"
fi

# ============================
# Summary
# ============================

echo ""
echo "╔════════════════════════════════════════╗"
echo "║            Test Summary                ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
echo -e "  Total:  $((TESTS_PASSED + TESTS_FAILED))"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}✗ Some tests failed${NC}"
  exit 1
fi
