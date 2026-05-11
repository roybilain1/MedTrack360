require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { initializeSchema, checkDatabaseConnection } = require('./db');
const {
  attachRequestContext,
  requestLogger,
  rateLimit,
  rateLimitWeb,
  rateLimitDevice,
  authenticateApiToken,
  authenticateDevice,
  requireRole,
  requireDevice,
  forbidAdminTokens,
  safeError,
} = require('./middleware/security');

const webRoutes = require('./routes/web');
const posRoutes = require('./routes/pos');
const syncRoutes = require('./routes/sync');
const monitoringRoutes = require('./routes/monitoring');
const inventorySnapshotRoutes = require('./routes/inventory_snapshot');
const announcementsRoutes = require('./routes/announcements');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use(attachRequestContext);
app.use(requestLogger);

const publicOperationalRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 1000,
  keyFn: (req) => `public:${req.ip || req.socket?.remoteAddress || 'unknown'}:${req.path}`,
});

// ────────────────────────────────────────────────────────────────────────────
// ROUTE GROUPS: Separate Auth Domains
// ────────────────────────────────────────────────────────────────────────────

// WEB DASHBOARD: Human admin/inspector/analyst access
// Auth: Bearer token (human session from login)
// Rate Limit: 60/min per actor
app.use('/api/web', rateLimitWeb(), authenticateApiToken(), requireRole('admin', 'inspector', 'analyst'), webRoutes);
app.use('/api/web/monitoring', rateLimitWeb(), authenticateApiToken(), requireRole('admin', 'inspector', 'analyst'), monitoringRoutes);
app.use('/api/web/announcements', rateLimitWeb(), authenticateApiToken(), requireRole('admin'), announcementsRoutes);

// POS DEVICE SYNC: Device credentials only
// Auth: X-Sync-Key header (device credentials)
// Rate Limit: 300/min per device
// Important: Forbid admin tokens on device routes (security boundary)
app.use('/api/pos', rateLimitDevice(), forbidAdminTokens(), authenticateDevice(), requireDevice(), posRoutes);

// GENERIC SYNC: Device credentials only (per sync_service)
// Auth: X-Sync-Key header (device credentials)
// Rate Limit: 300/min per device
// Important: Forbid admin tokens on device routes (security boundary)
app.use('/api/sync', rateLimitDevice(), forbidAdminTokens(), authenticateDevice(), syncRoutes);
app.use('/api/sync/inventory-snapshot', rateLimitDevice(), forbidAdminTokens(), authenticateDevice(), inventorySnapshotRoutes);

// ────────────────────────────────────────────────────────────────────────────
// PUBLIC HEALTH CHECK
// ────────────────────────────────────────────────────────────────────────────

app.get('/health', publicOperationalRateLimit, async (req, res) => {
  try {
    const dbOk = await checkDatabaseConnection();
    res.status(dbOk ? 200 : 503).json({
      status: dbOk ? 'ok' : 'degraded',
      database: dbOk ? 'connected' : 'disconnected',
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(503).json({
      status: 'degraded',
      database: 'disconnected',
      error: error.message,
      timestamp: new Date().toISOString(),
    });
  }
});

// ────────────────────────────────────────────────────────────────────────────
// ERROR HANDLING
// ────────────────────────────────────────────────────────────────────────────

app.use((err, req, res, next) => {
  if (res.headersSent) return next(err);
  return safeError(res, req, err, 'internal server error', 500);
});

// ────────────────────────────────────────────────────────────────────────────
// SERVER STARTUP
// ────────────────────────────────────────────────────────────────────────────

async function startServer() {
  if (!process.env.DATABASE_URL && !process.env.POSTGRES_URL && !process.env.POSTGRES_URI) {
    console.warn(
      '[App] DATABASE_URL is not set. Falling back to local default postgres URL (postgresql://postgres:postgres@localhost:5432/medtrack).'
    );
  }

  try {
    console.log('[App] Connecting to PostgreSQL and verifying schema...');
    await initializeSchema();
    console.log('[App] Database initialized successfully.');
  } catch (error) {
    // Keep server running so /health can report DB status and deployments stay reachable.
    console.error('[App] Database init failed. Starting API in degraded mode:', error.message);
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`[App] Server listening on http://localhost:${PORT}`);
  });
}

startServer();
