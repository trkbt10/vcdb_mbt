#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="$ROOT_DIR/web-dashboard"
JS_DIR="$ROOT_DIR/js"
HOST="127.0.0.1"
GATEWAY_PORT="${VCDB_PORT:-6333}"
DASHBOARD_PORT="${DASHBOARD_PORT:-4179}"
STORAGE_DIR="$WEB_DIR/.e2e-storage"
GATEWAY_URL="http://${HOST}:${GATEWAY_PORT}"
DASHBOARD_URL="http://${HOST}:${DASHBOARD_PORT}"

wait_for_url() {
  local url="$1"
  local name="$2"
  for _ in $(seq 1 60); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  echo "Timed out waiting for ${name}: ${url}" >&2
  return 1
}

cleanup() {
  if [ -n "${PREVIEW_PID:-}" ]; then
    kill "$PREVIEW_PID" 2>/dev/null || true
    wait "$PREVIEW_PID" 2>/dev/null || true
  fi
  if [ -n "${GATEWAY_PID:-}" ]; then
    kill "$GATEWAY_PID" 2>/dev/null || true
    wait "$GATEWAY_PID" 2>/dev/null || true
  fi
  rm -rf "$STORAGE_DIR"
}

trap cleanup EXIT

cd "$WEB_DIR"
npm run build

if [ ! -f "$JS_DIR/dist/server.js" ]; then
  cd "$JS_DIR"
  npm run build
  cd "$WEB_DIR"
fi

rm -rf "$STORAGE_DIR"
mkdir -p "$STORAGE_DIR"

node "$JS_DIR/dist/server.js" --host "$HOST" --port "$GATEWAY_PORT" --storage "$STORAGE_DIR" &
GATEWAY_PID=$!
wait_for_url "$GATEWAY_URL/healthz" "gateway"

API_BASE="$GATEWAY_URL" E2E_COLLECTION_NAME="e2e-client" npm run test:client

npm run preview -- --host "$HOST" --port "$DASHBOARD_PORT" &
PREVIEW_PID=$!
wait_for_url "$DASHBOARD_URL" "dashboard"

DASHBOARD_URL="$DASHBOARD_URL" node "$WEB_DIR/e2e/smoke.mjs"
