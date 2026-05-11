const test = require('node:test');
const assert = require('node:assert/strict');

const {
  rateLimit,
  authenticateApiToken,
  requireRole,
  validateSyncHeaders,
  validateSyncPushPayload,
  safeError,
} = require('../middleware/security');

function createReq(overrides = {}) {
  const headers = new Map(Object.entries(overrides.headers || {}).map(([k, v]) => [k.toLowerCase(), v]));
  return {
    path: overrides.path || '/api/sync/push',
    method: overrides.method || 'POST',
    originalUrl: overrides.originalUrl || '/api/sync/push',
    ip: overrides.ip || '127.0.0.1',
    socket: { remoteAddress: '127.0.0.1' },
    query: overrides.query || {},
    body: overrides.body || {},
    auth: overrides.auth,
    requestContext: overrides.requestContext,
    header(name) {
      return headers.get(String(name).toLowerCase());
    },
  };
}

function createRes() {
  return {
    statusCode: 200,
    headers: {},
    payload: null,
    setHeader(key, value) {
      this.headers[key.toLowerCase()] = String(value);
    },
    status(code) {
      this.statusCode = Number(code);
      return this;
    },
    json(data) {
      this.payload = data;
      return this;
    },
  };
}

test('rateLimit returns 429 when threshold exceeded', () => {
  const middleware = rateLimit({ windowMs: 1000, max: 1, keyFn: () => 'test-key' });

  const req1 = createReq();
  const res1 = createRes();
  let called1 = false;
  middleware(req1, res1, () => {
    called1 = true;
  });

  const req2 = createReq();
  const res2 = createRes();
  let called2 = false;
  middleware(req2, res2, () => {
    called2 = true;
  });

  assert.equal(called1, true);
  assert.equal(called2, false);
  assert.equal(res2.statusCode, 429);
  assert.equal(res2.payload.error, 'rate limit exceeded');
});

test('authenticateApiToken accepts configured bearer token and sets auth context', () => {
  process.env.AUTH_TOKENS_JSON = JSON.stringify([
    { token: 'token-admin-1', role: 'admin', actor: 'security-admin' },
  ]);

  const req = createReq({ headers: { authorization: 'Bearer token-admin-1' } });
  const res = createRes();
  let called = false;

  authenticateApiToken()(req, res, () => {
    called = true;
  });

  delete process.env.AUTH_TOKENS_JSON;

  assert.equal(called, true);
  assert.equal(req.auth.role, 'admin');
  assert.equal(req.auth.actor, 'security-admin');
  assert.equal(req.auth.authenticated, true);
});

test('requireRole blocks unauthorized role with 403', () => {
  const req = createReq({ auth: { role: 'analyst' }, requestContext: { requestId: 'REQ-123' } });
  const res = createRes();

  let called = false;
  requireRole('admin', 'inspector')(req, res, () => {
    called = true;
  });

  assert.equal(called, false);
  assert.equal(res.statusCode, 403);
  assert.equal(res.payload.error, 'forbidden');
  assert.equal(res.payload.request_id, 'REQ-123');
});

test('validateSyncHeaders and validateSyncPushPayload enforce required fields', () => {
  const missingHeadersReq = createReq({
    headers: {},
    query: {},
    body: {},
  });

  const headerIssue = validateSyncHeaders(missingHeadersReq);
  const payloadIssue = validateSyncPushPayload({ events: [] });

  assert.equal(headerIssue, 'pharmacy identity header/query is required');
  assert.equal(payloadIssue, 'events must be a non-empty array');
});

test('safeError returns sanitized response with request id', () => {
  const req = createReq({
    method: 'POST',
    originalUrl: '/api/sync/push',
    requestContext: { requestId: 'REQ-ERROR', sourceIp: '10.0.0.10' },
  });
  const res = createRes();

  safeError(res, req, new Error('sensitive details should not leak'), 'sync push failed', 500);

  assert.equal(res.statusCode, 500);
  assert.equal(res.payload.error, 'sync push failed');
  assert.equal(res.payload.request_id, 'REQ-ERROR');
});
