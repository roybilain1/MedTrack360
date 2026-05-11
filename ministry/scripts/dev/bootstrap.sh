#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
POS_DIR="$ROOT_DIR/../../../POS_frontend/medtrack_pos"

export MEDTRACK_BACKEND_URL="${MEDTRACK_BACKEND_URL:-http://localhost:3000}"
export MEDTRACK_API_BASE_URL="${MEDTRACK_API_BASE_URL:-$MEDTRACK_BACKEND_URL/api}"
export MEDTRACK_SYNC_API_KEY="${MEDTRACK_SYNC_API_KEY:-local-dev-sync-key}"
export MEDTRACK_PHARMACY_ID="${MEDTRACK_PHARMACY_ID:-1}"
export MEDTRACK_POS_HWID="${MEDTRACK_POS_HWID:-HW-00423}"

export VITE_API_BASE_URL="$MEDTRACK_BACKEND_URL"

cat <<INFO
[bootstrap] Shared environment
  backend:  $MEDTRACK_BACKEND_URL
  api:      $MEDTRACK_API_BASE_URL
  sync key: $MEDTRACK_SYNC_API_KEY
  pharmacy: $MEDTRACK_PHARMACY_ID
  device:   $MEDTRACK_POS_HWID
INFO

cleanup() {
  if [[ -n "${BACKEND_PID:-}" ]]; then kill "$BACKEND_PID" >/dev/null 2>&1 || true; fi
  if [[ -n "${WEB_PID:-}" ]]; then kill "$WEB_PID" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT INT TERM

(
  cd "$BACKEND_DIR"
  export DEVICE_SYNC_API_KEY="$MEDTRACK_SYNC_API_KEY"
  export POS_SYNC_API_KEY="$MEDTRACK_SYNC_API_KEY"
  npm run dev
) &
BACKEND_PID=$!

(
  cd "$ROOT_DIR"
  npm run dev
) &
WEB_PID=$!

cat <<INFO

[bootstrap] Backend and web are running.
[bootstrap] In a separate terminal, run POS with the same environment:

cd "$POS_DIR"
flutter run -d macos \
  --dart-define=MEDTRACK_API_BASE_URL="$MEDTRACK_API_BASE_URL" \
  --dart-define=MEDTRACK_SYNC_API_KEY="$MEDTRACK_SYNC_API_KEY" \
  --dart-define=MEDTRACK_PHARMACY_ID="$MEDTRACK_PHARMACY_ID" \
  --dart-define=MEDTRACK_POS_HWID="$MEDTRACK_POS_HWID"

INFO

wait
