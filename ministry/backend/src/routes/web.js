const express = require('express');
const router = express.Router();
const db = require('../db');

// ── Helper ────────────────────────────────────────────────────────────────────
const uid = (prefix) => `${prefix}-${Date.now().toString().slice(-6)}`;

const toInt = (value, fallback = 0) => {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
};

const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

const toIsoString = (value) => {
  if (!value) return null;
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return null;
  return dt.toISOString();
};

function readListParams(req, { defaultLimit = 200, maxLimit = 500 } = {}) {
  const requestedLimit = toInt(req.query.limit, defaultLimit);
  const pageSize = clamp(requestedLimit, 1, maxLimit);
  const page = clamp(toInt(req.query.page, 1), 1, 100000);
  const offset = (page - 1) * pageSize;
  return { page, pageSize, offset };
}

function listMeta({ count, filters = {}, sort = null }) {
  return {
    count: toInt(count, 0),
    empty: toInt(count, 0) === 0,
    filters,
    sort,
    generated_at: new Date().toISOString(),
  };
}

// ── MoPH Registry ─────────────────────────────────────────────────────────────
router.get('/registry', async (req, res) => {
  try {
    const r = await db.query(
      `SELECT
         r.*,
         COALESCE(r.quantity, 0) AS stock_units,
         MAX(ns.last_sync) AS last_sync,
         MIN(ns.threshold) AS threshold,
         CASE
           WHEN COALESCE(r.quantity, 0) <= 0 THEN 'critical'
           WHEN COALESCE(r.quantity, 0) < COALESCE(MIN(ns.threshold), 30) THEN 'low'
           ELSE 'safe'
         END AS stock_status
       FROM moph_registry r
       LEFT JOIN national_stock ns ON ns.barcode = r.barcode
       GROUP BY r.id
       ORDER BY r.trade_name ASC`
    );
    res.json({
      status: 'success',
      data: r.rows,
      pagination: {
        page: 1,
        pageSize: r.rows.length,
        total: r.rows.length,
        totalPages: 1,
      },
      meta: listMeta({
        count: r.rows.length,
        sort: { by: 'trade_name', dir: 'asc' },
      }),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

router.post('/registry/:id/price', async (req, res) => {
  const { price } = req.body;
  const parsed = Number(price);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return res.status(400).json({ error: 'Invalid price' });
  }

  try {
    const old = await db.query('SELECT moph_ceiling FROM moph_registry WHERE id=$1', [req.params.id]);
    const oldPrice = old.rows[0]?.moph_ceiling;
    
    const r = await db.query(
      `UPDATE moph_registry
       SET moph_ceiling=$1, updated_at=NOW()
       WHERE id=$2
       RETURNING *`,
      [parsed, req.params.id]
    );
    if (!r.rows.length) return res.status(404).json({ error: 'Not found' });
    
    // Log the change for POS notification
    if (oldPrice !== parsed) {
      await db.query(
        `INSERT INTO change_log (change_type, entity_id, entity_type, old_value, new_value, changed_by, synced_to_pos)
         VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6, false)`,
        ['price_update', req.params.id, 'medication', JSON.stringify({ price: oldPrice }), JSON.stringify({ price: parsed }), 'admin']
      );
    }
    
    res.json({ status: 'success', data: r.rows[0] });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.post('/registry/:id/adjust-stock', async (req, res) => {
  const { delta, reason } = req.body;
  const qty = parseInt(delta, 10);
  if (!Number.isInteger(qty)) {
    return res.status(400).json({ error: 'Invalid delta' });
  }

  try {
    const reg = await db.query('SELECT * FROM moph_registry WHERE id=$1', [req.params.id]);
    if (!reg.rows.length) return res.status(404).json({ error: 'Medication not found' });
    const med = reg.rows[0];

    const stockRow = await db.query('SELECT stock_units FROM national_stock WHERE barcode=$1', [med.barcode]);
    const oldStock = stockRow.rows[0]?.stock_units || 0;

    if (!stockRow.rows.length) {
      const startingStock = Math.max(0, qty);
      await db.query(
        `INSERT INTO national_stock (barcode, medication_name, category, stock_units, threshold, status, region, last_sync)
         VALUES ($1, $2, $3, $4, 1000, CASE WHEN $4 < 250 THEN 'critical' WHEN $4 < 1000 THEN 'low' ELSE 'safe' END, 'National', 'just now')`,
        [med.barcode, `${med.trade_name} ${med.dosage || ''}`.trim(), med.category || 'Other', startingStock]
      );
    } else {
      await db.query(
        `UPDATE national_stock
         SET
           stock_units = GREATEST(0, stock_units + $1),
           status = CASE
             WHEN GREATEST(0, stock_units + $1) <= 0 THEN 'critical'
             WHEN threshold > 0 AND GREATEST(0, stock_units + $1) < (threshold * 0.25) THEN 'critical'
             WHEN threshold > 0 AND GREATEST(0, stock_units + $1) < threshold THEN 'low'
             ELSE 'safe'
           END,
           last_sync = 'just now',
           updated_at = NOW()
         WHERE barcode=$2`,
        [qty, med.barcode]
      );
    }

    await db.query(
      `INSERT INTO audit_logs (event_id, event_type, item_name, unit_count, metadata)
       VALUES ($1, 'stock_adjust', $2, $3, $4::jsonb)`,
      [uid('EVT'), `${med.trade_name} ${med.dosage || ''}`.trim(), qty, JSON.stringify({ reason: reason || 'Manual adjustment' })]
    );

    // Log the stock change
    await db.query(
      `INSERT INTO change_log (change_type, entity_id, entity_type, old_value, new_value, changed_by, synced_to_pos)
       VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6, false)`,
      ['stock_adjust', req.params.id, 'medication', JSON.stringify({ stock: oldStock }), JSON.stringify({ stock: oldStock + qty }), 'admin']
    );

    res.json({ status: 'success' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.post('/registry', async (req, res) => {
  const { barcode, reg_number, trade_name, generic_name, dosage, form, manufacturer, category, moph_ceiling } = req.body;
  try {
    const r = await db.query(
      `INSERT INTO moph_registry (barcode,reg_number,trade_name,generic_name,dosage,form,manufacturer,category,moph_ceiling)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
       ON CONFLICT (barcode) DO UPDATE SET
         trade_name=EXCLUDED.trade_name, moph_ceiling=EXCLUDED.moph_ceiling, updated_at=NOW()
       RETURNING *`,
      [barcode, reg_number, trade_name, generic_name, dosage, form, manufacturer, category, moph_ceiling]
    );
    res.status(201).json({ status: 'success', data: r.rows[0] });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

router.put('/registry/:id', async (req, res) => {
  const { trade_name, generic_name, dosage, form, manufacturer, category, moph_ceiling } = req.body;
  try {
    const old = await db.query('SELECT moph_ceiling FROM moph_registry WHERE id=$1', [req.params.id]);
    const r = await db.query(
      `UPDATE moph_registry SET trade_name=$1,generic_name=$2,dosage=$3,form=$4,manufacturer=$5,category=$6,moph_ceiling=$7,updated_at=NOW()
       WHERE id=$8 RETURNING *`,
      [trade_name, generic_name, dosage, form, manufacturer, category, moph_ceiling, req.params.id]
    );
    
    // Log the change
    if (old.rows[0]?.moph_ceiling !== moph_ceiling || old.rows.length === 0) {
      await db.query(
        `INSERT INTO change_log (change_type, entity_id, entity_type, old_value, new_value, changed_by)
         VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6)`,
        ['price_update', req.params.id, 'medication', JSON.stringify({ price: old.rows[0]?.moph_ceiling }), JSON.stringify({ price: moph_ceiling }), 'admin']
      );
    }
    
    res.json({ status: 'success', data: r.rows[0] });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

router.delete('/registry/:id', async (req, res) => {
  try {
    await db.query('DELETE FROM moph_registry WHERE id=$1', [req.params.id]);
    res.json({ status: 'success' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Audit Logs ────────────────────────────────────────────────────────────────
router.get('/price-violations-summary', async (req, res) => {
  const requestedLimit = Number.parseInt(req.query.limit, 10);
  const limit = Number.isFinite(requestedLimit)
    ? Math.min(Math.max(requestedLimit, 1), 50)
    : 8;

  try {
    const r = await db.query(
      `SELECT *
       FROM audit_logs
       WHERE event_type = 'price_hike'
         AND (
           metadata->>'receipt_id' IS NOT NULL
           OR metadata->>'source' = 'inventory_snapshot'
         )
       ORDER BY created_at DESC
       LIMIT $1`,
      [limit]
    );

    const realRows = r.rows.map((row) => ({
      ...row,
      metadata: {
        ...(row.metadata || {}),
        source: 'real_pos',
      },
    }));

    res.json({
      status: 'success',
      data: realRows,
      pagination: {
        page: 1,
        pageSize: realRows.length,
        total: realRows.length,
        totalPages: 1,
      },
      meta: {
        count: realRows.length,
        sort: { by: 'created_at', dir: 'desc' },
      },
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/audit-logs', async (req, res) => {
  try {
    const { page, pageSize, offset } = readListParams(req, { defaultLimit: 200, maxLimit: 1000 });
    const r = await db.query(
      `SELECT *, COUNT(*) OVER()::int AS total_count
       FROM audit_logs
       ORDER BY created_at DESC, id DESC
       LIMIT $1 OFFSET $2`,
      [pageSize, offset]
    );
    const total = r.rows[0]?.total_count || 0;
    res.json({
      status: 'success',
      data: r.rows,
      pagination: {
        page,
        pageSize,
        total,
        totalPages: Math.max(1, Math.ceil(total / pageSize)),
      },
      meta: listMeta({
        count: r.rows.length,
        sort: { by: 'created_at,id', dir: 'desc' },
      }),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

router.post('/audit-logs', async (req, res) => {
  const { pharmacy_name, hwid, license_number, region, event_type, item_name, registry_price, charged_price, unit_count } = req.body;
  try {
    const r = await db.query(
      `INSERT INTO audit_logs (event_id,pharmacy_name,hwid,license_number,region,event_type,item_name,registry_price,charged_price,unit_count)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *`,
      [uid('EVT'), pharmacy_name, hwid, license_number, region, event_type, item_name, registry_price, charged_price, unit_count]
    );
    res.status(201).json({ status: 'success', data: r.rows[0] });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Pharmacies / POS Nodes ────────────────────────────────────────────────────
router.get('/pharmacies', async (req, res) => {
  try {
    const r = await db.query('SELECT * FROM pharmacies ORDER BY name ASC, id ASC');
    res.json({
      status: 'success',
      data: r.rows,
      pagination: {
        page: 1,
        pageSize: r.rows.length,
        total: r.rows.length,
        totalPages: 1,
      },
      meta: listMeta({
        count: r.rows.length,
        sort: { by: 'name,id', dir: 'asc' },
      }),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

router.get('/sync-health', async (req, res) => {
  try {
    const r = await db.query(
      `SELECT
         p.id,
         p.name,
         p.hwid,
         p.license_number,
         p.region,
         p.status,
         p.sync_version,
         p.sync_pct,
         p.last_seen,
         p.latency_ms,
         s.last_sync_up,
         s.last_sync_down,
         (SELECT COUNT(*)::int FROM sync_outbox o WHERE o.device_id = p.hwid AND o.sync_status = 'pending') AS pending_outbox,
         (SELECT COUNT(*)::int FROM compliance_alerts c WHERE c.pharmacy_id = p.id AND c.status = 'open') AS open_compliance_alerts
       FROM pharmacies p
       LEFT JOIN pos_sync_state s ON s.pharmacy_id = p.id
       ORDER BY p.name ASC, p.id ASC`
    );
    res.json({
      status: 'success',
      data: r.rows,
      pagination: {
        page: 1,
        pageSize: r.rows.length,
        total: r.rows.length,
        totalPages: 1,
      },
      meta: listMeta({
        count: r.rows.length,
        sort: { by: 'name,id', dir: 'asc' },
      }),
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/compliance-alerts', async (req, res) => {
  const { page, pageSize, offset } = readListParams(req, { defaultLimit: 200, maxLimit: 500 });
  const onlyOpen = String(req.query.only_open || 'true').toLowerCase() !== 'false';
  try {
    const r = await db.query(
      `SELECT
         c.*,
         p.name AS pharmacy_name,
         p.license_number,
         COUNT(*) OVER()::int AS total_count
       FROM compliance_alerts c
       LEFT JOIN pharmacies p ON p.id = c.pharmacy_id
       WHERE ($1::boolean = false OR c.status = 'open')
       ORDER BY c.created_at DESC, c.id DESC
       LIMIT $2 OFFSET $3`,
      [onlyOpen, pageSize, offset]
    );
    const total = r.rows[0]?.total_count || 0;
    res.json({
      status: 'success',
      data: r.rows,
      count: r.rows.length,
      pagination: {
        page,
        pageSize,
        total,
        totalPages: Math.max(1, Math.ceil(total / pageSize)),
      },
      meta: listMeta({
        count: r.rows.length,
        filters: { only_open: onlyOpen },
        sort: { by: 'created_at,id', dir: 'desc' },
      }),
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.post('/pharmacies/:id/flag', async (req, res) => {
  const { flag_type = 'inspection', note = '' } = req.body;
  try {
    const p = await db.query('SELECT * FROM pharmacies WHERE id=$1', [req.params.id]);
    if (!p.rows.length) return res.status(404).json({ error: 'Not found' });
    const ph = p.rows[0];
    const ref = uid(flag_type === 'inspection' ? 'INS' : 'VIO');
    await db.query(
      `INSERT INTO audit_logs (event_id,pharmacy_name,hwid,license_number,region,event_type,metadata)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [ref, ph.name, ph.hwid, ph.license_number, ph.region, flag_type, JSON.stringify({ note, ref })]
    );
    res.json({ status: 'success', ref });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Registration Requests ─────────────────────────────────────────────────────
router.get('/registration-requests', async (req, res) => {
  const { page, pageSize, offset } = readListParams(req, { defaultLimit: 200, maxLimit: 500 });
  const status = String(req.query.status || '').trim();
  try {
    const r = await db.query(
      `SELECT *, COUNT(*) OVER()::int AS total_count
       FROM registration_requests
       WHERE ($1 = '' OR status = $1)
       ORDER BY submitted_date DESC, id DESC
       LIMIT $2 OFFSET $3`,
      [status, pageSize, offset]
    );
    const total = r.rows[0]?.total_count || 0;
    res.json({
      status: 'success',
      data: r.rows,
      pagination: {
        page,
        pageSize,
        total,
        totalPages: Math.max(1, Math.ceil(total / pageSize)),
      },
      meta: listMeta({
        count: r.rows.length,
        filters: { status },
        sort: { by: 'submitted_date,id', dir: 'desc' },
      }),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

router.post('/registration-requests/:id/approve', async (req, res) => {
  try {
    const r = await db.query(
      "UPDATE registration_requests SET status='approved' WHERE id=$1 RETURNING *",
      [req.params.id]
    );
    if (!r.rows.length) return res.status(404).json({ error: 'Not found' });
    res.json({ status: 'success', data: r.rows[0] });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

router.post('/registration-requests/:id/reject', async (req, res) => {
  try {
    const r = await db.query(
      "UPDATE registration_requests SET status='rejected' WHERE id=$1 RETURNING *",
      [req.params.id]
    );
    if (!r.rows.length) return res.status(404).json({ error: 'Not found' });
    res.json({ status: 'success', data: r.rows[0] });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Medicine Onboarding Requests ────────────────────────────────────────────
router.get('/medicine-requests', async (req, res) => {
  const { page, pageSize, offset } = readListParams(req, { defaultLimit: 200, maxLimit: 500 });
  const status = String(req.query.status || '').trim();
  try {
    const r = await db.query(
      `SELECT m.*, p.name AS pharmacy_name, p.license_number, p.region, COUNT(*) OVER()::int AS total_count
       FROM medicine_registration_requests m
       LEFT JOIN pharmacies p ON p.id = m.pharmacy_id
       WHERE m.deleted_at IS NULL
         AND ($1 = '' OR m.request_status = $1)
       ORDER BY m.created_at DESC, m.id DESC
       LIMIT $2 OFFSET $3`,
      [status, pageSize, offset]
    );
    const total = r.rows[0]?.total_count || 0;
    res.json({
      status: 'success',
      data: r.rows,
      pagination: {
        page,
        pageSize,
        total,
        totalPages: Math.max(1, Math.ceil(total / pageSize)),
      },
      meta: listMeta({
        count: r.rows.length,
        filters: { status },
        sort: { by: 'created_at,id', dir: 'desc' },
      }),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

router.post('/medicine-requests/:id/approve', async (req, res) => {
  const requestId = Number(req.params.id);
  const payload = req.body || {};
  try {
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');
      const requestResult = await client.query(
        `SELECT * FROM medicine_registration_requests WHERE id = $1 AND deleted_at IS NULL LIMIT 1 FOR UPDATE`,
        [requestId]
      );
      const request = requestResult.rows[0];
      if (!request) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Not found' });
      }

      const approvedPrice = Number.isFinite(Number(payload.moph_ceiling))
        ? Number(payload.moph_ceiling)
        : (Number(request.proposed_price_minor) || 0) / 100;
      const tradeName = String(payload.trade_name || request.requested_name || request.barcode).trim();
      const genericName = String(payload.generic_name || request.generic_name || tradeName).trim();
      const dosage = String(payload.dosage || request.dosage || '').trim();
      const category = String(payload.category || request.category || '').trim();
      const form = String(payload.form || '').trim();
      const manufacturer = String(payload.manufacturer || '').trim();
      const regNumber = String(payload.reg_number || request.barcode).trim();

      const registryResult = await client.query(
        `INSERT INTO moph_registry (barcode, reg_number, trade_name, generic_name, dosage, form, manufacturer, category, moph_ceiling, is_blocked, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,false,NOW())
         ON CONFLICT (barcode) DO UPDATE SET
           reg_number = COALESCE(NULLIF(EXCLUDED.reg_number, ''), moph_registry.reg_number),
           trade_name = EXCLUDED.trade_name,
           generic_name = EXCLUDED.generic_name,
           dosage = EXCLUDED.dosage,
           form = EXCLUDED.form,
           manufacturer = EXCLUDED.manufacturer,
           category = EXCLUDED.category,
           moph_ceiling = EXCLUDED.moph_ceiling,
           is_blocked = false,
           updated_at = NOW()
         RETURNING *`,
        [request.barcode, regNumber, tradeName, genericName, dosage, form, manufacturer, category, approvedPrice]
      );

      const registryRow = registryResult.rows[0];

      if (registryRow?.medication_id && request.pharmacy_id) {
        const stockUnits = Number(request.stock_units) || 0;
        const priceMajor = (Number(request.proposed_price_minor) || 0) / 100;
        await client.query(
          `INSERT INTO pharmacy_stock (pharmacy_id, medication_id, in_stock, current_price, last_updated)
           VALUES ($1, $2, $3, $4, NOW())
           ON CONFLICT (pharmacy_id, medication_id) DO UPDATE SET
             in_stock = EXCLUDED.in_stock,
             current_price = EXCLUDED.current_price,
             last_updated = NOW()`,
          [request.pharmacy_id, registryRow.medication_id, stockUnits > 0, priceMajor]
        );
      }

      await client.query(
        `UPDATE medicine_registration_requests
         SET request_status = 'approved',
             official_medicine_id = $2,
             review_notes = COALESCE(NULLIF($3, ''), review_notes),
             reviewed_at = NOW(),
             updated_at = NOW()
         WHERE id = $1`,
        [requestId, registryRow?.id || null, String(payload.review_notes || '').trim()]
      );

      await client.query(
        `INSERT INTO change_log (change_type, entity_id, entity_type, old_value, new_value, changed_by, synced_to_pos)
         VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6, false)`,
        [
          'medicine_approval',
          request.barcode,
          'medication',
          JSON.stringify({ request_status: request.request_status }),
          JSON.stringify({ request_status: 'approved', registry_id: registryRow?.id || null, barcode: request.barcode }),
          'admin',
        ]
      );

      await client.query('COMMIT');
      res.json({ status: 'success', data: { ...request, request_status: 'approved', official_medicine_id: registryRow?.id || null } });
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  } catch (e) { res.status(500).json({ error: e.message }); }
});

router.post('/medicine-requests/:id/reject', async (req, res) => {
  const requestId = Number(req.params.id);
  const reviewNotes = String(req.body?.review_notes || '').trim();
  try {
    const r = await db.query(
      `UPDATE medicine_registration_requests
       SET request_status = 'rejected',
           review_notes = COALESCE(NULLIF($2, ''), review_notes),
           reviewed_at = NOW(),
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [requestId, reviewNotes]
    );
    if (!r.rows.length) return res.status(404).json({ error: 'Not found' });
    await db.query(
      `INSERT INTO change_log (change_type, entity_id, entity_type, old_value, new_value, changed_by, synced_to_pos)
       VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6, false)`,
      [
        'medicine_rejection',
        r.rows[0].barcode,
        'medication',
        JSON.stringify({ request_status: 'pending_review' }),
        JSON.stringify({ request_status: 'rejected', review_notes: reviewNotes }),
        'admin',
      ]
    );
    res.json({ status: 'success', data: r.rows[0] });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Hoarding Anomalies ────────────────────────────────────────────────────────
router.get('/hoarding-anomalies', async (req, res) => {
  try {
    const r = await db.query(`
      WITH flow AS (
        SELECT
          COALESCE(a.pharmacy_name, p.name) AS pharmacy_name,
          COALESCE(a.license_number, p.license_number) AS license_number,
          COALESCE(a.hwid, p.hwid) AS hwid,
          COALESCE(a.region, p.region) AS region,
          SUM(CASE WHEN a.event_type IN ('receipt', 'stock_adjust') AND COALESCE(a.unit_count, 0) > 0 THEN a.unit_count ELSE 0 END) AS incoming_units,
          SUM(CASE WHEN a.event_type = 'sale' AND COALESCE(a.unit_count, 0) > 0 THEN a.unit_count ELSE 0 END) AS outgoing_units,
          ARRAY_REMOVE(ARRAY_AGG(DISTINCT CASE WHEN a.event_type = 'price_hike' THEN a.item_name END), NULL) AS flagged_items
        FROM audit_logs a
        LEFT JOIN pharmacies p
          ON p.hwid = a.hwid
          OR (a.license_number IS NOT NULL AND p.license_number = a.license_number)
        WHERE a.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY 1,2,3,4
      ),
      scored AS (
        SELECT
          ROW_NUMBER() OVER (ORDER BY
            CASE
              WHEN COALESCE(outgoing_units, 0) = 0 THEN COALESCE(incoming_units, 0)
              ELSE COALESCE(incoming_units, 0)::numeric / NULLIF(outgoing_units, 0)
            END DESC,
            COALESCE(incoming_units, 0) DESC
          )::int AS id,
          pharmacy_name,
          license_number,
          hwid,
          region,
          COALESCE(incoming_units, 0)::int AS incoming_units,
          COALESCE(outgoing_units, 0)::int AS outgoing_units,
          ROUND(
            CASE
              WHEN COALESCE(outgoing_units, 0) = 0 THEN COALESCE(incoming_units, 0)
              ELSE COALESCE(incoming_units, 0)::numeric / NULLIF(outgoing_units, 0)
            END,
            2
          ) AS ratio,
          LEAST(
            100,
            GREATEST(
              0,
              ROUND(
                CASE
                  WHEN COALESCE(outgoing_units, 0) = 0 THEN COALESCE(incoming_units, 0)
                  ELSE (COALESCE(incoming_units, 0)::numeric / NULLIF(outgoing_units, 0)) * 25
                END
              )
            )
          )::int AS score,
          CASE
            WHEN COALESCE(outgoing_units, 0) = 0 AND COALESCE(incoming_units, 0) >= 30 THEN 'critical'
            WHEN COALESCE(outgoing_units, 0) > 0 AND (COALESCE(incoming_units, 0)::numeric / NULLIF(outgoing_units, 0)) >= 3 THEN 'critical'
            WHEN COALESCE(outgoing_units, 0) > 0 AND (COALESCE(incoming_units, 0)::numeric / NULLIF(outgoing_units, 0)) >= 1.8 THEN 'suspicious'
            WHEN COALESCE(incoming_units, 0) >= 20 THEN 'watch'
            ELSE 'watch'
          END AS flag,
          COALESCE(flagged_items, ARRAY[]::text[]) AS flagged_items
        FROM flow
      )
      SELECT *
      FROM scored
      WHERE pharmacy_name IS NOT NULL
      ORDER BY score DESC, pharmacy_name ASC
      LIMIT 200
    `);
    res.json({
      status: 'success',
      data: r.rows,
      pagination: {
        page: 1,
        pageSize: r.rows.length,
        total: r.rows.length,
        totalPages: 1,
      },
      meta: listMeta({
        count: r.rows.length,
        sort: { by: 'score,pharmacy_name', dir: 'desc,asc' },
      }),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

router.get('/hoarding-anomalies/:id/trend', async (req, res) => {
  try {
    const selected = await db.query(
      `WITH flow AS (
         SELECT
           COALESCE(a.pharmacy_name, p.name) AS pharmacy_name,
           COALESCE(a.license_number, p.license_number) AS license_number,
           SUM(CASE WHEN a.event_type IN ('receipt', 'stock_adjust') AND COALESCE(a.unit_count, 0) > 0 THEN a.unit_count ELSE 0 END) AS incoming_units,
           SUM(CASE WHEN a.event_type = 'sale' AND COALESCE(a.unit_count, 0) > 0 THEN a.unit_count ELSE 0 END) AS outgoing_units
         FROM audit_logs a
         LEFT JOIN pharmacies p
           ON p.hwid = a.hwid
           OR (a.license_number IS NOT NULL AND p.license_number = a.license_number)
         WHERE a.created_at >= NOW() - INTERVAL '30 days'
         GROUP BY 1,2
       ),
       scored AS (
         SELECT
           ROW_NUMBER() OVER (ORDER BY
             CASE
               WHEN COALESCE(outgoing_units, 0) = 0 THEN COALESCE(incoming_units, 0)
               ELSE COALESCE(incoming_units, 0)::numeric / NULLIF(outgoing_units, 0)
             END DESC,
             COALESCE(incoming_units, 0) DESC
           )::int AS id,
           pharmacy_name,
           license_number
         FROM flow
       )
       SELECT pharmacy_name, license_number
       FROM scored
       WHERE id = $1
       LIMIT 1`,
      [req.params.id]
    );
    if (!selected.rows.length) return res.status(404).json({ error: 'Not found' });
    const { pharmacy_name, license_number } = selected.rows[0];

    const trend = await db.query(
      `WITH weeks AS (
         SELECT generate_series(
           date_trunc('week', NOW()) - INTERVAL '7 weeks',
           date_trunc('week', NOW()),
           INTERVAL '1 week'
         ) AS wk
       )
       SELECT
         to_char(w.wk, '"Wk" IW') AS week,
         COALESCE(SUM(CASE WHEN a.event_type IN ('receipt', 'stock_adjust') AND COALESCE(a.unit_count, 0) > 0 THEN a.unit_count ELSE 0 END), 0)::INT AS incoming,
         COALESCE(SUM(CASE WHEN a.event_type='sale' AND COALESCE(a.unit_count, 0) > 0 THEN a.unit_count ELSE 0 END), 0)::INT AS outgoing
       FROM weeks w
       LEFT JOIN audit_logs a
         ON date_trunc('week', a.created_at) = w.wk
        AND a.pharmacy_name = $1
        AND a.license_number = $2
       GROUP BY w.wk
       ORDER BY w.wk`,
      [pharmacy_name, license_number]
    );

    res.json({
      status: 'success',
      data: trend.rows,
      pagination: {
        page: 1,
        pageSize: trend.rows.length,
        total: trend.rows.length,
        totalPages: 1,
      },
      meta: listMeta({
        count: trend.rows.length,
        filters: {
          pharmacy_name,
          license_number,
        },
        sort: { by: 'week', dir: 'asc' },
      }),
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.post('/hoarding-anomalies/:id/dismiss', async (req, res) => {
  try {
    await db.query('UPDATE hoarding_alerts SET dismissed=true WHERE id=$1', [req.params.id]);
    res.json({ status: 'success' });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Shortage Surveillance ─────────────────────────────────────────────────────
router.get('/shortage', async (req, res) => {
  try {
    const r = await db.query(
      `SELECT
         ns.id,
         ns.barcode,
         ns.medication_name,
         ns.category,
         ns.stock_units,
         ns.threshold,
         ns.status,
         ns.region,
         ns.last_sync,
         COALESCE(ns.pharmacy_name, p.name, 'Unknown Pharmacy') AS pharmacy_name,
         COALESCE(ns.license_number, p.license_number, 'N/A') AS license_number
       FROM national_stock ns
       LEFT JOIN pharmacies p
         ON (ns.license_number IS NOT NULL AND p.license_number = ns.license_number)
         OR (ns.license_number IS NULL AND ns.hwid IS NOT NULL AND p.hwid = ns.hwid)
       ORDER BY
         CASE ns.status
           WHEN 'critical' THEN 1
           WHEN 'low' THEN 2
           ELSE 3
         END,
         ns.medication_name ASC,
         ns.barcode ASC,
         ns.id ASC`
    );
    res.json({
      status: 'success',
      data: r.rows,
      pagination: {
        page: 1,
        pageSize: r.rows.length,
        total: r.rows.length,
        totalPages: 1,
      },
      meta: listMeta({
        count: r.rows.length,
        sort: { by: 'status,medication_name,barcode,id', dir: 'asc' },
      }),
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Sales Log ─────────────────────────────────────────────────────────────────
router.get('/sales', async (req, res) => {
  try {
    const r = await db.query(
      `SELECT s.*, p.name AS pharmacy_name FROM sales_log s
       LEFT JOIN pharmacies p ON s.pharmacy_id=p.id ORDER BY s.created_at DESC`
    );
    res.json({ status: 'success', data: r.rows });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Chain of Custody ──────────────────────────────────────────────────────────
router.get('/chain-of-custody/:barcode', async (req, res) => {
  try {
    const r = await db.query('SELECT * FROM moph_registry WHERE barcode=$1', [req.params.barcode]);
    if (!r.rows.length) return res.status(404).json({ status: 'not_found' });
    const row = r.rows[0];
    res.json({
      status: 'success',
      data: {
        ...row,
        medication_name: row.trade_name,
        name: row.trade_name,
        updated_at: toIsoString(row.updated_at),
        created_at: toIsoString(row.created_at),
      },
      meta: {
        generated_at: new Date().toISOString(),
      },
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ── Admin: Clear Demo Data (Safe & Selective) ───────────────────────────────
router.post('/admin/clear-demo-data', async (req, res) => {
  const { confirm } = req.body || {};
  if (confirm !== true) {
    return res.status(400).json({
      error: 'Explicit confirmation required. Send {"confirm": true}.',
    });
  }

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');

    // Identify likely demo/test entities by explicit naming patterns only.
    const demoPharmacyRows = await client.query(
      `SELECT id
       FROM pharmacies
       WHERE name ILIKE 'demo %'
          OR name ILIKE '% test %'
          OR license_number ILIKE 'DEMO-%'
          OR hwid ILIKE 'HW-DEMO-%'`
    );
    const demoPharmacyIds = demoPharmacyRows.rows.map((r) => r.id);

    let deletedSales = 0;
    if (demoPharmacyIds.length > 0) {
      const salesByPharmacy = await client.query(
        `DELETE FROM sales_log WHERE pharmacy_id = ANY($1::int[])`,
        [demoPharmacyIds]
      );
      deletedSales += salesByPharmacy.rowCount;
    }

    const salesByReceipt = await client.query(
      `DELETE FROM sales_log
       WHERE receipt_id ILIKE 'DEMO-%'
          OR receipt_id ILIKE 'TEST-%'`
    );
    deletedSales += salesByReceipt.rowCount;

    const deletedAudit = await client.query(
      `DELETE FROM audit_logs
       WHERE event_id ILIKE 'DEMO-%'
          OR pharmacy_name ILIKE 'demo %'
          OR pharmacy_name ILIKE '% test %'
          OR (metadata->>'source') IN ('demo_seed', 'test_seed')`
    );

    const deletedHoarding = await client.query(
      `DELETE FROM hoarding_alerts
       WHERE pharmacy_name ILIKE 'demo %'
          OR pharmacy_name ILIKE '% test %'`
    );

    const deletedRequests = await client.query(
      `DELETE FROM registration_requests
       WHERE reg_id ILIKE 'DEMO-%'
          OR name ILIKE 'demo %'
          OR owner ILIKE 'demo %'`
    );

    const deletedAdmins = await client.query(
      `DELETE FROM admin_users
       WHERE email ILIKE '%@demo.local'
          OR name ILIKE 'demo %'`
    );

    const deletedDistributors = await client.query(
      `DELETE FROM distributors
       WHERE dist_id ILIKE 'DEMO-%'
          OR iqr ILIKE 'DEMO-%'
          OR name ILIKE 'demo %'`
    );

    const deletedRegistry = await client.query(
      `DELETE FROM moph_registry
       WHERE reg_number ILIKE 'DEMO-%'
          OR trade_name ILIKE 'demo %'
       RETURNING barcode`
    );
    const deletedBarcodes = deletedRegistry.rows.map((r) => r.barcode).filter(Boolean);

    let deletedStock = 0;
    if (deletedBarcodes.length > 0) {
      const stockResult = await client.query(
        `DELETE FROM national_stock WHERE barcode = ANY($1::text[])`,
        [deletedBarcodes]
      );
      deletedStock = stockResult.rowCount;
    }

    if (demoPharmacyIds.length > 0) {
      await client.query(
        `DELETE FROM pos_sync_state WHERE pharmacy_id = ANY($1::int[])`,
        [demoPharmacyIds]
      );
      await client.query(
        `DELETE FROM pharmacies WHERE id = ANY($1::int[])`,
        [demoPharmacyIds]
      );
    }

    await client.query('COMMIT');
    res.json({
      status: 'success',
      message: 'Selective demo/test cleanup completed.',
      deleted: {
        pharmacies: demoPharmacyIds.length,
        sales_log: deletedSales,
        audit_logs: deletedAudit.rowCount,
        hoarding_alerts: deletedHoarding.rowCount,
        registration_requests: deletedRequests.rowCount,
        admin_users: deletedAdmins.rowCount,
        distributors: deletedDistributors.rowCount,
        moph_registry: deletedRegistry.rowCount,
        national_stock: deletedStock,
      },
    });
  } catch (e) {
    await client.query('ROLLBACK');
    res.status(500).json({ error: e.message });
  } finally {
    client.release();
  }
});

// ── Admin: Backfill Price Violations from POS Sales Logs ───────────────────
router.post('/admin/backfill-price-violations', async (req, res) => {
  const days = Math.max(1, Math.min(365, Number(req.body?.days) || 30));

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');

    const candidates = await client.query(
      `WITH normalized_sales AS (
         SELECT
           s.id,
           s.receipt_id,
           s.created_at,
           s.pharmacy_id,
           CASE
             WHEN jsonb_typeof(s.sale_data) = 'object' THEN s.sale_data
             WHEN jsonb_typeof(s.sale_data) = 'string' THEN
               CASE
                 WHEN (s.sale_data #>> '{}') LIKE '{%' THEN ((s.sale_data #>> '{}')::jsonb)
                 ELSE '{}'::jsonb
               END
             ELSE '{}'::jsonb
           END AS sale_payload
         FROM sales_log s
         WHERE s.created_at >= NOW() - ($1::text || ' days')::interval
       ), sale_items AS (
         SELECT
           s.id AS sales_id,
           s.receipt_id,
           s.created_at,
           p.name AS pharmacy_name,
           p.hwid,
           p.license_number,
           p.region,
           item.value AS item_json
         FROM normalized_sales s
         LEFT JOIN pharmacies p ON p.id = s.pharmacy_id
         CROSS JOIN LATERAL jsonb_array_elements(
           CASE
             WHEN jsonb_typeof(s.sale_payload->'items') = 'array' THEN s.sale_payload->'items'
             ELSE '[]'::jsonb
           END
         ) AS item(value)
       ), parsed AS (
         SELECT
           sales_id,
           receipt_id,
           created_at,
           pharmacy_name,
           hwid,
           license_number,
           region,
           COALESCE(NULLIF(item_json->>'barcode', ''), '') AS barcode,
           COALESCE(NULLIF(item_json->>'name', ''), NULLIF(item_json->>'product', ''), 'Unknown Item') AS item_name,
           COALESCE((item_json->>'qty')::numeric, (item_json->>'quantity')::numeric, 0) AS unit_count,
           COALESCE((item_json->>'price')::numeric, (item_json->>'unit_price')::numeric, 0) AS charged_price,
           COALESCE((item_json->>'moph_ceiling')::numeric, (item_json->>'registry_price')::numeric) AS fallback_registry_price
         FROM sale_items
       ), enriched AS (
         SELECT
           p.*,
           COALESCE(m.moph_ceiling, p.fallback_registry_price) AS registry_price
         FROM parsed p
         LEFT JOIN moph_registry m ON m.barcode = p.barcode
       )
       SELECT *
       FROM enriched e
       WHERE e.barcode <> ''
         AND e.unit_count > 0
         AND e.registry_price IS NOT NULL
         AND e.charged_price > e.registry_price
         AND NOT EXISTS (
           SELECT 1
           FROM audit_logs a
           WHERE a.event_type = 'price_hike'
             AND a.metadata->>'receipt_id' = e.receipt_id
             AND a.metadata->>'barcode' = e.barcode
         )`,
      [String(days)]
    );

    let inserted = 0;
    for (const row of candidates.rows) {
      const eventId = uid('EVT');
      const result = await client.query(
        `INSERT INTO audit_logs (event_id, pharmacy_name, hwid, license_number, region, event_type, item_name, registry_price, charged_price, unit_count, metadata, created_at)
         VALUES ($1, $2, $3, $4, $5, 'price_hike', $6, $7, $8, $9, $10::jsonb, $11)`,
        [
          eventId,
          row.pharmacy_name || null,
          row.hwid || null,
          row.license_number || null,
          row.region || null,
          row.item_name,
          row.registry_price,
          row.charged_price,
          Math.round(Number(row.unit_count || 0)),
          JSON.stringify({
            source: 'sales_log_backfill',
            receipt_id: row.receipt_id,
            barcode: row.barcode,
          }),
          row.created_at,
        ]
      );
      inserted += result.rowCount;
    }

    await client.query('COMMIT');
    res.json({ status: 'success', inserted, scanned: candidates.rows.length, days });
  } catch (e) {
    await client.query('ROLLBACK');
    res.status(500).json({ error: e.message });
  } finally {
    client.release();
  }
});

// ── Data Provenance (POS vs Manual/Admin) ───────────────────────────────────
router.get('/data-provenance', async (req, res) => {
  try {
    const [
      sales,
      audits,
      syncState,
      changes,
      suspicious,
    ] = await Promise.all([
      db.query(`SELECT COUNT(*)::int AS total FROM sales_log`),
      db.query(
        `SELECT
           COUNT(*)::int AS total,
           COUNT(*) FILTER (WHERE event_type IN ('sale', 'price_hike'))::int AS pos_derived,
           COUNT(*) FILTER (WHERE event_type = 'stock_adjust')::int AS manual_adjustments,
           COUNT(*) FILTER (WHERE event_type IN ('inspection', 'violation'))::int AS governance_actions
         FROM audit_logs`
      ),
      db.query(
        `SELECT
           MAX(last_sync_up) AS last_sync_up,
           COUNT(*) FILTER (WHERE last_sync_up IS NOT NULL)::int AS synced_nodes,
           COUNT(*)::int AS total_nodes
         FROM pos_sync_state`
      ),
      db.query(
        `SELECT
           COUNT(*)::int AS total,
           COUNT(*) FILTER (WHERE synced_to_pos = true)::int AS synced_to_pos
         FROM change_log`
      ),
      db.query(
        `SELECT
           (SELECT COUNT(*)::int FROM pharmacies
             WHERE name ILIKE 'demo %' OR license_number ILIKE 'DEMO-%' OR hwid ILIKE 'HW-DEMO-%') AS demo_pharmacies,
           (SELECT COUNT(*)::int FROM sales_log
             WHERE receipt_id ILIKE 'DEMO-%' OR receipt_id ILIKE 'TEST-%') AS demo_sales,
           (SELECT COUNT(*)::int FROM audit_logs
             WHERE event_id ILIKE 'DEMO-%' OR (metadata->>'source') IN ('demo_seed', 'test_seed')) AS demo_audits`
      )
    ]);

    const salesTotal = sales.rows[0]?.total || 0;
    const auditStats = audits.rows[0] || {};
    const syncStats = syncState.rows[0] || {};
    const changeStats = changes.rows[0] || {};
    const suspiciousStats = suspicious.rows[0] || {};

    res.json({
      status: 'success',
      data: {
        sales_log: {
          total: salesTotal,
          source: 'pos_sync_up',
        },
        audit_logs: {
          total: Number(auditStats.total || 0),
          pos_derived: Number(auditStats.pos_derived || 0),
          manual_adjustments: Number(auditStats.manual_adjustments || 0),
          governance_actions: Number(auditStats.governance_actions || 0),
        },
        pos_sync: {
          last_sync_up: syncStats.last_sync_up || null,
          synced_nodes: Number(syncStats.synced_nodes || 0),
          total_nodes: Number(syncStats.total_nodes || 0),
        },
        change_log: {
          total: Number(changeStats.total || 0),
          synced_to_pos: Number(changeStats.synced_to_pos || 0),
        },
        suspicious_demo_markers: {
          pharmacies: Number(suspiciousStats.demo_pharmacies || 0),
          sales: Number(suspiciousStats.demo_sales || 0),
          audits: Number(suspiciousStats.demo_audits || 0),
        },
      },
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Settings Data (DB-backed) ────────────────────────────────────────────────
// Settings data now returns only common POS↔Web data
router.get('/settings-data', async (req, res) => {
  try {
    const [
      terminals,
      terminalSummary,
      pricingPolicy,
      recentPriceEvents,
      adjustmentReasons,
      recentAdjustments,
      adjustmentSummary,
      topAdjustmentReasons,
    ] = await Promise.all([
      db.query(
        `SELECT
           p.id,
           p.name,
           p.hwid,
           p.license_number,
           p.region,
           p.status,
           p.sync_version,
           p.sync_pct,
           p.last_seen,
           p.latency_ms,
           s.last_sync_up,
           s.last_sync_down,
           (SELECT COUNT(*)::int FROM sync_outbox o WHERE o.device_id = p.hwid AND o.sync_status = 'pending') AS pending_outbox,
           (SELECT COUNT(*)::int FROM compliance_alerts c WHERE c.pharmacy_id = p.id AND c.status = 'open') AS open_compliance_alerts,
           (SELECT r.status FROM registration_requests r WHERE LOWER(r.name) = LOWER(p.name) ORDER BY r.id DESC LIMIT 1) AS registration_status
         FROM pharmacies p
         LEFT JOIN pos_sync_state s ON s.pharmacy_id = p.id
         ORDER BY p.name ASC, p.id ASC`
      ),
      db.query(
        `SELECT
           COUNT(*)::int AS total_terminals,
           COUNT(*) FILTER (WHERE status = 'online')::int AS online_count,
           COUNT(*) FILTER (WHERE status = 'offline')::int AS offline_count,
           COUNT(*) FILTER (WHERE status = 'degraded')::int AS degraded_count,
           COUNT(*) FILTER (WHERE sync_version IS NULL OR sync_version = '')::int AS unknown_version_count,
           COUNT(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM pos_sync_state s WHERE s.pharmacy_id = pharmacies.id))::int AS never_seen_count
         FROM pharmacies`
      ),
      db.query(
        `SELECT
           COUNT(*) FILTER (WHERE moph_ceiling IS NOT NULL)::int AS regulated_medicine_count,
           (SELECT COUNT(*)::int FROM compliance_alerts WHERE status = 'open' AND alert_type = 'high_price') AS high_price_violations,
           (SELECT MAX(created_at) FROM change_log WHERE change_type = 'price_update') AS last_registry_sync,
           (SELECT MAX(created_at) FROM audit_logs WHERE event_type = 'price_hike') AS last_price_event_at
         FROM moph_registry`
      ),
      db.query(
        `SELECT
           item_name,
           COALESCE(metadata->>'barcode', '') AS barcode,
           pharmacy_name,
           license_number,
           registry_price,
           charged_price,
           event_type,
           CASE
             WHEN charged_price > registry_price THEN 'violation'
             ELSE 'ok'
           END AS status,
           created_at
         FROM audit_logs
         WHERE event_type = 'price_hike'
           AND registry_price IS NOT NULL
           AND charged_price IS NOT NULL
         ORDER BY created_at DESC
         LIMIT 10`
      ),
      db.query('SELECT reason FROM adjustment_reasons ORDER BY id ASC'),
      db.query(
        `SELECT
           pharmacy_name,
           item_name,
           unit_count,
           COALESCE(metadata->>'reason', 'Manual adjustment') AS reason,
           COALESCE(metadata->>'source', 'manual_adjustment') AS source,
           created_at
         FROM audit_logs
         WHERE event_type = 'stock_adjust'
         ORDER BY created_at DESC
         LIMIT 10`
      ),
      db.query(
        `SELECT
           COUNT(*)::int AS total_adjustments,
           COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days')::int AS adjustments_last_30d,
           MAX(created_at) AS last_adjustment_at
         FROM audit_logs
         WHERE event_type = 'stock_adjust'`
      ),
      db.query(
        `SELECT
           COALESCE(NULLIF(metadata->>'reason', ''), 'Unspecified') AS reason,
           COUNT(*)::int AS usage_count
         FROM audit_logs
         WHERE event_type = 'stock_adjust'
         GROUP BY COALESCE(NULLIF(metadata->>'reason', ''), 'Unspecified')
         ORDER BY usage_count DESC, reason ASC
         LIMIT 5`
      ),
    ]);

    const normalizedTerminals = terminals.rows.map((node) => ({
      ...node,
      last_seen: toIsoString(node.last_seen),
      last_sync_up: toIsoString(node.last_sync_up),
      last_sync_down: toIsoString(node.last_sync_down),
    }));

    const knownVersions = normalizedTerminals
      .map((row) => row.sync_version)
      .filter((value) => typeof value === 'string' && value.trim().length > 0);
    const expectedSyncVersion = knownVersions.sort().at(-1) || null;

    const versionMismatchCount = expectedSyncVersion
      ? normalizedTerminals.filter((row) => row.sync_version && row.sync_version !== expectedSyncVersion).length
      : 0;

    const neverSyncedCount = normalizedTerminals.filter((row) => !row.last_sync_up && !row.last_sync_down).length;

    const normalizedPriceEvents = recentPriceEvents.rows.map((row) => ({
      ...row,
      created_at: toIsoString(row.created_at),
    }));

    const normalizedRecentAdjustments = recentAdjustments.rows.map((row) => ({
      ...row,
      created_at: toIsoString(row.created_at),
    }));

    const pricingPolicyRow = pricingPolicy.rows[0] || {};
    const adjustmentSummaryRow = adjustmentSummary.rows[0] || {};
    const terminalSummaryRow = terminalSummary.rows[0] || {};

    res.json({
      status: 'success',
      data: {
        terminals: normalizedTerminals,
        terminal_summary: {
          ...terminalSummaryRow,
          version_mismatch_count: toInt(versionMismatchCount, 0),
          never_synced_count: toInt(neverSyncedCount, 0),
          expected_sync_version: expectedSyncVersion,
        },
        pricing_policy: {
          regulated_medicine_count: toInt(pricingPolicyRow.regulated_medicine_count, 0),
          high_price_violations: toInt(pricingPolicyRow.high_price_violations, 0),
          last_registry_sync: toIsoString(pricingPolicyRow.last_registry_sync),
          last_price_event_at: toIsoString(pricingPolicyRow.last_price_event_at),
        },
        recent_price_events: normalizedPriceEvents,
        adjustment_reasons: adjustmentReasons.rows.map((r) => r.reason),
        recent_adjustments: normalizedRecentAdjustments,
        adjustment_summary: {
          total_adjustments: toInt(adjustmentSummaryRow.total_adjustments, 0),
          adjustments_last_30d: toInt(adjustmentSummaryRow.adjustments_last_30d, 0),
          last_adjustment_at: toIsoString(adjustmentSummaryRow.last_adjustment_at),
        },
        top_adjustment_reasons: topAdjustmentReasons.rows,
      },
      pagination: {
        page: 1,
        pageSize: normalizedTerminals.length,
        total: normalizedTerminals.length,
        totalPages: 1,
      },
      meta: {
        generated_at: new Date().toISOString(),
      },
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Sync Pricing Updates to POS ─────────────────────────────────────────────
router.post('/sync-pricing-to-pos', async (req, res) => {
  const { pharmacy_id } = req.body;
  try {
    const r = await db.query(
      `SELECT id, barcode, trade_name, dosage, moph_ceiling
       FROM moph_registry WHERE moph_ceiling IS NOT NULL
       ORDER BY updated_at DESC LIMIT 20`
    );
    
    // Create audit log entry as notification to POS
    await db.query(
      `INSERT INTO audit_logs (event_id, event_type, metadata)
       VALUES ($1, $2, $3::jsonb)`,
      [uid('SYNC'), 'pricing_sync_from_web', JSON.stringify({
        pharmacy_id,
        pricing_count: r.rows.length,
        timestamp: new Date().toISOString()
      })]
    );

    res.json({ status: 'success', synced_count: r.rows.length, data: r.rows });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Sync Stock Status to POS ────────────────────────────────────────────────
router.post('/sync-stock-to-pos', async (req, res) => {
  const { pharmacy_id } = req.body;
  try {
    const r = await db.query(
      `SELECT barcode, medication_name, stock_units, status, threshold
       FROM national_stock ORDER BY status DESC`
    );

    // Create audit log entry as notification to POS
    await db.query(
      `INSERT INTO audit_logs (event_id, event_type, metadata)
       VALUES ($1, $2, $3::jsonb)`,
      [uid('SYNC'), 'stock_sync_from_web', JSON.stringify({
        pharmacy_id,
        stock_count: r.rows.length,
        timestamp: new Date().toISOString()
      })]
    );

    res.json({ status: 'success', synced_count: r.rows.length, data: r.rows });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
