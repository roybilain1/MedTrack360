# MedTrack POS

MedTrack POS is the pharmacy point-of-sale frontend with local SQLite storage,
offline-first sales queuing, and sync integration with a government-hosted
Node.js + PostgreSQL backend.

## Architecture

- POS desktop app: Flutter + SQLite (`InventoryDatabase`)
- Central production backend: `medtrack_web/backend` (single source of truth)
- Local POS backend: dev-only proxy/deprecation shim (`backend/`)
- Mobile app DB: separate SQLite store (`MobileDatabase`)

## Backend Configuration (Flutter)

The POS backend URL is runtime-configurable via `--dart-define`.

- `MEDTRACK_API_BASE_URL` (default: `http://localhost:3000/api`)
- `MEDTRACK_SYNC_API_KEY` (optional, if server requires `x-sync-key`)
- `MEDTRACK_PHARMACY_ID`
- `MEDTRACK_POS_HWID`
- `MEDTRACK_REQUEST_TIMEOUT_SECONDS` (default: `15`)
- `MEDTRACK_HEALTH_TIMEOUT_SECONDS` (default: `4`)
- `MEDTRACK_SYNC_INTERVAL_SECONDS` (default: `30`)
- `MEDTRACK_SYNC_RETRY_BASE_SECONDS` (default: `1`)

Example:

- `flutter run -d macos --dart-define=MEDTRACK_API_BASE_URL=http://localhost:3000/api --dart-define=MEDTRACK_SYNC_API_KEY=local-dev-sync-key --dart-define=MEDTRACK_PHARMACY_ID=1 --dart-define=MEDTRACK_POS_HWID=HW-00423`

## Run POS Frontend

1. Install Flutter dependencies:
	- `flutter pub get`
2. Run app:
	- `flutter run -d macos`

## Run Local POS Backend (Dev Proxy Only)

1. Install dependencies:
	- `cd backend && npm install`

2. Start dev proxy (default target is central backend `http://localhost:3000/api`):
	- `npm run dev`

Set `CENTRAL_BACKEND_API_BASE_URL` to change proxy target.

For production, point Flutter directly to `medtrack_web/backend` and do not deploy this local POS backend.

## Sync APIs Used By POS

- `GET /api/pos/sync-down`
- `POST /api/pos/sync-up`

These endpoints are already implemented in `backend/src/routes/pos.js`.
