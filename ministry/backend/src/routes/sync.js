const express = require('express');
const db = require('../db');
const {
  normalized,
  stableUuid,
  validatePushBody,
  authenticatePharmacyDevice,
  assertAndStoreSyncRequest,
  markSyncRequestResult,
  processPushEvents,
  pullSyncData,
} = require('../services/sync_service');
const {
  validateSyncHeaders,
  validateSyncPushPayload,
  safeError,
} = require('../middleware/security');

const router = express.Router();

function classifySyncError(error) {
  const message = String(error?.message || 'sync error');
  const normalizedMessage = message.toLowerCase();

  if (normalizedMessage.includes('x-device-id header is required')) {
    return { status: 400, message: 'x-device-id header is required' };
  }
  if (normalizedMessage.includes('x-pharmacy-id or x-license-number header is required')) {
    return { status: 400, message: 'x-pharmacy-id or x-license-number header is required' };
  }
  if (normalizedMessage.includes('pharmacy not found')) {
    return { status: 404, message: 'pharmacy not found for sync identity' };
  }
  if (normalizedMessage.includes('device is not authorized for this pharmacy')) {
    return { status: 403, message: 'device is not authorized for this pharmacy' };
  }

  return { status: 500, message: null };
}




function authContextFromRequest(req) {
  return {
    pharmacyId:
      req.header('x-pharmacy-id') ||
      req.query.pharmacy_id ||
      req.body?.pharmacy_id,
    deviceId:
      req.header('x-device-id') ||
      req.query.device_id ||
      req.query.hwid ||
      req.body?.device_id ||
      req.body?.hwid,
    licenseNumber:
      req.header('x-license-number') ||
      req.query.license_number ||
      req.body?.license_number,
  };
}

function classifyPushConflicts(conflicts) {
  const rejected = [];
  const warnings = [];

  for (const conflict of (Array.isArray(conflicts) ? conflicts : [])) {
    const code = normalized(conflict?.code).toLowerCase();
    if (code === 'invalid_event_payload') {
      rejected.push(conflict);
      continue;
    }
    warnings.push(conflict);
  }

  return { rejected, warnings };
}

router.post('/push', async (req, res) => {

  const headerIssue = validateSyncHeaders(req);
  if (headerIssue) {
    return res.status(400).json({ error: headerIssue, request_id: req.requestContext?.requestId });
  }

  const payloadIssue = validateSyncPushPayload(req.body || {});
  if (payloadIssue) {
    return res.status(400).json({ error: payloadIssue, request_id: req.requestContext?.requestId });
  }

  const validated = validatePushBody(req.body || {});
  if (validated.error) {
    return res.status(400).json({ error: validated.error, request_id: req.requestContext?.requestId });
  }

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');

    const pharmacy = await authenticatePharmacyDevice(client, authContextFromRequest(req));
    const deviceId = normalized(authContextFromRequest(req).deviceId);

    const dedupe = await assertAndStoreSyncRequest(client, {
      requestId: validated.value.requestId,
      pharmacyId: pharmacy.id,
      deviceId,
      endpoint: '/api/sync/push',
      payload: req.body || {},
    });

    if (dedupe.isDuplicate) {
      await client.query('COMMIT');
      return res.json(
        dedupe.responsePayload || {
          status: 'success',
          duplicate: true,
          request_id: validated.value.requestId,
        }
      );
    }

    const result = await processPushEvents(client, {
      pharmacy,
      deviceId,
      events: validated.value.events,
      requestId: req.requestContext?.requestId,
      sourceIp: req.requestContext?.sourceIp,
      actorIdentity: req.auth?.actor || 'sync_device',
      actorRole: req.auth?.role || 'device',
    });

    const classified = classifyPushConflicts(result.conflicts);

    const responsePayload = {
      status: 'success',
      request_id: validated.value.requestId,
      accepted_event_ids: result.acceptedEventIds,
      duplicate_event_ids: result.duplicateEventIds,
      rejected_event_ids: classified.rejected
        .map((c) => normalized(c?.event_id))
        .filter(Boolean),
      accepted: result.acceptedEventIds,
      rejected: classified.rejected,
      warnings: classified.warnings,
      conflicts: result.conflicts,
      server_time_utc: new Date().toISOString(),
    };

    await markSyncRequestResult(client, {
      syncRequestId: dedupe.syncRequestId,
      status: 'completed',
      response: responsePayload,
    });

    await client.query('COMMIT');
    return res.json(responsePayload);
  } catch (error) {
    await client.query('ROLLBACK');
    const classified = classifySyncError(error);
    if (classified.status < 500) {
      return res.status(classified.status).json({
        error: classified.message,
        request_id: req.requestContext?.requestId,
      });
    }
    return safeError(res, req, error, 'sync push failed', 500);
  } finally {
    client.release();
  }
});

