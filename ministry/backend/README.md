# MedTrack POS Local Backend (Dev Proxy / Deprecated)

This server is no longer a production backend. It is a development-only proxy shim that forwards POS routes to the central backend in `medtrack_web/backend`.

## Endpoints

- `GET /api/health`: proxy health status for central backend.
- `GET /api/pos/*`: proxy to central backend POS routes.
- `POST /api/pos/*`: proxy to central backend POS routes.
- Legacy local-only endpoints return `410 Deprecated`.

## Setup

1. Install dependencies:
   - `cd backend && npm install`
2. Start server:
   - `npm run dev`

Optional env:

- `PORT` (default `3001`)
- `CENTRAL_BACKEND_API_BASE_URL` (default `http://localhost:3000/api`)

Production source of truth is `medtrack_web/backend`.
