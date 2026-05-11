const express = require('express');
const crypto = require('crypto');
const router = express.Router();
const db = require('../db');

// --- Helper ─────────────────────────────────────────────────────────────────
const uid = (prefix) => `${prefix}-${Date.now().toString().slice(-6)}`;
const normalized = (v) => String(v || '').trim();
const normalizedLower = (v) => normalized(v).toLowerCase();
const toMinor = (v) => Math.round((Number(v) || 0) * 100);
const DEFAULT_SYNC_PROTOCOL_VERSION = '2026-04-07';


function readSyncProtocolVersion(req) {
  return normalized(
    req.body?.sync_protocol_version
    || req.query?.sync_protocol_version
    || req.header('x-sync-protocol-version')
    || DEFAULT_SYNC_PROTOCOL_VERSION
  );
}

function markLegacySyncAdapter(res, canonicalPath) {
  res.setHeader('x-sync-contract', 'legacy-adapter');
  res.setHeader('x-sync-canonical-endpoint', canonicalPath);
}


function stableUuid(seed) {
  const hash = crypto.createHash('sha1').update(String(seed)).digest('hex').slice(0, 32);
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-${hash.slice(12, 16)}-${hash.slice(16, 20)}-${hash.slice(20, 32)}`;
}

function stockStatus(stockUnits, threshold) {
  const safeThreshold = Number.isFinite(threshold) && threshold > 0 ? threshold : 1000;
  const safeStock = Number.isFinite(stockUnits) ? stockUnits : 0;
  if (safeStock < safeThreshold * 0.25) return 'critical';
  if (safeStock < safeThreshold) return 'low';
  return 'safe';
}

function parseJsonSafely(value, fallback = {}) {
  if (typeof value === 'string') {
    try {
      return JSON.parse(value || '{}');
    } catch {
      return fallback;
    }
  }
  if (value && typeof value === 'object') return value;
  return fallback;
}

function asUtcDateFromEpochMs(value, fallback = new Date()) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return new Date(n);
}

function isStockMovementType(movementType) {
  return new Set([
    'sale',
    'purchase',
    'return_in',
    'return_out',
    'adjustment',
    'loss',
    'damaged',
    'correction',
  ]).has(movementType);
}

function normalizeMovement(rawMovement, fallbackDeviceId, fallbackPharmacyId) {
  const movement = rawMovement || {};
  const movementUuid = normalized(movement.movement_uuid);
  const barcode = normalized(movement.barcode);
  const movementType = normalizedLower(movement.movement_type || 'adjustment');
  const parsedQuantity = Number(movement.quantity_delta);
  const quantityDelta = Number.isFinite(parsedQuantity) ? Math.trunc(parsedQuantity) : 0;
  const unitPriceMinor = Number.isFinite(Number(movement.unit_price_minor))
    ? Math.trunc(Number(movement.unit_price_minor))
    : null;
  const happenedAt = asUtcDateFromEpochMs(movement.happened_at);
  const updatedAt = asUtcDateFromEpochMs(movement.updated_at, happenedAt);
  const deletedAt = Number.isFinite(Number(movement.deleted_at))
    ? asUtcDateFromEpochMs(movement.deleted_at, null)
    : null;

  return {
    movementUuid,
    pharmacyId: Number(movement.pharmacy_id) > 0 ? Number(movement.pharmacy_id) : fallbackPharmacyId,
    deviceId: normalized(movement.device_id) || fallbackDeviceId,
    version: Number.isFinite(Number(movement.version)) ? Math.max(1, Math.trunc(Number(movement.version))) : 1,
    barcode,
    movementType,
    quantityDelta,
    unitPriceMinor,
    currencyCode: normalized(movement.currency_code || 'USD') || 'USD',
    referenceType: normalized(movement.reference_type),
    referenceId: normalized(movement.reference_id),
    metadata: parseJsonSafely(movement.metadata, {}),
    happenedAt,
    updatedAt,
    deletedAt,
    syncStatus: normalized(movement.sync_status || 'synced') || 'synced',
  };
}

async function resolvePharmacy(client, payload) {
  const requestedPharmacyId = Number(payload.pharmacy_id);
  const hwid = normalized(payload.hwid);
  const branchName = normalized(payload.branch_name);
  const licenseNumber = normalized(payload.license_number);
  const region = normalized(payload.region);

  const hasIdentifier =
    (Number.isFinite(requestedPharmacyId) && requestedPharmacyId > 0) ||
    !!hwid ||
    !!licenseNumber;
  if (!hasIdentifier) {
    return { error: 'Missing pharmacy identifier: provide pharmacy_id, hwid, or license_number.' };
  }

  let pharmacy = null;
  if (Number.isFinite(requestedPharmacyId) && requestedPharmacyId > 0) {
    const byId = await client.query(
      'SELECT * FROM pharmacies WHERE id = $1 LIMIT 1',
      [requestedPharmacyId]
    );
    pharmacy = byId.rows[0] || null;
    if (pharmacy && hwid && pharmacy.hwid && normalizedLower(pharmacy.hwid) !== normalizedLower(hwid)) {
      return {
        error: `Provided hwid ${hwid} does not match pharmacy_id ${requestedPharmacyId}.`,
      };
    }
  }

  if (!pharmacy && hwid) {
    const byHwid = await client.query('SELECT * FROM pharmacies WHERE hwid = $1 LIMIT 1', [hwid]);
    pharmacy = byHwid.rows[0] || null;
  }

  if (!pharmacy && licenseNumber) {
    const byLicense = await client.query(
      'SELECT * FROM pharmacies WHERE license_number = $1 LIMIT 1',
      [licenseNumber]
    );
    pharmacy = byLicense.rows[0] || null;
  }

  if (!pharmacy) {
    if (!branchName || !licenseNumber) {
      return { error: 'Cannot create pharmacy: branch_name and license_number are required for new pharmacies.' };
    }
    const inserted = await client.query(
      `INSERT INTO pharmacies (name, license_number, hwid, region, status, last_seen)
       VALUES ($1, $2, NULLIF($3, ''), $4, 'online', 'just now')
       RETURNING *`,
      [branchName, licenseNumber, hwid, region || '']
    );
    pharmacy = inserted.rows[0];
  } else {
    const updated = await client.query(
      `UPDATE pharmacies
       SET
         name = COALESCE(NULLIF($1, ''), name),
         hwid = COALESCE(NULLIF($2, ''), hwid),
         region = COALESCE(NULLIF($3, ''), region),
         status = 'online',
         last_seen = 'just now'
       WHERE id = $4
       RETURNING *`,
      [branchName, hwid, region, pharmacy.id]
    );
    pharmacy = updated.rows[0] || pharmacy;
  }

  return { pharmacy };
}

// --- Sync Down (MoPH Data to POS) ---

// Get the latest registry to overwrite / update the POS SQLite db (optimized)
router.get('/sync-down', async (req, res) => {
  markLegacySyncAdapter(res, '/api/sync/pull');
  try {
    const hwid = normalized(req.query.hwid || req.query.device_id);
    const pharmacyId = Number(req.query.pharmacy_id);
    const sinceRaw = normalized(req.query.since_checkpoint);
    const since = sinceRaw ? new Date(sinceRaw) : new Date(0);
    const sinceTs = Number.isNaN(since.getTime()) ? new Date(0) : since;

    // Only send fields POS needs, indexed query
    const medicines = await db.query(`
      SELECT id, barcode, reg_number, trade_name, generic_name, dosage, form, manufacturer, category, moph_ceiling, is_blocked, updated_at
      FROM moph_registry
      ORDER BY id ASC
    `);

    const serverChanges = await db.query(
      `SELECT id, change_type, entity_id, entity_type, old_value, new_value, created_at
       FROM change_log
       WHERE created_at > $1
       ORDER BY created_at ASC
       LIMIT 1000`,
      [sinceTs]
    );

    const complianceAlerts = await db.query(
      `SELECT alert_uuid, alert_type, severity, title, details, status, created_at
       FROM compliance_alerts
       WHERE status = 'open'
         AND (
           pharmacy_id IS NULL
           OR pharmacy_id = $1
         )
       ORDER BY created_at DESC
       LIMIT 300`,
      [Number.isFinite(pharmacyId) && pharmacyId > 0 ? pharmacyId : null]
    );

    const now = new Date().toISOString();

    if (hwid) {
      await db.query(
        `INSERT INTO sync_outbox (event_uuid, pharmacy_id, device_id, direction, stream, payload, sync_status, created_at, updated_at)
         VALUES ($1::uuid, $2, $3, 'server_to_pos', 'sync_down_payload', $4::jsonb, 'sent', NOW(), NOW())`,
        [
          stableUuid(`sync-down:${hwid}:${now}`),
          Number.isFinite(pharmacyId) && pharmacyId > 0 ? pharmacyId : null,
          hwid,
          JSON.stringify({ checkpoint: now, changes: serverChanges.rows.length, medicines: medicines.rows.length }),
        ]
      ).catch(() => {});
    }

    res.json({
      status: 'success',
      sync_protocol_version: readSyncProtocolVersion(req),
      count: medicines.rows.length,
      data: medicines.rows,
      medicines: medicines.rows,
      regulated_prices: medicines.rows.map((m) => ({
        barcode: m.barcode,
        regulated_price_minor: m.moph_ceiling == null ? null : toMinor(m.moph_ceiling),
        currency_code: 'USD',
        updated_at: m.updated_at,
      })),
      compliance_alerts: complianceAlerts.rows,
      server_updates: serverChanges.rows,
      server_checkpoint: now,
      timestamp: now,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Failed to sync down' });
  }
});

// Get current stock levels for POS (optimized)
router.get('/stock-status', async (req, res) => {
  try {
    const result = await db.query(`
      SELECT
        barcode,
        MAX(medication_name) AS medication_name,
        MAX(category) AS category,
        SUM(COALESCE(stock_units, 0))::int AS stock_units,
        MAX(COALESCE(threshold, 1000))::int AS threshold,
        CASE
          WHEN BOOL_OR(status = 'critical') THEN 'critical'
          WHEN BOOL_OR(status = 'low') THEN 'low'
          ELSE 'safe'
        END AS status
      FROM national_stock
      GROUP BY barcode
      ORDER BY barcode ASC
    `);
    res.json({
      status: 'success',
      count: result.rows.length,
      data: result.rows
    });
  } catch {
    res.status(500).json({ error: 'Failed to get stock status' });
  }
});

// --- Sync Up (POS Offline Queue to Command Center) ---

router.post('/sync-up', async (req, res) => {
  markLegacySyncAdapter(res, '/api/sync/push');
  const payload = req.body || {};
  const {
    app_version = '',
    sales = [],
    movements = [],
    audits = [],
    stock = [],
    events = [],
    hwid = '',
  } = payload;
  const requestedPharmacyId = Number(payload.pharmacy_id);
  const normalizedHwid = normalized(hwid);
  const syncProtocolVersion = readSyncProtocolVersion(req);
  const requestId = normalized(payload.request_id) || stableUuid(`pos-sync-up:${normalizedHwid || requestedPharmacyId || 'unknown'}:${Date.now()}`);

  if ((!Number.isFinite(requestedPharmacyId) || requestedPharmacyId <= 0) && !normalizedHwid) {
    return res.status(400).json({ error: 'pharmacy_id or hwid is required' });
  }

  const client = await db.pool.connect();

  try {
    await client.query('BEGIN');

    const resolved = await resolvePharmacy(client, payload);
    if (resolved.error) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: resolved.error });
    }
    const pharmacy = resolved.pharmacy;
    const effectiveHwid = normalized(pharmacy?.hwid || normalizedHwid);
    const hasMovementPayload = Array.isArray(movements) && movements.length > 0;
    const eventBatch = Array.isArray(events) ? events : [];
    const acceptedEventIds = [];
    const duplicateEventIds = [];
    const syncedMovementUuids = [];
    const registryCache = new Map();

    async function getRegistryRow(barcode) {
      const key = normalized(barcode);
      if (!key) return null;
      if (registryCache.has(key)) return registryCache.get(key);
      const reg = await client.query(
        `SELECT trade_name, dosage, category, moph_ceiling, is_blocked
         FROM moph_registry
         WHERE barcode = $1
         LIMIT 1`,
        [key]
      );
      const row = reg.rows[0] || null;
      registryCache.set(key, row);
      return row;
    }

    // Insert synced sales and derive audit/stock updates from POS line items.
    let insertedSales = 0;
    let derivedAudits = 0;
    let stockUpdatesFromSales = 0;
    for (const sale of sales) {
      const parsedSaleData = parseJsonSafely(sale.sale_data, {});
      const saleData = JSON.stringify(parsedSaleData);

      const saleCreatedAt = Number(sale.created_at);
      const hasPosCreatedAt = Number.isFinite(saleCreatedAt) && saleCreatedAt > 0;

      const insertedSale = await client.query(`
        INSERT INTO sales_log (receipt_id, pharmacy_id, device_id, version, sale_data, sync_status, updated_at, deleted_at, pos_created_at)
        VALUES (
          $1,
          $2,
          $3,
          $4,
          $5::jsonb,
          'synced',
          NOW(),
          NULL,
          CASE WHEN $6::bigint > 0 THEN to_timestamp($6 / 1000.0) ELSE NULL END
        )
        ON CONFLICT (receipt_id) DO NOTHING
      `, [sale.receipt_id, pharmacy.id, effectiveHwid || null, 1, saleData, hasPosCreatedAt ? saleCreatedAt : 0]);

      insertedSales += insertedSale.rowCount;

      const saleUuid = stableUuid(`sale:${pharmacy.id}:${sale.receipt_id}`);
      const saleHeader = await client.query(
        `INSERT INTO sales (
           sale_uuid, pharmacy_id, device_id, receipt_id, sold_at, customer_name, payment_method,
           subtotal_minor, moph_tax_minor, vat_minor, grand_total_minor, currency_code,
           version, sync_status, payload, updated_at, deleted_at
         )
         VALUES (
           $1::uuid, $2, $3, $4,
           CASE WHEN $5::bigint > 0 THEN to_timestamp($5 / 1000.0) ELSE NOW() END,
           $6, $7,
           $8, $9, $10, $11, 'USD',
           1, 'synced', $12::jsonb, NOW(), NULL
         )
         ON CONFLICT (sale_uuid) DO NOTHING
         RETURNING id`,
        [
          saleUuid,
          pharmacy.id,
          effectiveHwid || 'UNKNOWN',
          sale.receipt_id,
          hasPosCreatedAt ? saleCreatedAt : 0,
          parsedSaleData.customer || null,
          parsedSaleData.method || 'CASH',
          toMinor(parsedSaleData.subtotal),
          toMinor(parsedSaleData.moph_tax),
          toMinor(parsedSaleData.vat),
          toMinor(parsedSaleData.grand_total),
          saleData,
        ]
      );

      let saleId = saleHeader.rows[0]?.id;
      if (!saleId) {
        const existingSale = await client.query('SELECT id FROM sales WHERE sale_uuid = $1::uuid LIMIT 1', [saleUuid]);
        saleId = existingSale.rows[0]?.id;
      }

      if (saleId) {
        const saleItems = Array.isArray(parsedSaleData.items) ? parsedSaleData.items : [];
        for (let idx = 0; idx < saleItems.length; idx += 1) {
          const item = saleItems[idx] || {};
          const barcode = normalized(item.barcode);
          const qty = Math.max(0, Number(item.qty ?? item.quantity ?? 0));
          if (!barcode || qty <= 0) continue;

          await client.query(
            `INSERT INTO sale_items (
               sale_id, line_uuid, barcode, product_name, dosage, quantity,
               unit_price_minor, line_total_minor, batch_number, version, updated_at, deleted_at
             )
             VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8, $9, 1, NOW(), NULL)
             ON CONFLICT (line_uuid) DO NOTHING`,
            [
              saleId,
              stableUuid(`sale-item:${sale.receipt_id}:${idx}:${barcode}`),
              barcode,
              item.name || item.product || barcode,
              item.dosage || '',
              Math.trunc(qty),
              toMinor(item.price ?? item.unit_price),
              toMinor(item.total ?? ((item.price ?? item.unit_price ?? 0) * qty)),
              item.batch_number || null,
            ]
          );
        }
      }

      const saleItemsForAudit = Array.isArray(parsedSaleData.items) ? parsedSaleData.items : [];
      for (const item of saleItemsForAudit) {
        const barcode = String(item.barcode || '').trim();
        const qty = Math.max(0, Number(item.qty ?? item.quantity ?? 0));
        const chargedPrice = Number(item.unit_price ?? item.price ?? 0);
        if (!barcode || qty <= 0) continue;

        const regRow = await getRegistryRow(barcode);
        const registryPriceFromMaster = regRow?.moph_ceiling != null ? Number(regRow.moph_ceiling) : null;
        const registryPriceFromPosItem = Number(item.moph_ceiling ?? item.registry_price);
        const hasMasterCeiling = Number.isFinite(registryPriceFromMaster);
        const hasPosCeiling = Number.isFinite(registryPriceFromPosItem);
        const registryPrice = hasMasterCeiling
          ? registryPriceFromMaster
          : (hasPosCeiling ? registryPriceFromPosItem : null);
        const itemName = String(
          item.name ||
          item.product ||
          (regRow ? `${regRow.trade_name} ${regRow.dosage || ''}`.trim() : barcode)
        );
        const eventType = registryPrice != null && Number.isFinite(chargedPrice) && chargedPrice > registryPrice
          ? 'price_hike'
          : 'sale';

        const insertedAudit = await client.query(
          `INSERT INTO audit_logs (event_id, pharmacy_name, hwid, license_number, region, event_type, item_name, registry_price, charged_price, unit_count, metadata)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb)`,
          [
            uid('EVT'),
            pharmacy?.name || null,
            effectiveHwid || null,
            pharmacy?.license_number || null,
            pharmacy?.region || null,
            eventType,
            itemName,
            registryPrice,
            Number.isFinite(chargedPrice) ? chargedPrice : null,
            qty,
            JSON.stringify({
              barcode,
              receipt_id: sale.receipt_id || null,
              ceiling_source: hasMasterCeiling ? 'moph_registry' : (hasPosCeiling ? 'pos_item' : 'missing'),
            })
          ]
        );

        derivedAudits += insertedAudit.rowCount;

        if (!hasMovementPayload) {
          const updatedStock = await client.query(
            `UPDATE national_stock
             SET
               stock_units = GREATEST(0, stock_units - $2),
               status = CASE
                 WHEN GREATEST(0, stock_units - $2) < (threshold * 0.25) THEN 'critical'
                 WHEN GREATEST(0, stock_units - $2) < threshold THEN 'low'
                 ELSE 'safe'
               END,
               last_sync = $3,
               updated_at = NOW()
             WHERE barcode = $1
               AND (
                 (license_number IS NOT NULL AND license_number = $4)
                 OR (license_number IS NULL AND hwid = $5)
               )`,
            [barcode, qty, new Date().toISOString(), pharmacy?.license_number || null, effectiveHwid || null]
          );

          if (updatedStock.rowCount === 0) {
            await client.query(
              `INSERT INTO national_stock (barcode, medication_name, category, pharmacy_name, license_number, hwid, stock_units, threshold, status, region, last_sync, updated_at)
               VALUES ($1, $2, $3, $4, $5, $6, 0, 1000, 'critical', $7, $8, NOW())
               ON CONFLICT (barcode, license_number) DO UPDATE SET
                 medication_name = EXCLUDED.medication_name,
                 category = EXCLUDED.category,
                 pharmacy_name = EXCLUDED.pharmacy_name,
                 hwid = EXCLUDED.hwid,
                 status = 'critical',
                 region = EXCLUDED.region,
                 last_sync = EXCLUDED.last_sync,
                 updated_at = NOW()`,
              [
                barcode,
                itemName,
                regRow?.category || 'Uncategorized',
                pharmacy?.name || null,
                pharmacy?.license_number || null,
                effectiveHwid || null,
                pharmacy?.region || null,
                new Date().toISOString(),
              ]
            );
          }
          stockUpdatesFromSales += 1;
        }
      }
    }

    // Movement-based stock sync (authoritative, idempotent); stock snapshots are ignored.
    let movementUpdates = 0;
    for (const rawMovement of (Array.isArray(movements) ? movements : [])) {
      const movement = normalizeMovement(rawMovement, effectiveHwid, pharmacy.id);
      if (!movement.movementUuid || !movement.barcode) continue;

      const insertedMovement = await client.query(
        `INSERT INTO pos_inventory_movements (
           movement_uuid, pharmacy_id, device_id, version, barcode, movement_type,
           quantity_delta, unit_price_minor, currency_code, reference_type, reference_id,
           metadata, happened_at, updated_at, deleted_at, sync_status
         )
         VALUES (
           $1::uuid, $2, $3, $4, $5, $6,
           $7, $8, $9, $10, $11,
           $12::jsonb, $13, $14, $15, $16
         )
         ON CONFLICT (movement_uuid) DO NOTHING
         RETURNING movement_uuid`,
        [
          movement.movementUuid,
          movement.pharmacyId,
          movement.deviceId,
          movement.version,
          movement.barcode,
          movement.movementType,
          movement.quantityDelta,
          movement.unitPriceMinor,
          movement.currencyCode,
          movement.referenceType,
          movement.referenceId,
          JSON.stringify(movement.metadata || {}),
          movement.happenedAt,
          movement.updatedAt,
          movement.deletedAt,
          movement.syncStatus,
        ]
      );

      if (!insertedMovement.rowCount) {
        syncedMovementUuids.push(movement.movementUuid);
        continue;
      }

      await client.query(
        `INSERT INTO inventory_movements (
           event_uuid, pharmacy_id, device_id, barcode, movement_type, quantity_delta,
           unit_price_minor, currency_code, reference_type, reference_id, metadata,
           happened_at, version, sync_status, updated_at, deleted_at
         )
         VALUES (
           $1::uuid, $2, $3, $4, $5, $6,
           $7, $8, $9, $10, $11::jsonb,
           $12, $13, $14, $15, $16
         )
         ON CONFLICT (event_uuid) DO NOTHING`,
        [
          movement.movementUuid,
          movement.pharmacyId,
          movement.deviceId,
          movement.barcode,
          movement.movementType,
          movement.quantityDelta,
          movement.unitPriceMinor,
          movement.currencyCode,
          movement.referenceType,
          movement.referenceId,
          JSON.stringify(movement.metadata || {}),
          movement.happenedAt,
          movement.version,
          movement.syncStatus,
          movement.updatedAt,
          movement.deletedAt,
        ]
      );

      const regRow = await getRegistryRow(movement.barcode);
      const itemName = regRow
        ? `${regRow.trade_name} ${regRow.dosage || ''}`.trim()
        : movement.barcode;

      if (movement.movementType === 'purchase') {
        const purchaseUuid = stableUuid(`purchase:${pharmacy.id}:${movement.referenceId || movement.movementUuid}`);
        await client.query(
          `INSERT INTO purchases (
             purchase_uuid, pharmacy_id, device_id, receipt_id, supplier_name, invoice_number,
             purchased_at, total_cost_minor, currency_code, version, sync_status, payload, updated_at, deleted_at
           )
           VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, 0, 'USD', $8, 'synced', $9::jsonb, NOW(), NULL)
           ON CONFLICT (purchase_uuid) DO NOTHING`,
          [
            purchaseUuid,
            pharmacy.id,
            effectiveHwid || 'UNKNOWN',
            movement.referenceId || movement.movementUuid,
            movement.metadata.supplier_name || null,
            movement.metadata.invoice_number || null,
            movement.happenedAt,
            movement.version,
            JSON.stringify(movement.metadata || {}),
          ]
        );

        const purchaseIdResult = await client.query('SELECT id FROM purchases WHERE purchase_uuid = $1::uuid LIMIT 1', [purchaseUuid]);
        const purchaseId = purchaseIdResult.rows[0]?.id;
        if (purchaseId) {
          await client.query(
            `INSERT INTO purchase_items (
               purchase_id, line_uuid, barcode, product_name, dosage, quantity,
               unit_cost_minor, line_total_minor, batch_number, version, updated_at, deleted_at
             )
             VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), NULL)
             ON CONFLICT (line_uuid) DO NOTHING`,
            [
              purchaseId,
              stableUuid(`purchase-item:${movement.movementUuid}`),
              movement.barcode,
              itemName,
              regRow?.dosage || '',
              Math.abs(movement.quantityDelta),
              movement.unitPriceMinor,
              (movement.unitPriceMinor || 0) * Math.abs(movement.quantityDelta),
              movement.metadata.batch_number || null,
              movement.version,
            ]
          );
        }
      }

      if (movement.movementType === 'return_in' || movement.movementType === 'return_out') {
        await client.query(
          `INSERT INTO returns (
             return_uuid, pharmacy_id, device_id, barcode, return_type, quantity,
             unit_price_minor, reason, reference_id, happened_at, version, sync_status,
             metadata, updated_at, deleted_at
           )
           VALUES (
             $1::uuid, $2, $3, $4, $5, $6,
             $7, $8, $9, $10, $11, 'synced',
             $12::jsonb, NOW(), NULL
           )
           ON CONFLICT (return_uuid) DO NOTHING`,
          [
            movement.movementUuid,
            pharmacy.id,
            effectiveHwid || 'UNKNOWN',
            movement.barcode,
            movement.movementType,
            Math.abs(movement.quantityDelta),
            movement.unitPriceMinor,
            movement.metadata.reason || null,
            movement.referenceId || null,
            movement.happenedAt,
            movement.version,
            JSON.stringify(movement.metadata || {}),
          ]
        );
      }

      if (['adjustment', 'loss', 'damaged', 'correction'].includes(movement.movementType)) {
        await client.query(
          `INSERT INTO stock_adjustments (
             adjustment_uuid, pharmacy_id, device_id, barcode, quantity_delta,
             reason, reference_id, happened_at, version, sync_status,
             metadata, updated_at, deleted_at
           )
           VALUES (
             $1::uuid, $2, $3, $4, $5,
             $6, $7, $8, $9, 'synced',
             $10::jsonb, NOW(), NULL
           )
           ON CONFLICT (adjustment_uuid) DO NOTHING`,
          [
            movement.movementUuid,
            pharmacy.id,
            effectiveHwid || 'UNKNOWN',
            movement.barcode,
            movement.quantityDelta,
            movement.metadata.reason || movement.movementType,
            movement.referenceId || null,
            movement.happenedAt,
            movement.version,
            JSON.stringify(movement.metadata || {}),
          ]
        );
      }

      if (isStockMovementType(movement.movementType) && movement.deletedAt == null && movement.quantityDelta !== 0) {
        await client.query(
          `INSERT INTO national_stock (barcode, medication_name, category, pharmacy_name, license_number, hwid, stock_units, threshold, status, region, last_sync, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW())
           ON CONFLICT (barcode, license_number) DO UPDATE SET
             medication_name = EXCLUDED.medication_name,
             category = EXCLUDED.category,
             pharmacy_name = EXCLUDED.pharmacy_name,
             hwid = EXCLUDED.hwid,
             stock_units = GREATEST(0, national_stock.stock_units + EXCLUDED.stock_units),
             threshold = COALESCE(NULLIF(national_stock.threshold, 0), EXCLUDED.threshold),
             status = CASE
               WHEN GREATEST(0, national_stock.stock_units + EXCLUDED.stock_units) < (COALESCE(NULLIF(national_stock.threshold, 0), EXCLUDED.threshold) * 0.25) THEN 'critical'
               WHEN GREATEST(0, national_stock.stock_units + EXCLUDED.stock_units) < COALESCE(NULLIF(national_stock.threshold, 0), EXCLUDED.threshold) THEN 'low'
               ELSE 'safe'
             END,
             region = EXCLUDED.region,
             last_sync = EXCLUDED.last_sync,
             updated_at = NOW()`,
          [
            movement.barcode,
            itemName,
            regRow?.category || 'Uncategorized',
            pharmacy?.name || null,
            pharmacy?.license_number || null,
            effectiveHwid || null,
            movement.quantityDelta,
            1000,
            stockStatus(Math.max(0, movement.quantityDelta), 1000),
            pharmacy?.region || null,
            movement.happenedAt.toISOString(),
          ]
        );
        movementUpdates += 1;
      }

      const priceMajor = Number.isFinite(movement.unitPriceMinor)
        ? Number(movement.unitPriceMinor) / 100
        : null;
      const registryPrice = regRow?.moph_ceiling != null ? Number(regRow.moph_ceiling) : null;
      const blockedMedicine = regRow?.is_blocked === true;

      if (blockedMedicine && movement.movementType === 'sale' && movement.quantityDelta < 0) {
        await client.query(
          `INSERT INTO audit_logs (event_id, pharmacy_name, hwid, license_number, region, event_type, item_name, registry_price, charged_price, unit_count, metadata)
           VALUES ($1, $2, $3, $4, $5, 'blocked_sale', $6, $7, $8, $9, $10::jsonb)`,
          [
            uid('EVT'),
            pharmacy?.name || null,
            effectiveHwid || null,
            pharmacy?.license_number || null,
            pharmacy?.region || null,
            itemName,
            registryPrice,
            priceMajor,
            Math.abs(movement.quantityDelta),
            JSON.stringify({ source: 'movement', movement_uuid: movement.movementUuid, barcode: movement.barcode }),
          ]
        );
        derivedAudits += 1;

        await client.query(
          `INSERT INTO compliance_alerts (
             alert_uuid, pharmacy_id, device_id, barcode, alert_type, severity, title, details, status, created_at, updated_at
           ) VALUES (
             $1::uuid, $2, $3, $4, 'blocked_sale', 'critical', $5, $6::jsonb, 'open', NOW(), NOW()
           ) ON CONFLICT (alert_uuid) DO NOTHING`,
          [
            stableUuid(`blocked-sale:${movement.movementUuid}`),
            pharmacy.id,
            effectiveHwid || null,
            movement.barcode,
            `Blocked medicine sold: ${itemName}`,
            JSON.stringify({ movement_uuid: movement.movementUuid, barcode: movement.barcode }),
          ]
        );
      }

      if (registryPrice != null && priceMajor != null && priceMajor > registryPrice) {
        await client.query(
          `INSERT INTO audit_logs (event_id, pharmacy_name, hwid, license_number, region, event_type, item_name, registry_price, charged_price, unit_count, metadata)
           VALUES ($1, $2, $3, $4, $5, 'price_hike', $6, $7, $8, $9, $10::jsonb)`,
          [
            uid('EVT'),
            pharmacy?.name || null,
            effectiveHwid || null,
            pharmacy?.license_number || null,
            pharmacy?.region || null,
            itemName,
            registryPrice,
            priceMajor,
            Math.max(1, Math.abs(movement.quantityDelta)),
            JSON.stringify({ source: 'movement', movement_uuid: movement.movementUuid, barcode: movement.barcode }),
          ]
        );
        derivedAudits += 1;

        await client.query(
          `INSERT INTO compliance_alerts (
             alert_uuid, pharmacy_id, device_id, barcode, alert_type, severity, title, details, status, created_at, updated_at
           ) VALUES (
             $1::uuid, $2, $3, $4, 'price_violation', 'high', $5, $6::jsonb, 'open', NOW(), NOW()
           ) ON CONFLICT (alert_uuid) DO NOTHING`,
          [
            stableUuid(`price-violation:${movement.movementUuid}`),
            pharmacy.id,
            effectiveHwid || null,
            movement.barcode,
            `Price above regulated ceiling: ${itemName}`,
            JSON.stringify({ charged_price: priceMajor, regulated_price: registryPrice, movement_uuid: movement.movementUuid }),
          ]
        );
      }

      await client.query(
        `INSERT INTO sync_outbox (event_uuid, pharmacy_id, device_id, direction, stream, payload, sync_status, created_at, updated_at)
         VALUES ($1::uuid, $2, $3, 'pos_to_server', 'inventory_movement', $4::jsonb, 'synced', NOW(), NOW())
         ON CONFLICT (event_uuid) DO NOTHING`,
        [
          movement.movementUuid,
          pharmacy.id,
          effectiveHwid || null,
          JSON.stringify({ barcode: movement.barcode, movement_type: movement.movementType, reference_id: movement.referenceId }),
        ]
      );

      syncedMovementUuids.push(movement.movementUuid);
    }

    const ignoredStockSnapshots = Array.isArray(stock) ? stock.length : 0;

    // Backward-compat adapter for canonical event-based payloads.
    let syncedMedicineRequests = 0;
    for (const rawEvent of eventBatch) {
      const eventId = normalized(rawEvent?.event_id || rawEvent?.eventId);
      const eventType = normalized(rawEvent?.event_type || rawEvent?.eventType).toLowerCase();
      const eventPayload = parseJsonSafely(rawEvent?.payload, {});
      if (!eventId || !eventType) continue;

      if (eventType !== 'medicine_request_submitted') {
        duplicateEventIds.push(eventId);
        continue;
      }

      const requestUuid = normalized(eventPayload.request_uuid || eventPayload.requestUuid || eventId);
      const barcode = normalized(eventPayload.barcode);
      const requestedName = normalized(eventPayload.requested_name || eventPayload.trade_name || eventPayload.name);
      if (!requestUuid || !barcode || !requestedName) {
        continue;
      }

      const upserted = await client.query(
        `INSERT INTO medicine_registration_requests (
           request_uuid,
           pharmacy_id,
           device_id,
           barcode,
           requested_name,
           generic_name,
           dosage,
           category,
           proposed_price_minor,
           stock_units,
           expiry,
           request_status,
           metadata,
           created_at,
           updated_at,
           deleted_at
         )
         VALUES (
           $1::uuid,
           $2,
           $3,
           $4,
           $5,
           $6,
           $7,
           $8,
           $9,
           $10,
           $11,
           $12,
           $13::jsonb,
           NOW(),
           NOW(),
           NULL
         )
         ON CONFLICT (request_uuid) DO UPDATE SET
           pharmacy_id = EXCLUDED.pharmacy_id,
           device_id = EXCLUDED.device_id,
           barcode = EXCLUDED.barcode,
           requested_name = EXCLUDED.requested_name,
           generic_name = EXCLUDED.generic_name,
           dosage = EXCLUDED.dosage,
           category = EXCLUDED.category,
           proposed_price_minor = EXCLUDED.proposed_price_minor,
           stock_units = EXCLUDED.stock_units,
           expiry = EXCLUDED.expiry,
           request_status = EXCLUDED.request_status,
           metadata = EXCLUDED.metadata,
           updated_at = NOW(),
           deleted_at = NULL
         RETURNING id`,
        [
          requestUuid,
          pharmacy.id,
          effectiveHwid || null,
          barcode,
          requestedName,
          normalized(eventPayload.generic_name || eventPayload.genericName || requestedName),
          normalized(eventPayload.dosage),
          normalized(eventPayload.category),
          toMinor(eventPayload.proposed_price ?? eventPayload.proposedPrice ?? 0),
          Math.max(0, Number(eventPayload.stock ?? eventPayload.stock_units ?? eventPayload.stockUnits ?? 0) || 0),
          normalized(eventPayload.expiry),
          normalized(eventPayload.request_status || eventPayload.requestStatus || 'pending_review') || 'pending_review',
          JSON.stringify({
            source: 'legacy_sync_adapter',
            payload: eventPayload,
          }),
        ]
      );

      if (upserted.rowCount > 0) {
        acceptedEventIds.push(eventId);
        syncedMedicineRequests += 1;
      } else {
        duplicateEventIds.push(eventId);
      }
    }

    const hoarding = await client.query(
      `WITH flow AS (
         SELECT
           SUM(CASE WHEN movement_type IN ('purchase', 'return_in') THEN ABS(quantity_delta) ELSE 0 END) AS incoming,
           SUM(CASE WHEN movement_type IN ('sale', 'return_out') THEN ABS(quantity_delta) ELSE 0 END) AS outgoing
         FROM inventory_movements
         WHERE pharmacy_id = $1
           AND happened_at >= NOW() - INTERVAL '30 days'
           AND deleted_at IS NULL
       )
       SELECT incoming, outgoing,
         CASE WHEN COALESCE(outgoing, 0) = 0 THEN COALESCE(incoming, 0)
              ELSE COALESCE(incoming, 0)::numeric / NULLIF(outgoing, 0)
         END AS ratio
       FROM flow`,
      [pharmacy.id]
    );
    const ratio = Number(hoarding.rows[0]?.ratio || 0);
    const incoming = Number(hoarding.rows[0]?.incoming || 0);
    if (incoming >= 30 && ratio >= 3) {
      await client.query(
        `INSERT INTO compliance_alerts (
           alert_uuid, pharmacy_id, device_id, alert_type, severity, title, details, status, created_at, updated_at
         ) VALUES (
           $1::uuid, $2, $3, 'hoarding_suspected', 'critical', $4, $5::jsonb, 'open', NOW(), NOW()
         ) ON CONFLICT (alert_uuid) DO NOTHING`,
        [
          stableUuid(`hoarding:${pharmacy.id}:${Math.floor(Date.now() / 21600000)}`),
          pharmacy.id,
          effectiveHwid || null,
          `Suspicious hoarding pattern at ${pharmacy.name}`,
          JSON.stringify({ ratio, incoming, window_days: 30 }),
        ]
      );
    }

    // Insert audit trails
    let insertedAudits = 0;
    for (const audit of audits) {
      const insertedAudit = await client.query(
        `INSERT INTO audit_logs (event_id, pharmacy_name, hwid, license_number, region, event_type, metadata)
         VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)`,
        [
          uid('EVT'),
          pharmacy?.name || null,
          effectiveHwid || null,
          pharmacy?.license_number || null,
          pharmacy?.region || null,
          audit.event_type || 'pos_sync_event',
          JSON.stringify(audit.metadata || {})
        ]
      );

      insertedAudits += insertedAudit.rowCount;
    }

    // Update POS sync state
    await client.query(`
      INSERT INTO pos_sync_state (hwid, pharmacy_id, last_sync_up, pending_updates, app_version)
      VALUES ($1, $2, NOW(), true, $3)
      ON CONFLICT (hwid) DO UPDATE SET
        last_sync_up = NOW(),
        pharmacy_id = EXCLUDED.pharmacy_id,
        app_version = $3,
        updated_at = NOW()
    `, [effectiveHwid || null, pharmacy.id, app_version]);

    const checkpointToken = new Date().toISOString();
    await client.query(
      `INSERT INTO sync_checkpoint (pharmacy_id, device_id, stream, checkpoint_token, checkpoint_time, updated_at)
       VALUES ($1, $2, 'pos_to_server', $3, NOW(), NOW())
       ON CONFLICT (device_id, stream) DO UPDATE SET
         pharmacy_id = EXCLUDED.pharmacy_id,
         checkpoint_token = EXCLUDED.checkpoint_token,
         checkpoint_time = EXCLUDED.checkpoint_time,
         updated_at = NOW()`,
      [pharmacy.id, effectiveHwid || 'UNKNOWN', checkpointToken]
    );

    await client.query('COMMIT');
    res.json({
      status: 'success',
      request_id: requestId,
      sync_protocol_version: syncProtocolVersion,
      pharmacy_id: pharmacy.id,
      pharmacy_name: pharmacy.name,
      accepted_event_ids: acceptedEventIds,
      duplicate_event_ids: duplicateEventIds,
      rejected_event_ids: [],
      synced_sales: insertedSales,
      synced_audits: insertedAudits + derivedAudits,
      stock_updates: stockUpdatesFromSales + movementUpdates,
      synced_medicine_requests: syncedMedicineRequests,
      ignored_stock_snapshots: ignoredStockSnapshots,
      synced_movement_uuids: syncedMovementUuids,
      checkpoint_token: checkpointToken,
      message: `Synced ${insertedSales} sales, ${insertedAudits + derivedAudits} audits, and ${stockUpdatesFromSales + movementUpdates} stock updates`,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(err);
    res.status(500).json({ error: 'Failed to sync up' });
  } finally {
    client.release();
  }
});

// --- Get Pending Updates for POS (Check what changed since last sync) ---
router.get('/pending-updates', async (req, res) => {
  const { hwid } = req.query;
  try {
    const syncState = await db.query(
      'SELECT last_sync_down FROM pos_sync_state WHERE hwid = $1',
      [hwid]
    );
    const lastSync = syncState.rows[0]?.last_sync_down || new Date(0);

    const changes = await db.query(
      `SELECT change_type, entity_type, new_value, created_at FROM change_log
       WHERE synced_to_pos = false AND created_at > $1
       ORDER BY created_at DESC`,
      [lastSync]
    );

    res.json({
      status: 'success',
      has_updates: changes.rows.length > 0,
      updates: changes.rows,
      count: changes.rows.length
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Acknowledge Sync Down (POS confirms it received updates) ---
router.post('/ack-sync-down', async (req, res) => {
  markLegacySyncAdapter(res, '/api/sync/ack');
  const { hwid, pharmacy_id, checkpoint_token } = req.body;
  try {
    await db.query(`
      UPDATE pos_sync_state
      SET last_sync_down = NOW(), pending_updates = false, updated_at = NOW()
      WHERE hwid = $1 AND pharmacy_id = $2
    `, [hwid, pharmacy_id]);

    // Mark all changes as synced to this POS
    await db.query(`
      UPDATE change_log
      SET synced_to_pos = true
      WHERE synced_to_pos = false
    `);

    if (normalized(hwid)) {
      await db.query(
        `INSERT INTO sync_checkpoint (pharmacy_id, device_id, stream, checkpoint_token, checkpoint_time, updated_at)
         VALUES ($1, $2, 'server_to_pos', $3, NOW(), NOW())
         ON CONFLICT (device_id, stream) DO UPDATE SET
           pharmacy_id = EXCLUDED.pharmacy_id,
           checkpoint_token = EXCLUDED.checkpoint_token,
           checkpoint_time = EXCLUDED.checkpoint_time,
           updated_at = NOW()`,
        [
          Number(pharmacy_id) > 0 ? Number(pharmacy_id) : null,
          normalized(hwid),
          normalized(checkpoint_token) || new Date().toISOString(),
        ]
      );
    }

    res.json({
      status: 'success',
      request_id: normalized(req.body?.request_id) || null,
      sync_protocol_version: readSyncProtocolVersion(req),
      message: 'Sync acknowledged',
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Get Settings & Configuration (POS pulls from Web) ---
router.get('/config', async (req, res) => {
  try {
    const [thresholds, settings, adjustReasons] = await Promise.all([
      db.query('SELECT * FROM stock_thresholds ORDER BY category ASC'),
      db.query('SELECT key, value FROM system_settings ORDER BY key ASC'),
      db.query('SELECT reason FROM adjustment_reasons ORDER BY id ASC'),
    ]);

    const settingMap = Object.fromEntries(
      settings.rows.map((s) => [s.key, s.value?.value])
    );

    res.json({
      status: 'success',
      data: {
        thresholds: thresholds.rows,
        settings: settingMap,
        adjustment_reasons: adjustReasons.rows.map((r) => r.reason),
      },
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Get Current Stock Levels (POS syncs stock from Web) ---
router.get('/stock-status', async (req, res) => {
  try {
    const r = await db.query(
      'SELECT barcode, medication_name, stock_units, status, threshold FROM national_stock ORDER BY status DESC, medication_name ASC'
    );
    res.json({ status: 'success', data: r.rows });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Get Current Pricing (POS syncs pricing from Web) ---
router.get('/pricing', async (req, res) => {
  try {
    const r = await db.query(
      `SELECT id, barcode, trade_name, dosage, moph_ceiling, 
              (SELECT registry_price FROM audit_logs WHERE item_name LIKE trade_name||'%' ORDER BY created_at DESC LIMIT 1) AS last_synced_price
       FROM moph_registry ORDER BY trade_name ASC`
    );
    res.json({ status: 'success', data: r.rows });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// --- Notify POS of Pharmacy Updates (Web pushes to POS) ---
router.post('/notify-update', async (req, res) => {
  const { pharmacy_id, update_type, data } = req.body;
  // update_type: 'pricing', 'stock', 'settings'. In production this would queue a push event.
  try {
    await db.query(
      `INSERT INTO audit_logs (event_id, event_type, metadata)
       VALUES ($1, $2, $3::jsonb)`,
      [
        uid('UPD'),
        `web_update_${update_type}`,
        JSON.stringify({ pharmacy_id, update_type, data, timestamp: new Date().toISOString() }),
      ]
    );
    res.json({ status: 'success' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
module.exports._test = {
  DEFAULT_SYNC_PROTOCOL_VERSION,
  stableUuid,
  parseJsonSafely,
  asUtcDateFromEpochMs,
  isStockMovementType,
  normalizeMovement,
  stockStatus,
  readSyncProtocolVersion,
};
