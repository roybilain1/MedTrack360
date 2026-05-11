const crypto = require('crypto');

const DEFAULT_WINDOW_MS = 60 * 1000;
const DEFAULT_MAX = 120;

const rateState = new Map();

function normalized(v) {
  return String(v || '').trim();
}

function getClientIp(req) {
  const xff = normalized(req.header('x-forwarded-for'));
  if (xff) {
    return xff.split(',')[0].trim();
  }
  return normalized(req.ip || req.socket?.remoteAddress || 'unknown');
}

function redactObject(obj) {
  if (!obj || typeof obj !== 'object') return obj;
  const out = Array.isArray(obj) ? [] : {};
  for (const [k, v] of Object.entries(obj)) {
    const key = k.toLowerCase();
    if (
      key.includes('token')
      || key.includes('authorization')
      || key.includes('password')
      || key.includes('license')
      || key.includes('phone')
      || key.includes('email')
      || key.includes('owner')
      || key.includes('name')
    ) {
      out[k] = '[REDACTED]';
      continue;
    }

    if (v && typeof v === 'object') {
      out[k] = redactObject(v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

function safeLog(message, context = {}) {
  const payload = redactObject(context);
  const line = JSON.stringify(payload);
  console.log(`[SECURITY] ${message} ${line}`);
}

function attachRequestContext(req, res, next) {
  const requestId = normalized(req.header('x-request-id')) || crypto.randomUUID();
  req.requestContext = {
    requestId,
    sourceIp: getClientIp(req),
    startedAt: Date.now(),
  };
  res.setHeader('x-request-id', requestId);
  next();
}

function requestLogger(req, res, next) {
  const startedAt = Date.now();
  res.on('finish', () => {
    safeLog('request', {
      request_id: req.requestContext?.requestId,
      method: req.method,
      path: req.originalUrl,
      status: res.statusCode,
      latency_ms: Date.now() - startedAt,
      source_ip: req.requestContext?.sourceIp,
      user_agent: normalized(req.header('user-agent')).slice(0, 120),
    });
  });
  next();
}

function rateLimit(options = {}) {
  const windowMs = Number(options.windowMs || DEFAULT_WINDOW_MS);
  const max = Number(options.max || DEFAULT_MAX);
  const keyFn = options.keyFn || ((req) => `${getClientIp(req)}:${req.path}`);

  return (req, res, next) => {
    const key = keyFn(req);
    const now = Date.now();
    const record = rateState.get(key) || { count: 0, resetAt: now + windowMs };

    if (record.resetAt <= now) {
      record.count = 0;
      record.resetAt = now + windowMs;
    }

    record.count += 1;
    rateState.set(key, record);

    if (record.count > max) {
      return res.status(429).json({
        error: 'rate limit exceeded',
        request_id: req.requestContext?.requestId,
      });
    }

    res.setHeader('x-ratelimit-limit', String(max));
    res.setHeader('x-ratelimit-remaining', String(Math.max(0, max - record.count)));
    res.setHeader('x-ratelimit-reset', String(Math.floor(record.resetAt / 1000)));
    return next();
  };
}

function buildTokenStore() {
  const store = new Map();

  const rawJson = normalized(process.env.AUTH_TOKENS_JSON);
  if (rawJson) {
    try {
      const list = JSON.parse(rawJson);
      if (Array.isArray(list)) {
        for (const row of list) {
          const token = normalized(row?.token);
          const role = normalized(row?.role || 'analyst').toLowerCase();
          const actor = normalized(row?.actor || role);
          if (token) store.set(token, { role, actor });
        }
      }
    } catch {
      safeLog('auth_tokens_json_invalid');
    }
  }

  const adminToken = normalized(process.env.AUTH_ADMIN_TOKEN);
  if (adminToken) store.set(adminToken, { role: 'admin', actor: 'admin' });

  const inspectorToken = normalized(process.env.AUTH_INSPECTOR_TOKEN);
  if (inspectorToken) store.set(inspectorToken, { role: 'inspector', actor: 'inspector' });

  const analystToken = normalized(process.env.AUTH_ANALYST_TOKEN);
  if (analystToken) store.set(analystToken, { role: 'analyst', actor: 'analyst' });

  return store;
}

function parseBearer(req) {
  const header = normalized(req.header('authorization'));
  if (!header) return '';
  const [scheme, token] = header.split(' ');
  if (String(scheme).toLowerCase() !== 'bearer') return '';
  return normalized(token);
}

function authenticateApiToken(options = {}) {
  const allowWhenUnconfigured = options.allowWhenUnconfigured !== false;
  return (req, res, next) => {
    const store = buildTokenStore();
    if (store.size === 0 && allowWhenUnconfigured) {
      req.auth = { role: 'admin', actor: 'bootstrap', authenticated: false };
      return next();
    }

    const token = parseBearer(req);
    if (!token || !store.has(token)) {
      return res.status(401).json({
        error: 'unauthorized',
        request_id: req.requestContext?.requestId,
      });
    }

    const auth = store.get(token);
    req.auth = {
      role: auth.role,
      actor: auth.actor,
      authenticated: true,
    };
    return next();
  };
}

function requireRole(...roles) {
  const allowed = new Set(roles.map((r) => normalized(r).toLowerCase()));
  return (req, res, next) => {
    const role = normalized(req.auth?.role).toLowerCase();
    if (!role || !allowed.has(role)) {
      return res.status(403).json({
        error: 'forbidden',
        request_id: req.requestContext?.requestId,
      });
    }
    return next();
  };
}

function buildDeviceTokenStore() {
  const store = new Map();
  const deviceToken = normalized(
    process.env.DEVICE_SYNC_API_KEY || process.env.POS_SYNC_API_KEY || process.env.SYNC_API_KEY
  );
  if (deviceToken) {
    store.set(deviceToken, { role: 'device', actor: 'pos_device' });
  }
  return store;
}

function authenticateDevice(options = {}) {
  const allowWhenUnconfigured = options.allowWhenUnconfigured !== false;
  return (req, res, next) => {
    const store = buildDeviceTokenStore();
    if (store.size === 0 && allowWhenUnconfigured) {
      req.device = { role: 'device', actor: 'bootstrap', authenticated: false };
      return next();
    }

    const token = normalized(req.header('x-sync-key'));
    if (!token || !store.has(token)) {
      return res.status(401).json({
        error: 'invalid_device_credentials',
        request_id: req.requestContext?.requestId,
      });
    }

    const auth = store.get(token);
    req.device = {
      role: auth.role,
      actor: auth.actor,
      authenticated: true,
      deviceId: normalized(req.header('x-device-id') || req.query.device_id || req.body?.device_id || req.query.hwid || req.body?.hwid),
      pharmacyId: normalized(req.header('x-pharmacy-id') || req.query.pharmacy_id || req.body?.pharmacy_id),
      licenseNumber: normalized(req.header('x-license-number') || req.query.license_number || req.body?.license_number),
    };
    return next();
  };
}

function requireDevice() {
  return (req, res, next) => {
    if (!req.device || normalized(req.device.role).toLowerCase() !== 'device') {
      return res.status(403).json({
        error: 'device_access_required',
        request_id: req.requestContext?.requestId,
      });
    }
    if (!normalized(req.device.deviceId)) {
      return res.status(400).json({
        error: 'device identity header/query is required',
        request_id: req.requestContext?.requestId,
      });
    }
    return next();
  };
}

function forbidAdminTokens() {
  return (req, res, next) => {
    const token = parseBearer(req);
    if (!token) return next();

    const adminStore = buildTokenStore();
    if (adminStore.has(token)) {
      return res.status(403).json({
        error: 'admin_tokens_cannot_access_device_routes',
        request_id: req.requestContext?.requestId,
      });
    }
    return next();
  };
}

function rateLimitWeb(options = {}) {
  const windowMs = Number(options.windowMs || DEFAULT_WINDOW_MS);
  const max = Number(options.max || 60);
  return rateLimit({
    windowMs,
    max,
    keyFn: (req) => {
      const actor = normalized(req.auth?.actor || 'anonymous');
      return `web:${actor}:${req.path}`;
    },
  });
}

function rateLimitDevice(options = {}) {
  const windowMs = Number(options.windowMs || DEFAULT_WINDOW_MS);
  const max = Number(options.max || 300);
  return rateLimit({
    windowMs,
    max,
    keyFn: (req) => {
      const deviceId = normalized(req.device?.deviceId || req.header('x-device-id') || req.query.device_id || req.query.hwid || req.body?.device_id || req.body?.hwid || 'unknown');
      return `device:${deviceId}:${req.path}`;
    },
  });
}

function validateSyncHeaders(req) {
  const pharmacyId = normalized(req.header('x-pharmacy-id') || req.query.pharmacy_id || req.body?.pharmacy_id);
  const deviceId = normalized(req.header('x-device-id') || req.query.device_id || req.query.hwid || req.body?.device_id || req.body?.hwid);
  if (!pharmacyId && !normalized(req.header('x-license-number') || req.query.license_number || req.body?.license_number)) {
    return 'pharmacy identity header/query is required';
  }
  if (!deviceId) {
    return 'device identity header/query is required';
  }
  return null;
}

function validateSyncPushPayload(body) {
  if (!body || typeof body !== 'object') return 'request body must be a JSON object';
  const events = body.events;
  if (!Array.isArray(events) || events.length === 0) return 'events must be a non-empty array';
  if (events.length > 1000) return 'events too large';
  return null;
}

function safeError(res, req, error, fallbackMessage = 'internal error', status = 500) {
  const requestId = req?.requestContext?.requestId || crypto.randomUUID();
  safeLog('error', {
    request_id: requestId,
    path: req?.originalUrl,
    method: req?.method,
    message: normalized(error?.message),
    source_ip: req?.requestContext?.sourceIp,
  });
  return res.status(status).json({
    error: fallbackMessage,
    request_id: requestId,
  });
}

module.exports = {
  normalized,
  safeLog,
  getClientIp,
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
  validateSyncHeaders,
  validateSyncPushPayload,
  safeError,
};
