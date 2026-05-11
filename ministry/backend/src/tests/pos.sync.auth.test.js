const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const posRoutes = require('../routes/pos');
const {
  attachRequestContext,
  authenticateDevice,
  requireDevice,
} = require('../middleware/security');

test('pos sync-up rejects when device sync key is configured but missing', async () => {
  const previousPosSyncKey = process.env.POS_SYNC_API_KEY;
  process.env.POS_SYNC_API_KEY = 'required-sync-key';

  const app = express();
  app.use(express.json());
  app.use(attachRequestContext);
  app.use('/api/pos', authenticateDevice(), requireDevice(), posRoutes);
  const server = app.listen(0);

  try {
    const { port } = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/api/pos/sync-up`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        pharmacy_id: 1,
        hwid: 'HW-00423',
        sales: [],
        movements: [],
      }),
    });

    assert.equal(response.status, 401);
    const body = await response.json();
    assert.equal(body.error, 'invalid_device_credentials');
  } finally {
    server.close();
    if (previousPosSyncKey == null) {
      delete process.env.POS_SYNC_API_KEY;
    } else {
      process.env.POS_SYNC_API_KEY = previousPosSyncKey;
    }
  }
});

test('readSyncProtocolVersion falls back to default when missing', () => {
  const { readSyncProtocolVersion, DEFAULT_SYNC_PROTOCOL_VERSION } = posRoutes._test;
  const version = readSyncProtocolVersion({ body: {}, query: {}, header: () => '' });
  assert.equal(version, DEFAULT_SYNC_PROTOCOL_VERSION);
});