router.get('/pull', async (req, res) => {

  const headerIssue = validateSyncHeaders(req);
  if (headerIssue) {
    return res.status(400).json({ error: headerIssue, request_id: req.requestContext?.requestId });
  }

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');

    const pharmacy = await authenticatePharmacyDevice(client, authContextFromRequest(req));
    const deviceId = normalized(authContextFromRequest(req).deviceId);

    const payload = await pullSyncData(client, {
      pharmacy,
      cursor: normalized(req.query.cursor),
      limit: req.query.limit,
    });

    const batchId = stableUuid(
      `sync-batch:${pharmacy.id}:${deviceId}:${payload.next_cursor || 'end'}:${Date.now()}`
    );

    await client.query(
      `INSERT INTO sync_outbox (
         event_uuid,
         pharmacy_id,
         device_id,
         direction,
         stream,
         payload,
         sync_status,
         created_at,
         updated_at
       )
       VALUES ($1::uuid, $2, $3, 'server_to_pos', 'sync_batch', $4::jsonb, 'sent', NOW(), NOW())
       ON CONFLICT (event_uuid) DO NOTHING`,
      [
        batchId,
        pharmacy.id,
        deviceId,
        JSON.stringify({
          cursor: normalized(req.query.cursor) || null,
          next_cursor: payload.next_cursor,
          event_count: payload.events.length,
        }),
      ]
    );

    await client.query('COMMIT');

    return res.json({
      status: 'success',
      batch_id: batchId,
      next_cursor: payload.next_cursor,
      checkpoint_token: payload.next_cursor,
      server_time_utc: new Date().toISOString(),
      data: payload,
    });
  } catch (error) {
    await client.query('ROLLBACK');
    const classified = classifySyncError(error);
    if (classified.status < 500) {
      return res.status(classified.status).json({
        error: classified.message,
        request_id: req.requestContext?.requestId,
      });
    }
    return safeError(res, req, error, 'sync pull failed', 500);
  } finally {
    client.release();
  }
});

router.post('/ack', async (req, res) => {

  const headerIssue = validateSyncHeaders(req);
  if (headerIssue) {
    return res.status(400).json({ error: headerIssue, request_id: req.requestContext?.requestId });
  }

  const requestId = normalized(req.body?.request_id || req.body?.requestId);
  const batchId = normalized(req.body?.batch_id || req.body?.batchId);
  const checkpointToken = normalized(req.body?.checkpoint_token || req.body?.checkpointToken);

  if (!requestId || !batchId) {
    return res.status(400).json({ error: 'request_id and batch_id are required', request_id: req.requestContext?.requestId });
  }

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');

    const pharmacy = await authenticatePharmacyDevice(client, authContextFromRequest(req));
    const deviceId = normalized(authContextFromRequest(req).deviceId);

    const dedupe = await assertAndStoreSyncRequest(client, {
      requestId,
      pharmacyId: pharmacy.id,
      deviceId,
      endpoint: '/api/sync/ack',
      payload: req.body || {},
    });

    if (!dedupe.isDuplicate) {
      await client.query(
        `UPDATE sync_outbox
         SET sync_status = 'synced',
             updated_at = NOW()
         WHERE event_uuid = $1::uuid
           AND pharmacy_id = $2
           AND device_id = $3`,
        [batchId, pharmacy.id, deviceId]
      );

      await client.query(
        `INSERT INTO sync_checkpoint (
           pharmacy_id,
           device_id,
           stream,
           checkpoint_token,
           checkpoint_time,
           updated_at
         )
         VALUES ($1, $2, 'server_to_pos', $3, NOW(), NOW())
         ON CONFLICT (device_id, stream)
         DO UPDATE SET
           pharmacy_id = EXCLUDED.pharmacy_id,
           checkpoint_token = EXCLUDED.checkpoint_token,
           checkpoint_time = EXCLUDED.checkpoint_time,
           updated_at = NOW()`,
        [
          pharmacy.id,
          deviceId,
          checkpointToken || new Date().toISOString(),
        ]
      );

      const responsePayload = {
        status: 'success',
        acked_batch_id: batchId,
        acked_checkpoint_token: checkpointToken || new Date().toISOString(),
        request_id: requestId,
        server_time_utc: new Date().toISOString(),
      };

      await markSyncRequestResult(client, {
        syncRequestId: dedupe.syncRequestId,
        status: 'completed',
        response: responsePayload,
      });

      await client.query('COMMIT');
      return res.json(responsePayload);
    }

    await client.query('COMMIT');
    return res.json(
      dedupe.responsePayload || {
        status: 'success',
        duplicate: true,
        acked_batch_id: batchId,
        request_id: requestId,
      }
    );
  } catch (error) {
    await client.query('ROLLBACK');
    const classified = classifySyncError(error);
    if (classified.status < 500) {
      return res.status(classified.status).json({
        error: classified.message,
        request_id: req.requestContext?.requestId,
      });
    }
    return safeError(res, req, error, 'sync ack failed', 500);
  } finally {
    client.release();
  }
});

