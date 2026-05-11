#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POS_DIR="$ROOT_DIR/../../../POS_frontend/medtrack_pos"

export MEDTRACK_BACKEND_URL="${MEDTRACK_BACKEND_URL:-http://localhost:3000}"
export MEDTRACK_API_BASE_URL="${MEDTRACK_API_BASE_URL:-$MEDTRACK_BACKEND_URL/api}"
export MEDTRACK_SYNC_API_KEY="${MEDTRACK_SYNC_API_KEY:-local-dev-sync-key}"
export MEDTRACK_PHARMACY_ID="${MEDTRACK_PHARMACY_ID:-1}"
export MEDTRACK_POS_HWID="${MEDTRACK_POS_HWID:-HW-00423}"

cd "$POS_DIR"
flutter run -d macos \
  --dart-define=MEDTRACK_API_BASE_URL="$MEDTRACK_API_BASE_URL" \
  --dart-define=MEDTRACK_SYNC_API_KEY="$MEDTRACK_SYNC_API_KEY" \
  --dart-define=MEDTRACK_PHARMACY_ID="$MEDTRACK_PHARMACY_ID" \
  --dart-define=MEDTRACK_POS_HWID="$MEDTRACK_POS_HWID"