router.get('/regulations/prices', async (req, res) => {

  const limitRaw = Number.parseInt(req.query.limit, 10);
  const limit = Number.isFinite(limitRaw) ? Math.min(Math.max(limitRaw, 1), 1000) : 500;

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    await authenticatePharmacyDevice(client, authContextFromRequest(req));

    const result = await client.query(
      `SELECT
         barcode,
         trade_name,
         dosage,
         CAST(ROUND(moph_ceiling * 100) AS BIGINT) AS regulated_price_minor,
         'USD'::varchar AS currency_code,
         is_blocked,
         updated_at
       FROM moph_registry
       ORDER BY updated_at DESC
       LIMIT $1`,
      [limit]
    );

    await client.query('COMMIT');

    res.json({
      status: 'success',
      count: result.rows.length,
      data: result.rows,
      server_time_utc: new Date().toISOString(),
    });
  } catch (error) {
    await client.query('ROLLBACK');
    res.status(500).json({ error: error.message || 'failed to fetch regulations prices' });
  } finally {
    client.release();
  }
});

router.get('/compliance/alerts', async (req, res) => {

  const limitRaw = Number.parseInt(req.query.limit, 10);
  const limit = Number.isFinite(limitRaw) ? Math.min(Math.max(limitRaw, 1), 1000) : 500;
  const status = normalized(req.query.status || 'open').toLowerCase();

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');

    const pharmacy = await authenticatePharmacyDevice(client, authContextFromRequest(req));

    const rows = await client.query(
      `SELECT
         alert_uuid,
         pharmacy_id,
         device_id,
         barcode,
         alert_type,
         severity,
         title,
         details,
         status,
         created_at,
         acknowledged_at,
         resolved_at,
         updated_at
       FROM compliance_alerts
       WHERE deleted_at IS NULL
         AND (pharmacy_id IS NULL OR pharmacy_id = $1)
         AND ($2 = '' OR status = $2)
       ORDER BY created_at DESC
       LIMIT $3`,
      [pharmacy.id, status === 'all' ? '' : status, limit]
    );

    await client.query('COMMIT');

    res.json({
      status: 'success',
      count: rows.rows.length,
      data: rows.rows,
      server_time_utc: new Date().toISOString(),
    });
  } catch (error) {
    await client.query('ROLLBACK');
    res.status(500).json({ error: error.message || 'failed to fetch compliance alerts' });
  } finally {
    client.release();
  }
});

router.get('/announcements', async (req, res) => {
  const limitRaw = Number.parseInt(req.query.limit, 10);
  const limit = Number.isFinite(limitRaw) ? Math.min(Math.max(limitRaw, 1), 200) : 50;
  try {
    const rows = await db.query(
      `SELECT news_id AS id, title, body, source, url, published_at AS created_at, published_at AS updated_at
       FROM health_news
       WHERE is_active = true
       ORDER BY published_at DESC
       LIMIT $1`,
      [limit]
    );
    res.json({
      status: 'success',
      count: rows.rows.length,
      data: rows.rows,
      server_time_utc: new Date().toISOString(),
    });
  } catch (error) {
    res.status(500).json({ error: error.message || 'failed to fetch announcements' });
  }
});

router.get('/health', async (req, res) => {

  try {
    const rows = await db.query(
      `SELECT
         p.id AS pharmacy_id,
         p.name AS pharmacy_name,
         p.hwid AS device_id,
         p.license_number,
         p.region,
         p.status,
         p.last_seen,
         p.sync_version,
         p.sync_pct,
         s.last_sync_up,
         s.last_sync_down,
         COALESCE(o.pending_count, 0)::int AS pending_outbox,
         COALESCE(a.open_alerts, 0)::int AS open_alerts,
         COALESCE(m.movement_count, 0)::int AS movement_events,
         m.last_movement_at
       FROM pharmacies p
       LEFT JOIN pos_sync_state s ON s.pharmacy_id = p.id
       LEFT JOIN (
         SELECT pharmacy_id, COUNT(*) AS pending_count
         FROM sync_outbox
         WHERE sync_status = 'pending'
         GROUP BY pharmacy_id
       ) o ON o.pharmacy_id = p.id
       LEFT JOIN (
         SELECT pharmacy_id, COUNT(*) AS open_alerts
         FROM compliance_alerts
         WHERE status = 'open' AND deleted_at IS NULL
         GROUP BY pharmacy_id
       ) a ON a.pharmacy_id = p.id
       LEFT JOIN (
         SELECT pharmacy_id, COUNT(*) AS movement_count, MAX(updated_at) AS last_movement_at
         FROM inventory_movements
         WHERE deleted_at IS NULL
         GROUP BY pharmacy_id
       ) m ON m.pharmacy_id = p.id
       ORDER BY p.name ASC`,
      []
    );

    res.json({
      status: 'success',
      count: rows.rows.length,
      data: rows.rows,
      server_time_utc: new Date().toISOString(),
    });
  } catch (error) {
    res.status(500).json({ error: error.message || 'failed to fetch sync health' });
  }
});

module.exports = router;
