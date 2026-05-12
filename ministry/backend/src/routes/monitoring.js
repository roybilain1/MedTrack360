const express = require('express');
const db = require('../db');

const router = express.Router();

function toInt(value, fallback) {
  const n = Number.parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
}

function toNumber(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function parseDate(value) {
  if (!value) return null;
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return null;
  return dt;
}

function toIsoString(value) {
  const dt = parseDate(value);
  return dt ? dt.toISOString() : null;
}

function buildListMeta({ filters = {}, sortBy, sortDir, count }) {
  return {
    count: toInt(count, 0),
    empty: toInt(count, 0) === 0,
    filters,
    sort: {
      by: sortBy || null,
      dir: sortDir ? String(sortDir).toLowerCase() : null,
    },
    generated_at: new Date().toISOString(),
  };
}

function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}

function parsePagination(req) {
  const page = clamp(toInt(req.query.page, 1), 1, 100000);
  const pageSize = clamp(toInt(req.query.pageSize, 25), 1, 1000);
  const offset = (page - 1) * pageSize;
  return { page, pageSize, offset };
}

function parseSort(req, allowed, fallback) {
  const requested = String(req.query.sortBy || fallback).trim();
  const sortBy = allowed[requested] ? requested : fallback;
  const sortDir = String(req.query.sortDir || 'desc').toLowerCase() === 'asc' ? 'ASC' : 'DESC';
  return {
    sortBy,
    sortColumn: allowed[sortBy],
    sortDir,
  };
}

function parseCommonFilters(req) {
  return {
    pharmacy: String(req.query.pharmacy || '').trim(),
    medicine: String(req.query.medicine || '').trim(),
    region: String(req.query.region || '').trim(),
    status: String(req.query.status || '').trim(),
    from: parseDate(req.query.from),
    to: parseDate(req.query.to),
  };
}

function parseBoolean(value, fallback = false) {
  if (value === undefined || value === null || value === '') return fallback;
  const normalized = String(value).trim().toLowerCase();
  if (['1', 'true', 'yes', 'y', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) return false;
  return fallback;
}

function parseAuditFilters(req, { defaultIncludeSystem = false } = {}) {
  const common = parseCommonFilters(req);
  return {
    ...common,
    family: String(req.query.family || '').trim(),
    eventType: String(req.query.eventType || '').trim(),
    severity: String(req.query.severity || req.query.status || '').trim(),
    source: String(req.query.source || '').trim(),
    outcome: String(req.query.outcome || '').trim(),
    complianceOnly: parseBoolean(req.query.complianceOnly, false),
    includeSystem: parseBoolean(req.query.includeSystem, defaultIncludeSystem),
  };
}

function parseAuditSort(req) {
  return parseSort(
    req,
    {
      event_time: 'event_time',
      severity: 'severity_rank',
      event_family: 'event_family',
      pharmacy_name: 'pharmacy_name',
      medicine_name: 'medicine_name',
    },
    'event_time'
  );
}

async function queryAuditFeed({ filters, page, pageSize, offset, sort }) {
  const result = await db.query(
    `WITH latest_alert AS (
       SELECT DISTINCT ON (ca.pharmacy_id, ca.barcode)
         ca.pharmacy_id,
         ca.barcode,
         ca.alert_uuid::text AS alert_uuid,
         ca.severity AS alert_severity,
         ca.status AS alert_status,
         ca.created_at AS alert_created_at
       FROM compliance_alerts ca
       WHERE ca.deleted_at IS NULL
       ORDER BY ca.pharmacy_id, ca.barcode, ca.created_at DESC
     ),
     sales_events AS (
       SELECT
         im.event_uuid::text AS event_uuid,
         'sales'::text AS event_family,
         'sale_recorded'::text AS event_type,
         CASE
           WHEN mr.moph_ceiling IS NOT NULL AND im.unit_price_minor IS NOT NULL AND im.unit_price_minor > (mr.moph_ceiling * 100) THEN
             CONCAT('Sold ', ABS(im.quantity_delta)::int, ' units above regulated ceiling')
           ELSE
             CONCAT('Sold ', ABS(im.quantity_delta)::int, ' units')
         END AS event_title,
         CASE
           WHEN mr.trade_name IS NOT NULL THEN CONCAT('Medicine: ', mr.trade_name)
           ELSE 'Medicine linked by barcode only'
         END AS event_summary,
         CASE
           WHEN mr.moph_ceiling IS NOT NULL AND im.unit_price_minor IS NOT NULL AND im.unit_price_minor > (mr.moph_ceiling * 100) THEN 'high'
           WHEN la.alert_severity IS NOT NULL THEN la.alert_severity
           ELSE 'info'
         END AS severity,
         p.id AS pharmacy_id,
         p.name AS pharmacy_name,
         p.license_number,
         p.hwid,
         p.region,
         im.barcode,
         COALESCE(NULLIF(mr.trade_name, ''), NULLIF(im.metadata->>'item_name', ''), NULLIF(im.barcode, '')) AS medicine_name,
         ABS(im.quantity_delta)::int AS quantity_delta,
         (mr.moph_ceiling * 100)::numeric AS regulated_price_minor,
         im.unit_price_minor::numeric AS actual_price_minor,
         NULL::numeric AS old_price_minor,
         NULL::numeric AS new_price_minor,
         NULL::numeric AS price_delta_minor,
         CASE
           WHEN mr.moph_ceiling IS NOT NULL AND im.unit_price_minor IS NOT NULL
             THEN ROUND(((im.unit_price_minor - (mr.moph_ceiling * 100)) / NULLIF((mr.moph_ceiling * 100), 0))::numeric, 4)
           ELSE NULL
         END AS markup_pct,
         NULLIF(im.metadata->>'reason', '') AS reason,
         COALESCE(NULLIF(im.metadata->>'source', ''), 'pos') AS source,
         CASE
           WHEN COALESCE(im.metadata->>'blocked', 'false') = 'true' THEN 'blocked'
           WHEN mr.moph_ceiling IS NOT NULL AND im.unit_price_minor IS NOT NULL AND im.unit_price_minor > (mr.moph_ceiling * 100) THEN 'warning'
           ELSE 'allowed'
         END AS outcome,
         la.alert_uuid AS linked_alert_id,
         CONCAT('pharmacy:', p.id, '|barcode:', im.barcode) AS chain_key,
         im.happened_at AS event_time,
         COALESCE(im.metadata, '{}'::jsonb) AS metadata,
         false AS is_system_event,
         1::int AS severity_rank
       FROM inventory_movements im
       JOIN pharmacies p ON p.id = im.pharmacy_id
       LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
       LEFT JOIN latest_alert la ON la.pharmacy_id = im.pharmacy_id AND la.barcode = im.barcode
       WHERE im.deleted_at IS NULL
         AND im.movement_type = 'sale'
     ),
     price_change_events AS (
       SELECT
         ph.history_uuid::text AS event_uuid,
         'price_change'::text AS event_family,
         'selling_price_changed'::text AS event_type,
         CONCAT(
           'Selling price changed from ',
           TO_CHAR((ph.previous_price_minor / 100.0)::numeric, 'FM999999990.00'),
           ' to ',
           TO_CHAR((ph.new_price_minor / 100.0)::numeric, 'FM999999990.00')
         ) AS event_title,
         CASE
           WHEN mr.moph_ceiling IS NOT NULL AND ph.new_price_minor > (mr.moph_ceiling * 100) THEN 'New selling price exceeds regulated ceiling'
           WHEN ph.source = 'web' OR ph.source = 'admin' THEN 'Price updated from government/web control path'
           ELSE 'Price updated from branch-side system'
         END AS event_summary,
         CASE
           WHEN mr.moph_ceiling IS NOT NULL AND ph.new_price_minor > (mr.moph_ceiling * 100) THEN 'high'
           WHEN ABS((ph.new_price_minor - ph.previous_price_minor)::numeric / NULLIF(ph.previous_price_minor, 0)) >= 0.25 THEN 'medium'
           ELSE 'info'
         END AS severity,
         p.id AS pharmacy_id,
         p.name AS pharmacy_name,
         p.license_number,
         p.hwid,
         p.region,
         ph.barcode,
         COALESCE(NULLIF(mr.trade_name, ''), NULLIF(ph.barcode, '')) AS medicine_name,
         NULL::int AS quantity_delta,
         (mr.moph_ceiling * 100)::numeric AS regulated_price_minor,
         ph.new_price_minor::numeric AS actual_price_minor,
         ph.previous_price_minor::numeric AS old_price_minor,
         ph.new_price_minor::numeric AS new_price_minor,
         (ph.new_price_minor - ph.previous_price_minor)::numeric AS price_delta_minor,
         ROUND(((ph.new_price_minor - ph.previous_price_minor)::numeric / NULLIF(ph.previous_price_minor, 0))::numeric, 4) AS markup_pct,
         NULLIF(ph.metadata->>'reason', '') AS reason,
         COALESCE(NULLIF(ph.source, ''), 'pos') AS source,
         CASE
           WHEN mr.moph_ceiling IS NOT NULL AND ph.new_price_minor > (mr.moph_ceiling * 100) THEN 'warning'
           ELSE 'allowed'
         END AS outcome,
         la.alert_uuid AS linked_alert_id,
         CONCAT('pharmacy:', COALESCE(p.id::text, 'unknown'), '|barcode:', ph.barcode) AS chain_key,
         ph.changed_at AS event_time,
         COALESCE(ph.metadata, '{}'::jsonb) AS metadata,
         false AS is_system_event,
         2::int AS severity_rank
       FROM price_history ph
       LEFT JOIN pharmacies p ON p.id = ph.pharmacy_id
       LEFT JOIN moph_registry mr ON mr.barcode = ph.barcode
       LEFT JOIN latest_alert la ON la.pharmacy_id = ph.pharmacy_id AND la.barcode = ph.barcode
     ),
     stock_adjustment_events AS (
       SELECT
         im.event_uuid::text AS event_uuid,
         'stock_adjustment'::text AS event_family,
         'stock_adjusted'::text AS event_type,
         CONCAT('Stock adjusted by ', CASE WHEN im.quantity_delta >= 0 THEN '+' ELSE '' END, im.quantity_delta::int, ' units') AS event_title,
         CONCAT('Reason: ', COALESCE(NULLIF(im.metadata->>'reason', ''), 'unspecified')) AS event_summary,
         CASE
           WHEN ABS(im.quantity_delta) >= 100 THEN 'medium'
           ELSE 'info'
         END AS severity,
         p.id AS pharmacy_id,
         p.name AS pharmacy_name,
         p.license_number,
         p.hwid,
         p.region,
         im.barcode,
         COALESCE(NULLIF(mr.trade_name, ''), NULLIF(im.metadata->>'item_name', ''), NULLIF(im.barcode, '')) AS medicine_name,
         im.quantity_delta::int AS quantity_delta,
         (mr.moph_ceiling * 100)::numeric AS regulated_price_minor,
         im.unit_price_minor::numeric AS actual_price_minor,
         NULL::numeric AS old_price_minor,
         NULL::numeric AS new_price_minor,
         NULL::numeric AS price_delta_minor,
         NULL::numeric AS markup_pct,
         NULLIF(im.metadata->>'reason', '') AS reason,
         COALESCE(NULLIF(im.metadata->>'source', ''), 'manual_adjustment') AS source,
         'logged'::text AS outcome,
         la.alert_uuid AS linked_alert_id,
         CONCAT('pharmacy:', p.id, '|barcode:', im.barcode) AS chain_key,
         im.happened_at AS event_time,
         COALESCE(im.metadata, '{}'::jsonb) AS metadata,
         false AS is_system_event,
         3::int AS severity_rank
       FROM inventory_movements im
       JOIN pharmacies p ON p.id = im.pharmacy_id
       LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
       LEFT JOIN latest_alert la ON la.pharmacy_id = im.pharmacy_id AND la.barcode = im.barcode
       WHERE im.deleted_at IS NULL
         AND im.movement_type IN ('stock_adjust', 'adjustment', 'correction')
     ),
     inventory_events AS (
       SELECT
         im.event_uuid::text AS event_uuid,
         'inventory_movement'::text AS event_family,
         COALESCE(NULLIF(im.movement_type, ''), 'movement')::text AS event_type,
         CASE
           WHEN im.movement_type = 'purchase' THEN CONCAT('Received ', ABS(im.quantity_delta)::int, ' units into stock')
           WHEN im.movement_type = 'return' THEN CONCAT('Returned ', ABS(im.quantity_delta)::int, ' units')
           WHEN im.movement_type = 'transfer' THEN CONCAT('Transferred ', ABS(im.quantity_delta)::int, ' units')
           ELSE CONCAT('Inventory movement of ', ABS(im.quantity_delta)::int, ' units')
         END AS event_title,
         'Branch inventory movement event'::text AS event_summary,
         'info'::text AS severity,
         p.id AS pharmacy_id,
         p.name AS pharmacy_name,
         p.license_number,
         p.hwid,
         p.region,
         im.barcode,
         COALESCE(NULLIF(mr.trade_name, ''), NULLIF(im.metadata->>'item_name', ''), NULLIF(im.barcode, '')) AS medicine_name,
         im.quantity_delta::int AS quantity_delta,
         (mr.moph_ceiling * 100)::numeric AS regulated_price_minor,
         im.unit_price_minor::numeric AS actual_price_minor,
         NULL::numeric AS old_price_minor,
         NULL::numeric AS new_price_minor,
         NULL::numeric AS price_delta_minor,
         NULL::numeric AS markup_pct,
         NULLIF(im.metadata->>'reason', '') AS reason,
         COALESCE(NULLIF(im.metadata->>'source', ''), 'pos') AS source,
         'logged'::text AS outcome,
         la.alert_uuid AS linked_alert_id,
         CONCAT('pharmacy:', p.id, '|barcode:', im.barcode) AS chain_key,
         im.happened_at AS event_time,
         COALESCE(im.metadata, '{}'::jsonb) AS metadata,
         false AS is_system_event,
         4::int AS severity_rank
       FROM inventory_movements im
       JOIN pharmacies p ON p.id = im.pharmacy_id
       LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
       LEFT JOIN latest_alert la ON la.pharmacy_id = im.pharmacy_id AND la.barcode = im.barcode
       WHERE im.deleted_at IS NULL
         AND im.movement_type IN ('purchase', 'receipt', 'return', 'transfer')
     ),
     compliance_events AS (
       SELECT
         ca.alert_uuid::text AS event_uuid,
         'compliance'::text AS event_family,
         COALESCE(NULLIF(ca.alert_type, ''), 'compliance_alert') AS event_type,
         COALESCE(NULLIF(ca.title, ''), 'Compliance alert opened') AS event_title,
         CASE
           WHEN ca.details ? 'markup_pct' THEN CONCAT('Markup ratio: ', TO_CHAR(((ca.details->>'markup_pct')::numeric * 100.0), 'FM999990.0'), '%')
           WHEN ca.details ? 'days_of_stock' THEN CONCAT('Days of stock signal: ', ca.details->>'days_of_stock')
           ELSE 'Compliance evidence logged'
         END AS event_summary,
         COALESCE(NULLIF(ca.severity, ''), 'high') AS severity,
         p.id AS pharmacy_id,
         COALESCE(NULLIF(p.name, ''), NULL) AS pharmacy_name,
         p.license_number,
         p.hwid,
         p.region,
         ca.barcode,
         COALESCE(NULLIF(mr.trade_name, ''), NULLIF(ca.barcode, '')) AS medicine_name,
         NULL::int AS quantity_delta,
         (mr.moph_ceiling * 100)::numeric AS regulated_price_minor,
         NULL::numeric AS actual_price_minor,
         NULL::numeric AS old_price_minor,
         NULL::numeric AS new_price_minor,
         NULL::numeric AS price_delta_minor,
         NULL::numeric AS markup_pct,
         NULL::text AS reason,
         'compliance_engine'::text AS source,
         COALESCE(NULLIF(ca.status, ''), 'open') AS outcome,
         ca.alert_uuid::text AS linked_alert_id,
         CONCAT('pharmacy:', COALESCE(ca.pharmacy_id::text, 'unknown'), '|barcode:', COALESCE(ca.barcode, 'none')) AS chain_key,
         ca.created_at AS event_time,
         COALESCE(ca.details, '{}'::jsonb) AS metadata,
         false AS is_system_event,
         CASE
           WHEN ca.severity = 'critical' THEN 0
           WHEN ca.severity = 'high' THEN 1
           WHEN ca.severity = 'medium' THEN 2
           ELSE 3
         END AS severity_rank
       FROM compliance_alerts ca
       LEFT JOIN pharmacies p ON p.id = ca.pharmacy_id
       LEFT JOIN moph_registry mr ON mr.barcode = ca.barcode
       WHERE ca.deleted_at IS NULL
     ),
     sync_events AS (
       SELECT
         COALESCE(a.event_id, CONCAT('audit-log-', a.id::text)) AS event_uuid,
         'sync_governance'::text AS event_family,
         COALESCE(NULLIF(a.event_type, ''), 'sync_event') AS event_type,
         CASE
           WHEN a.event_type = 'pricing_sync_from_web' THEN 'Government pricing sync applied'
           WHEN a.event_type = 'stock_sync_from_web' THEN 'Government stock sync applied'
           WHEN a.event_type = 'sync_push_event' THEN 'POS synchronization push processed'
           ELSE 'System synchronization event'
         END AS event_title,
         'Technical synchronization metadata recorded for traceability'::text AS event_summary,
         'low'::text AS severity,
         p.id AS pharmacy_id,
         COALESCE(NULLIF(a.pharmacy_name, ''), p.name) AS pharmacy_name,
         COALESCE(NULLIF(a.license_number, ''), p.license_number) AS license_number,
         COALESCE(NULLIF(a.hwid, ''), p.hwid) AS hwid,
         COALESCE(NULLIF(a.region, ''), p.region) AS region,
         NULLIF(a.metadata->>'barcode', '') AS barcode,
         NULLIF(a.item_name, '') AS medicine_name,
         NULLIF(a.unit_count, 0)::int AS quantity_delta,
         CASE WHEN a.registry_price IS NULL OR a.registry_price = 0 THEN NULL ELSE (a.registry_price * 100)::numeric END AS regulated_price_minor,
         CASE WHEN a.charged_price IS NULL OR a.charged_price = 0 THEN NULL ELSE (a.charged_price * 100)::numeric END AS actual_price_minor,
         NULL::numeric AS old_price_minor,
         NULL::numeric AS new_price_minor,
         NULL::numeric AS price_delta_minor,
         NULL::numeric AS markup_pct,
         NULLIF(a.metadata->>'reason', '') AS reason,
         COALESCE(NULLIF(a.metadata->>'source', ''), 'system_sync') AS source,
         'logged'::text AS outcome,
         NULL::text AS linked_alert_id,
         CONCAT('sync:', COALESCE(NULLIF(a.hwid, ''), COALESCE(p.hwid, 'unknown'))) AS chain_key,
         a.created_at AS event_time,
         COALESCE(a.metadata, '{}'::jsonb) AS metadata,
         true AS is_system_event,
         5::int AS severity_rank
       FROM audit_logs a
       LEFT JOIN LATERAL (
         SELECT px.id, px.name, px.license_number, px.hwid, px.region
         FROM pharmacies px
         WHERE (
             a.license_number IS NOT NULL AND a.license_number <> '' AND px.license_number = a.license_number
           ) OR (
             a.hwid IS NOT NULL AND a.hwid <> '' AND px.hwid = a.hwid
           ) OR (
             a.pharmacy_name IS NOT NULL AND a.pharmacy_name <> '' AND px.name = a.pharmacy_name
           )
         ORDER BY
           CASE
             WHEN a.license_number IS NOT NULL AND a.license_number <> '' AND px.license_number = a.license_number THEN 0
             WHEN a.hwid IS NOT NULL AND a.hwid <> '' AND px.hwid = a.hwid THEN 1
             ELSE 2
           END
         LIMIT 1
       ) p ON TRUE
       WHERE a.event_type IN ('sync_push_event', 'pricing_sync_from_web', 'stock_sync_from_web')
     ),
     all_events AS (
       SELECT * FROM sales_events
       UNION ALL
       SELECT * FROM price_change_events
       UNION ALL
       SELECT * FROM stock_adjustment_events
       UNION ALL
       SELECT * FROM inventory_events
       UNION ALL
       SELECT * FROM compliance_events
       UNION ALL
       SELECT * FROM sync_events
     ),
     filtered AS (
       SELECT
         ae.*,
         COUNT(*) OVER()::int AS total_count
       FROM all_events ae
       WHERE ($1 = '' OR COALESCE(ae.pharmacy_name, '') ILIKE $2 OR COALESCE(ae.license_number, '') ILIKE $2 OR COALESCE(ae.hwid, '') ILIKE $2)
         AND ($3 = '' OR COALESCE(ae.medicine_name, '') ILIKE $4 OR COALESCE(ae.barcode, '') ILIKE $4)
         AND ($5 = '' OR COALESCE(ae.region, '') ILIKE $6)
         AND ($7 = '' OR ae.event_family = $7)
         AND ($8 = '' OR ae.event_type = $8)
         AND ($9 = '' OR ae.severity = $9)
         AND ($10 = '' OR ae.source = $10)
         AND ($11::timestamptz IS NULL OR ae.event_time >= $11::timestamptz)
         AND ($12::timestamptz IS NULL OR ae.event_time <= $12::timestamptz)
         AND ($13::boolean = false OR ae.event_family = 'compliance' OR ae.severity IN ('critical', 'high'))
         AND ($14::boolean = true OR ae.is_system_event = false)
         AND ($15 = '' OR ae.outcome = $15)
     )
     SELECT *
     FROM filtered
     ORDER BY ${sort.sortColumn} ${sort.sortDir} NULLS LAST
     LIMIT $16 OFFSET $17`,
    [
      filters.pharmacy,
      `%${filters.pharmacy}%`,
      filters.medicine,
      `%${filters.medicine}%`,
      filters.region,
      `%${filters.region}%`,
      filters.family,
      filters.eventType,
      filters.severity,
      filters.source,
      filters.from ? filters.from.toISOString() : null,
      filters.to ? filters.to.toISOString() : null,
      filters.complianceOnly,
      filters.includeSystem,
      filters.outcome,
      pageSize,
      offset,
    ]
  );

  const total = result.rows[0]?.total_count || 0;

  return {
    rows: result.rows,
    pagination: {
      page,
      pageSize,
      total,
      totalPages: Math.max(1, Math.ceil(total / pageSize)),
    },
  };
}

function encodeAlertId(payload) {
  return Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
}

function decodeAlertId(id) {
  try {
    const parsed = JSON.parse(Buffer.from(String(id), 'base64url').toString('utf8'));
    if (!parsed || typeof parsed !== 'object') return null;
    return parsed;
  } catch {
    return null;
  }
}

function looksLikeUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(value || '').trim());
}

router.get('/overview', async (req, res) => {
  const markupThreshold = toNumber(req.query.markupThreshold, 0.15);
  const daysOfStockCritical = toInt(req.query.daysOfStockCritical, 60);
  const syncOverdueHours = toInt(req.query.syncOverdueHours, 12);

  try {
    const result = await db.query(
      `WITH stock AS (
         SELECT
           im.pharmacy_id,
           im.barcode,
           GREATEST(0, SUM(im.quantity_delta))::int AS stock_units,
           SUM(CASE WHEN im.movement_type = 'sale' AND im.happened_at >= NOW() - INTERVAL '30 days' THEN ABS(im.quantity_delta) ELSE 0 END)::numeric AS sold_30d
         FROM inventory_movements im
         WHERE im.deleted_at IS NULL
         GROUP BY im.pharmacy_id, im.barcode
       ), latest_price_events AS (
         SELECT
           ph.pharmacy_id,
           ph.barcode,
           ph.new_price_minor::numeric AS local_price_minor,
           ph.changed_at AS event_time
         FROM price_history ph
         WHERE ph.new_price_minor IS NOT NULL

         UNION ALL

         SELECT
           im.pharmacy_id,
           im.barcode,
           im.unit_price_minor::numeric AS local_price_minor,
           im.happened_at AS event_time
         FROM inventory_movements im
         WHERE im.deleted_at IS NULL
           AND im.movement_type = 'price_change'
           AND im.unit_price_minor IS NOT NULL
       ), latest_local_price AS (
         SELECT DISTINCT ON (lpe.pharmacy_id, lpe.barcode)
           lpe.pharmacy_id,
           lpe.barcode,
           lpe.local_price_minor
         FROM latest_price_events lpe
         ORDER BY lpe.pharmacy_id, lpe.barcode, lpe.event_time DESC
       ), canonical_price_fallback AS (
         SELECT
           pr.barcode,
           pr.local_price_minor::numeric AS local_price_minor
         FROM prices pr
         WHERE pr.deleted_at IS NULL
           AND pr.local_price_minor IS NOT NULL
       ), pricing_sales AS (
         SELECT
           im.pharmacy_id,
           im.barcode,
           AVG(im.unit_price_minor)::numeric AS avg_selling_price_minor,
           MAX((mr.moph_ceiling * 100)::numeric) AS regulated_price_minor,
           MAX(im.happened_at) AS last_sale_at
         FROM inventory_movements im
         LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
         WHERE im.deleted_at IS NULL
           AND im.movement_type = 'sale'
           AND im.happened_at >= NOW() - INTERVAL '30 days'
           AND im.unit_price_minor IS NOT NULL
         GROUP BY im.pharmacy_id, im.barcode
       ), observed_pairs AS (
         SELECT ps.pharmacy_id, ps.barcode
         FROM pricing_sales ps

         UNION

         SELECT llp.pharmacy_id, llp.barcode
         FROM latest_local_price llp
       ), pricing AS (
         SELECT
           op.pharmacy_id,
           op.barcode,
           COALESCE(llp.local_price_minor, cpf.local_price_minor, ps.avg_selling_price_minor) AS avg_selling_price_minor,
           COALESCE(ps.regulated_price_minor, (mr.moph_ceiling * 100)::numeric) AS regulated_price_minor
         FROM observed_pairs op
         LEFT JOIN pricing_sales ps
           ON ps.pharmacy_id = op.pharmacy_id
          AND ps.barcode = op.barcode
         LEFT JOIN latest_local_price llp
           ON llp.pharmacy_id = op.pharmacy_id
          AND llp.barcode = op.barcode
         LEFT JOIN canonical_price_fallback cpf
           ON cpf.barcode = op.barcode
         LEFT JOIN moph_registry mr
           ON mr.barcode = op.barcode
       ), pricing_flags AS (
         SELECT COUNT(*)::int AS high_price_count
         FROM pricing
         WHERE regulated_price_minor IS NOT NULL
           AND avg_selling_price_minor IS NOT NULL
           AND (
             avg_selling_price_minor > regulated_price_minor
             OR ((avg_selling_price_minor - regulated_price_minor) / NULLIF(regulated_price_minor, 0)) > $1
           )
       ), hoarding_flags AS (
         SELECT COUNT(*)::int AS hoarding_count
         FROM stock
         WHERE (sold_30d <= 5 AND stock_units >= 10)
            OR (stock_units / NULLIF(sold_30d / 30.0, 0)) > $2
       ), sync_health AS (
         SELECT
           COUNT(*)::int AS total_pharmacies,
           COUNT(*) FILTER (
             WHERE p.status != 'online'
               OR s.last_sync_up IS NULL
               OR s.last_sync_up < NOW() - make_interval(hours => $3)
           )::int AS unhealthy_pharmacies
         FROM pharmacies p
         LEFT JOIN pos_sync_state s ON s.pharmacy_id = p.id
       ), alerts_count AS (
         SELECT COUNT(*)::int AS open_alerts
         FROM compliance_alerts
         WHERE status = 'open' AND deleted_at IS NULL
       )
       SELECT
         (SELECT high_price_count FROM pricing_flags) AS high_price_count,
         (SELECT hoarding_count FROM hoarding_flags) AS hoarding_count,
         (SELECT unhealthy_pharmacies FROM sync_health) AS unhealthy_pharmacies,
         (SELECT total_pharmacies FROM sync_health) AS total_pharmacies,
         (SELECT open_alerts FROM alerts_count) AS open_alerts`,
      [markupThreshold, daysOfStockCritical, syncOverdueHours]
    );

    const row = result.rows[0] || {};
    res.json({
      status: 'success',
      data: {
        high_price_count: toInt(row.high_price_count, 0),
        hoarding_count: toInt(row.hoarding_count, 0),
        unhealthy_pharmacies: toInt(row.unhealthy_pharmacies, 0),
        total_pharmacies: toInt(row.total_pharmacies, 0),
        open_alerts: toInt(row.open_alerts, 0),
      },
      rules: {
        markupThreshold,
        daysOfStockCritical,
        syncOverdueHours,
      },
      meta: {
        generated_at: new Date().toISOString(),
      },
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/stock', async (req, res) => {
  const filters = parseCommonFilters(req);
  const { page, pageSize, offset } = parsePagination(req);
  const criticalDaysFloor = toNumber(req.query.criticalDaysFloor, 3);
  const lowDaysFloor = toNumber(req.query.lowDaysFloor, 7);
  const minimumDailyRate = toNumber(req.query.minimumDailyRate, 0.25);
  const sort = parseSort(
    req,
    {
      risk_rank: 'risk_rank',
      pharmacy_name: 'pharmacy_name',
      medicine_name: 'medicine_name',
      stock_units: 'stock_units',
      days_of_stock: 'days_of_stock',
      sales_30d: 'sales_30d',
      last_movement_at: 'last_movement_at',
    },
    'risk_rank'
  );

  try {
    const result = await db.query(
      `WITH latest_price_events AS (
         SELECT
           ph.pharmacy_id,
           ph.barcode,
           ph.new_price_minor::numeric AS local_price_minor,
           ph.changed_at AS event_time
         FROM price_history ph
         WHERE ph.new_price_minor IS NOT NULL

         UNION ALL

         SELECT
           im.pharmacy_id,
           im.barcode,
           im.unit_price_minor::numeric AS local_price_minor,
           im.happened_at AS event_time
         FROM inventory_movements im
         WHERE im.deleted_at IS NULL
           AND im.movement_type = 'price_change'
           AND im.unit_price_minor IS NOT NULL
       ), latest_local_price AS (
         SELECT DISTINCT ON (lpe.pharmacy_id, lpe.barcode)
           lpe.pharmacy_id,
           lpe.barcode,
           lpe.local_price_minor
         FROM latest_price_events lpe
         ORDER BY lpe.pharmacy_id, lpe.barcode, lpe.event_time DESC
       ), latest_batch_expiry AS (
         SELECT
           pb.pharmacy_id,
           pb.barcode,
           MIN(pb.expiry_at) AS expiry_at
         FROM product_batches pb
         WHERE pb.deleted_at IS NULL
           AND pb.expiry_at IS NOT NULL
         GROUP BY pb.pharmacy_id, pb.barcode
       ), grouped AS (
         SELECT
           p.id AS pharmacy_id,
           p.name AS pharmacy_name,
           p.license_number,
           p.hwid,
           p.region,
           mr.barcode,
           COALESCE(mr.trade_name, mr.barcode) AS medicine_name,
           COALESCE(NULLIF(mr.dosage, ''), '') AS dosage,
           COALESCE(NULLIF(mr.category, ''), NULLIF(ns.category, ''), 'Uncategorized') AS category,
           COALESCE(MAX(ns.threshold), 0)::numeric AS configured_threshold,
           -- Stock units: prefer the live trigger-maintained pharmacy_stock.stock_units;
           -- fall back to summing inventory_movements when present
           GREATEST(0, COALESCE(MAX(ps.stock_units), SUM(im.quantity_delta), 0))::int AS stock_units,
           SUM(CASE WHEN im.movement_type = 'sale' AND im.happened_at >= NOW() - INTERVAL '30 days' THEN ABS(im.quantity_delta) ELSE 0 END)::numeric AS sales_30d,
           SUM(CASE WHEN im.movement_type = 'purchase' AND im.happened_at >= NOW() - INTERVAL '30 days' THEN ABS(im.quantity_delta) ELSE 0 END)::numeric AS purchases_30d,
           MAX(im.happened_at) AS last_movement_at,
           MAX(ss.last_sync_up) AS last_sync_up,
           MAX(ss.last_sync_down) AS last_sync_down,
           COALESCE(MAX(llp.local_price_minor), MAX((ps.current_price * 100)::numeric), NULL)::numeric AS current_price_minor,
           COALESCE(MAX((mr.moph_ceiling * 100)::numeric), NULL)::numeric AS regulated_price_minor,
           MAX(lbe.expiry_at) AS expiry_at
         FROM pharmacy_stock ps
         JOIN pharmacies p ON p.id = ps.pharmacy_id
         JOIN moph_registry mr ON mr.medication_id = ps.medication_id
         LEFT JOIN inventory_movements im
           ON im.pharmacy_id = ps.pharmacy_id
          AND im.barcode = mr.barcode
          AND im.deleted_at IS NULL
         LEFT JOIN (
           SELECT barcode, MAX(threshold) AS threshold, MAX(category) AS category
           FROM national_stock
           GROUP BY barcode
         ) ns ON ns.barcode = mr.barcode
         LEFT JOIN pos_sync_state ss ON ss.pharmacy_id = p.id
         LEFT JOIN latest_local_price llp ON llp.pharmacy_id = p.id AND llp.barcode = mr.barcode
         LEFT JOIN latest_batch_expiry lbe ON lbe.pharmacy_id = p.id AND lbe.barcode = mr.barcode
         WHERE ($1 = '' OR p.name ILIKE $2 OR p.license_number ILIKE $2)
           AND ($3 = '' OR mr.barcode ILIKE $4 OR mr.trade_name ILIKE $4)
           AND ($5 = '' OR p.region ILIKE $6)
           AND ($7::timestamptz IS NULL OR im.happened_at IS NULL OR im.happened_at >= $7::timestamptz)
           AND ($8::timestamptz IS NULL OR im.happened_at IS NULL OR im.happened_at <= $8::timestamptz)
         GROUP BY p.id, p.name, p.license_number, p.hwid, p.region, mr.barcode, mr.trade_name, COALESCE(NULLIF(mr.dosage, ''), ''), COALESCE(NULLIF(mr.category, ''), NULLIF(ns.category, ''), 'Uncategorized')
       ), metrics AS (
         SELECT
           g.*,
           CASE
             WHEN g.configured_threshold > 0 THEN ROUND(g.configured_threshold)
             WHEN g.sales_30d > 0 THEN CEIL((g.sales_30d / 30.0) * 14.0)
             ELSE NULL
           END AS threshold_units,
           CASE
             WHEN g.sales_30d > 0 THEN ROUND(g.sales_30d / 30.0, 4)
             ELSE NULL
           END AS avg_daily_sales,
           CASE
             WHEN g.stock_units <= 0 THEN 0
             WHEN g.sales_30d > 0 THEN ROUND(LEAST(3650, g.stock_units / GREATEST(g.sales_30d / 30.0, $9)), 2)
             ELSE NULL
           END AS days_of_stock,
           CASE
             WHEN g.stock_units <= 0 THEN 'out_of_stock'
             WHEN g.sales_30d <= 0 THEN 'no_demand_history'
             WHEN (g.sales_30d / 30.0) < $9 THEN 'recent_sales_min_rate'
             ELSE 'recent_sales_30d'
           END AS coverage_basis
         FROM grouped g
       ), scored AS (
         SELECT
           m.*,
           CASE
             WHEN m.stock_units <= 0 THEN 'critical'
             WHEN (
               CASE
                 WHEN m.threshold_units > 0 THEN m.stock_units <= (m.threshold_units * 0.25)
                 ELSE false
               END
             ) OR (m.days_of_stock IS NOT NULL AND m.days_of_stock <= $10) THEN 'critical'
             WHEN (
               CASE
                 WHEN m.threshold_units > 0 THEN m.stock_units < m.threshold_units
                 ELSE false
               END
             ) OR (m.days_of_stock IS NOT NULL AND m.days_of_stock <= $11) THEN 'low'
             WHEN m.sales_30d > 0 AND m.purchases_30d > (m.sales_30d * 2.0) AND m.stock_units > 0 THEN 'watch'
             WHEN m.coverage_basis = 'no_demand_history' AND m.threshold_units IS NULL THEN 'unknown'
             ELSE 'safe'
           END AS status
         FROM metrics m
       ), final_rows AS (
         SELECT
           s.*,
           CASE
             WHEN s.status = 'critical' THEN 'threshold_or_coverage_breach'
             WHEN s.status = 'low' THEN 'near_threshold_or_low_coverage'
             WHEN s.status = 'watch' THEN 'inbound_outpaces_dispensing'
             WHEN s.status = 'unknown' THEN 'insufficient_demand_and_threshold'
             ELSE 'within_threshold_and_coverage'
           END AS status_basis,
           CASE
             WHEN s.stock_units <= 0 THEN 'Out of Stock'
             WHEN s.status = 'critical' THEN 'Low'
             WHEN s.status = 'low' THEN 'Low'
             WHEN s.status = 'watch' THEN 'Watch'
             ELSE 'In Stock'
           END AS stock_state_label,
           CASE
             WHEN s.status = 'critical' THEN 1
             WHEN s.status = 'low' THEN 2
             WHEN s.status = 'watch' THEN 3
             WHEN s.status = 'unknown' THEN 4
             ELSE 5
           END AS risk_rank,
           COUNT(*) OVER()::int AS total_count
         FROM scored s
       ), filtered AS (
         SELECT *
         FROM final_rows
         WHERE ($12 = '' OR status = $12)
       ), scoped AS (
         SELECT
           COUNT(*)::int AS filtered_rows,
           COUNT(DISTINCT pharmacy_id)::int AS active_pharmacies
         FROM filtered
       )
       SELECT f.*, s.active_pharmacies, s.filtered_rows
       FROM filtered f
       CROSS JOIN scoped s
       ORDER BY ${sort.sortColumn} ${sort.sortDir} NULLS LAST
       LIMIT $13 OFFSET $14`,
      [
        filters.pharmacy,
        `%${filters.pharmacy}%`,
        filters.medicine,
        `%${filters.medicine}%`,
        filters.region,
        `%${filters.region}%`,
        filters.from ? filters.from.toISOString() : null,
        filters.to ? filters.to.toISOString() : null,
        minimumDailyRate,
        criticalDaysFloor,
        lowDaysFloor,
        filters.status,
        pageSize,
        offset,
      ]
    );

    const total = result.rows[0]?.filtered_rows ?? result.rows[0]?.total_count ?? 0;
    const activePharmacies = toInt(result.rows[0]?.active_pharmacies, 0);
    res.json({
      status: 'success',
      data: result.rows,
      pagination: {
        page,
        pageSize,
        total,
        totalPages: Math.max(1, Math.ceil(total / pageSize)),
      },
      meta: buildListMeta({
        filters,
        sortBy: sort.sortBy,
        sortDir: sort.sortDir,
        count: result.rows.length,
      }),
      rules: {
        minimumDailyRate,
        criticalDaysFloor,
        lowDaysFloor,
      },
      scope: {
        active_pharmacies: activePharmacies,
        scope_label:
          activePharmacies <= 1
            ? 'Current stock risk view based on the latest synchronized inventory from 1 active pharmacy'
            : `Live branch risk view derived from latest synced POS inventory across ${activePharmacies} active pharmacies`,
      },
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/pricing', async (req, res) => {
  const filters = parseCommonFilters(req);
  const { page, pageSize, offset } = parsePagination(req);
  const markupThreshold = toNumber(req.query.markupThreshold, 0.15);
  const sort = parseSort(
    req,
    {
      markup_pct: 'markup_pct',
      pharmacy_name: 'pharmacy_name',
      medicine_name: 'medicine_name',
      avg_selling_price_minor: 'avg_selling_price_minor',
      regulated_price_minor: 'regulated_price_minor',
    },
    'markup_pct'
  );

  try {
    const result = await db.query(
      `WITH latest_price_events AS (
         SELECT
           ph.pharmacy_id,
           ph.barcode,
           ph.new_price_minor::numeric AS local_price_minor,
           ph.changed_at AS event_time
         FROM price_history ph
         WHERE ph.new_price_minor IS NOT NULL

         UNION ALL

         SELECT
           im.pharmacy_id,
           im.barcode,
           im.unit_price_minor::numeric AS local_price_minor,
           im.happened_at AS event_time
         FROM inventory_movements im
         WHERE im.deleted_at IS NULL
           AND im.movement_type = 'price_change'
           AND im.unit_price_minor IS NOT NULL
       ), latest_local_price AS (
         SELECT DISTINCT ON (lpe.pharmacy_id, lpe.barcode)
           lpe.pharmacy_id,
           lpe.barcode,
           lpe.local_price_minor,
           lpe.event_time
         FROM latest_price_events lpe
         ORDER BY lpe.pharmacy_id, lpe.barcode, lpe.event_time DESC
       ), canonical_price_fallback AS (
         SELECT
           pr.barcode,
           pr.local_price_minor::numeric AS local_price_minor
         FROM prices pr
         WHERE pr.deleted_at IS NULL
           AND pr.local_price_minor IS NOT NULL
       ), sales_price AS (
         SELECT
           im.pharmacy_id,
           im.barcode,
           AVG(im.unit_price_minor)::numeric AS avg_selling_price_minor,
           MAX((mr.moph_ceiling * 100)::numeric) AS regulated_price_minor,
           MAX(im.happened_at) AS last_sale_at
         FROM inventory_movements im
         LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
         WHERE im.deleted_at IS NULL
           AND im.movement_type = 'sale'
           AND im.unit_price_minor IS NOT NULL
         GROUP BY im.pharmacy_id, im.barcode
       ), observed_pairs AS (
         SELECT sp.pharmacy_id, sp.barcode
         FROM sales_price sp

         UNION

         SELECT llp.pharmacy_id, llp.barcode
         FROM latest_local_price llp
       ), pricing_base AS (
         SELECT
           p.id AS pharmacy_id,
           p.name AS pharmacy_name,
           p.region,
           op.barcode,
           COALESCE(mr.trade_name, op.barcode) AS medicine_name,
           COALESCE(
             MAX(llp.local_price_minor),
             MAX(cpf.local_price_minor),
             MAX(sp.avg_selling_price_minor)
           ) AS avg_selling_price_minor,
           COALESCE(
             MAX(sp.regulated_price_minor),
             MAX((mr.moph_ceiling * 100)::numeric)
           ) AS regulated_price_minor,
           MAX(sp.last_sale_at) AS last_sale_at,
           MAX(llp.event_time) AS last_price_event_at
         FROM observed_pairs op
         JOIN pharmacies p ON p.id = op.pharmacy_id
         LEFT JOIN moph_registry mr ON mr.barcode = op.barcode
         LEFT JOIN sales_price sp
           ON sp.pharmacy_id = op.pharmacy_id
          AND sp.barcode = op.barcode
         LEFT JOIN latest_local_price llp
           ON llp.pharmacy_id = op.pharmacy_id
          AND llp.barcode = op.barcode
         LEFT JOIN canonical_price_fallback cpf
           ON cpf.barcode = op.barcode
         WHERE op.barcode IS NOT NULL
           AND ($1 = '' OR p.name ILIKE $2 OR p.license_number ILIKE $2)
           AND ($3 = '' OR op.barcode ILIKE $4 OR mr.trade_name ILIKE $4)
           AND ($5 = '' OR p.region ILIKE $6)
           AND ($7::timestamptz IS NULL OR COALESCE(llp.event_time, sp.last_sale_at) >= $7::timestamptz)
           AND ($8::timestamptz IS NULL OR COALESCE(llp.event_time, sp.last_sale_at) <= $8::timestamptz)
         GROUP BY p.id, p.name, p.region, op.barcode, mr.trade_name
       ), with_rule AS (
         SELECT
           pb.*,
           ROUND(((pb.avg_selling_price_minor - pb.regulated_price_minor) / NULLIF(pb.regulated_price_minor, 0))::numeric, 4) AS markup_pct,
           CASE
             WHEN pb.regulated_price_minor IS NULL THEN 'missing_regulated_price'
             WHEN pb.avg_selling_price_minor > pb.regulated_price_minor THEN 'high_price'
             WHEN ((pb.avg_selling_price_minor - pb.regulated_price_minor) / NULLIF(pb.regulated_price_minor, 0)) > $9 THEN 'high_markup'
             ELSE 'ok'
           END AS status
         FROM pricing_base pb
       )
       SELECT *, COUNT(*) OVER()::int AS total_count
       FROM with_rule
       WHERE ($10 = '' OR status = $10)
       ORDER BY ${sort.sortColumn} ${sort.sortDir}
       LIMIT $11 OFFSET $12`,
      [
        filters.pharmacy,
        `%${filters.pharmacy}%`,
        filters.medicine,
        `%${filters.medicine}%`,
        filters.region,
        `%${filters.region}%`,
        filters.from ? filters.from.toISOString() : null,
        filters.to ? filters.to.toISOString() : null,
        markupThreshold,
        filters.status,
        pageSize,
        offset,
      ]
    );

    const total = result.rows[0]?.total_count || 0;
    res.json({
      status: 'success',
      data: result.rows,
      pagination: {
        page,
        pageSize,
        total,
        totalPages: Math.max(1, Math.ceil(total / pageSize)),
      },
      rules: {
        markupThreshold,
      },
      meta: buildListMeta({
        filters,
        sortBy: sort.sortBy,
        sortDir: sort.sortDir,
        count: result.rows.length,
      }),
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/hoarding-alerts', async (req, res) => {
  const filters = parseCommonFilters(req);
  const { page, pageSize, offset } = parsePagination(req);
  const daysOfStockCritical = toInt(req.query.daysOfStockCritical, 60);
  const purchaseToSalesFactor = toNumber(req.query.purchaseToSalesFactor, 2);
  const sort = parseSort(
    req,
    {
      days_of_stock: 'days_of_stock',
      purchases_30d: 'purchases_30d',
      sales_30d: 'sales_30d',
      pharmacy_name: 'pharmacy_name',
    },
    'days_of_stock'
  );

  try {
    const result = await db.query(
      `WITH demand_rank AS (
         SELECT
           im.barcode,
           SUM(CASE WHEN im.movement_type = 'sale' THEN ABS(im.quantity_delta) ELSE 0 END) AS sold_90d,
           NTILE(5) OVER (ORDER BY SUM(CASE WHEN im.movement_type = 'sale' THEN ABS(im.quantity_delta) ELSE 0 END) DESC) AS demand_bucket
         FROM inventory_movements im
         WHERE im.deleted_at IS NULL
           AND im.happened_at >= NOW() - INTERVAL '90 days'
         GROUP BY im.barcode
       ), stock_rules AS (
         SELECT
           p.id AS pharmacy_id,
           p.name AS pharmacy_name,
           p.region,
           im.barcode,
           COALESCE(mr.trade_name, im.barcode) AS medicine_name,
           GREATEST(0, SUM(im.quantity_delta))::int AS stock_units,
           SUM(CASE WHEN im.movement_type = 'purchase' AND im.happened_at >= NOW() - INTERVAL '30 days' THEN ABS(im.quantity_delta) ELSE 0 END)::numeric AS purchases_30d,
           SUM(CASE WHEN im.movement_type = 'sale' AND im.happened_at >= NOW() - INTERVAL '30 days' THEN ABS(im.quantity_delta) ELSE 0 END)::numeric AS sales_30d,
           COUNT(*) FILTER (
             WHERE im.movement_type = 'purchase'
               AND im.happened_at >= NOW() - INTERVAL '14 days'
               AND ABS(im.quantity_delta) >= 10
           )::int AS repeated_accumulation_count,
           ROUND(
             GREATEST(0, SUM(im.quantity_delta)) / NULLIF((SUM(CASE WHEN im.movement_type = 'sale' AND im.happened_at >= NOW() - INTERVAL '30 days' THEN ABS(im.quantity_delta) ELSE 0 END) / 30.0), 0),
             2
           ) AS days_of_stock,
           COALESCE(dr.demand_bucket, 5) AS demand_bucket
         FROM inventory_movements im
         JOIN pharmacies p ON p.id = im.pharmacy_id
         LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
         LEFT JOIN demand_rank dr ON dr.barcode = im.barcode
         WHERE im.deleted_at IS NULL
           AND ($1 = '' OR p.name ILIKE $2 OR p.license_number ILIKE $2)
           AND ($3 = '' OR im.barcode ILIKE $4 OR mr.trade_name ILIKE $4)
           AND ($5 = '' OR p.region ILIKE $6)
           AND ($7::timestamptz IS NULL OR im.happened_at >= $7::timestamptz)
           AND ($8::timestamptz IS NULL OR im.happened_at <= $8::timestamptz)
         GROUP BY p.id, p.name, p.region, im.barcode, mr.trade_name, dr.demand_bucket
       ), tagged AS (
         SELECT
           sr.*,
           CASE
             WHEN sr.days_of_stock > $9 THEN 'high_days_of_stock'
             WHEN sr.repeated_accumulation_count >= 3 AND sr.sales_30d <= 5 THEN 'repeated_accumulation_low_sales'
             WHEN sr.purchases_30d > (sr.sales_30d * $10) AND sr.purchases_30d >= 20 THEN 'purchase_outpaces_dispensing'
             WHEN sr.demand_bucket = 1 AND sr.days_of_stock > 45 AND sr.sales_30d < (sr.purchases_30d * 0.35) THEN 'suspicious_retention_high_demand'
             ELSE 'normal'
           END AS alert_type
         FROM stock_rules sr
       )
       SELECT *, COUNT(*) OVER()::int AS total_count
       FROM tagged
       WHERE alert_type <> 'normal'
         AND ($11 = '' OR alert_type = $11)
       ORDER BY ${sort.sortColumn} ${sort.sortDir} NULLS LAST
       LIMIT $12 OFFSET $13`,
      [
        filters.pharmacy,
        `%${filters.pharmacy}%`,
        filters.medicine,
        `%${filters.medicine}%`,
        filters.region,
        `%${filters.region}%`,
        filters.from ? filters.from.toISOString() : null,
        filters.to ? filters.to.toISOString() : null,
        daysOfStockCritical,
        purchaseToSalesFactor,
        filters.status,
        pageSize,
        offset,
      ]
    );

    const total = result.rows[0]?.total_count || 0;
    res.json({
      status: 'success',
      data: result.rows,
      pagination: {
        page,
        pageSize,
        total,
        totalPages: Math.max(1, Math.ceil(total / pageSize)),
      },
      rules: {
        daysOfStockCritical,
        purchaseToSalesFactor,
      },
      meta: buildListMeta({
        filters,
        sortBy: sort.sortBy,
        sortDir: sort.sortDir,
        count: result.rows.length,
      }),
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/sync-health', async (req, res) => {
  const region = String(req.query.region || '').trim();
  const status = String(req.query.status || '').trim();
  const syncOverdueHours = toInt(req.query.syncOverdueHours, 12);
  const { page, pageSize, offset } = parsePagination(req);
  const sort = parseSort(
    req,
    {
      hours_since_sync: 'hours_since_sync',
      pharmacy_name: 'pharmacy_name',
      pending_outbox: 'pending_outbox',
    },
    'hours_since_sync'
  );

  try {
    const result = await db.query(
      `WITH health AS (
         SELECT
           p.id AS pharmacy_id,
           p.name AS pharmacy_name,
           p.license_number,
           p.hwid,
           p.region,
           p.status AS pharmacy_status,
           s.last_sync_up,
           s.last_sync_down,
           CASE WHEN s.last_sync_up IS NULL THEN NULL
                ELSE EXTRACT(EPOCH FROM (NOW() - s.last_sync_up)) / 3600.0
           END AS hours_since_sync,
           COALESCE(o.pending_outbox, 0)::int AS pending_outbox,
           COALESCE(a.open_alerts, 0)::int AS open_alerts,
           CASE
             WHEN s.last_sync_up IS NULL THEN 'never_synced'
             WHEN s.last_sync_up < NOW() - make_interval(hours => $1) THEN 'overdue_sync'
             WHEN p.status <> 'online' THEN 'offline'
             WHEN COALESCE(o.pending_outbox, 0) >= 20 THEN 'queue_backlog'
             ELSE 'healthy'
           END AS health_status
         FROM pharmacies p
         LEFT JOIN pos_sync_state s ON s.pharmacy_id = p.id
         LEFT JOIN (
           SELECT pharmacy_id, COUNT(*) AS pending_outbox
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
         WHERE ($2 = '' OR p.region ILIKE $3)
       )
       SELECT *, COUNT(*) OVER()::int AS total_count FROM (
         SELECT * FROM health WHERE ($4 = '' OR health_status = $4)
       ) f
       ORDER BY ${sort.sortColumn} ${sort.sortDir} NULLS LAST
       LIMIT $5 OFFSET $6`,
      [syncOverdueHours, region, `%${region}%`, status, pageSize, offset]
    );

    const total = result.rows[0]?.total_count || 0;
    res.json({
      status: 'success',
      data: result.rows,
      pagination: {
        page,
        pageSize,
        total,
        totalPages: Math.max(1, Math.ceil(total / pageSize)),
      },
      rules: { syncOverdueHours },
      meta: buildListMeta({
        filters: { region, status },
        sortBy: sort.sortBy,
        sortDir: sort.sortDir,
        count: result.rows.length,
      }),
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/medicine-history', async (req, res) => {
  const medicine = String(req.query.medicine || '').trim();
  if (!medicine) {
    return res.status(400).json({ error: 'medicine query is required (barcode or name)' });
  }

  const { page, pageSize, offset } = parsePagination(req);
  const sort = parseSort(
    req,
    {
      event_time: 'event_time',
      medicine_name: 'medicine_name',
      pharmacy_name: 'pharmacy_name',
    },
    'event_time'
  );

  try {
    const result = await db.query(
      `WITH medicine_rows AS (
         SELECT
           'movement'::text AS source,
           im.event_uuid::text AS row_id,
           im.barcode,
           COALESCE(mr.trade_name, im.barcode) AS medicine_name,
           p.name AS pharmacy_name,
           p.region,
           im.movement_type AS event_type,
           im.quantity_delta,
           im.unit_price_minor,
           im.happened_at AS event_time,
           im.metadata
         FROM inventory_movements im
         JOIN pharmacies p ON p.id = im.pharmacy_id
         LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
         WHERE im.deleted_at IS NULL
           AND (
             im.barcode ILIKE $1
             OR mr.trade_name ILIKE $1
           )

         UNION ALL

         SELECT
           'price_history'::text AS source,
           ph.history_uuid::text AS row_id,
           ph.barcode,
           COALESCE(mr.trade_name, ph.barcode) AS medicine_name,
           p.name AS pharmacy_name,
           p.region,
           'price_change'::text AS event_type,
           NULL::int AS quantity_delta,
           ph.new_price_minor AS unit_price_minor,
           ph.changed_at AS event_time,
           ph.metadata
         FROM price_history ph
         LEFT JOIN pharmacies p ON p.id = ph.pharmacy_id
         LEFT JOIN moph_registry mr ON mr.barcode = ph.barcode
         WHERE ph.barcode ILIKE $1
            OR mr.trade_name ILIKE $1
       ), counted AS (
         SELECT
           mr.*, 
           COUNT(*) OVER()::int AS total_count
         FROM medicine_rows mr
       )
       SELECT *
       FROM counted
       ORDER BY ${sort.sortColumn} ${sort.sortDir}
       LIMIT $2 OFFSET $3`,
      [`%${medicine}%`, pageSize, offset]
    );

    const total = result.rows[0]?.total_count || 0;

    res.json({
      status: 'success',
      data: result.rows,
      pagination: {
        page,
        pageSize,
        total,
        totalPages: Math.max(1, Math.ceil(total / pageSize)),
      },
      meta: buildListMeta({
        filters: { medicine },
        sortBy: sort.sortBy,
        sortDir: sort.sortDir,
        count: result.rows.length,
      }),
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/audit-feed', async (req, res) => {
  const filters = parseAuditFilters(req, { defaultIncludeSystem: false });
  const { page, pageSize, offset } = parsePagination(req);
  const sort = parseAuditSort(req);

  try {
    const result = await queryAuditFeed({
      filters,
      page,
      pageSize,
      offset,
      sort,
    });

    const rows = result.rows;
    res.json({
      status: 'success',
      data: rows,
      pagination: result.pagination,
      meta: buildListMeta({
        filters,
        sortBy: sort.sortBy,
        sortDir: sort.sortDir,
        count: rows.length,
      }),
      scope: {
        default_view_policy: 'business_and_compliance_events',
        system_events_visible: filters.includeSystem,
      },
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/pharmacy-audit', async (req, res) => {
  const filters = parseAuditFilters(req, { defaultIncludeSystem: false });
  const { page, pageSize, offset } = parsePagination(req);
  const sort = parseAuditSort(req);

  try {
    const result = await queryAuditFeed({
      filters,
      page,
      pageSize,
      offset,
      sort,
    });

    const rows = result.rows.filter((row) => row.event_family !== 'sync_governance' || filters.includeSystem);
    res.json({
      status: 'success',
      data: rows,
      pagination: result.pagination,
      meta: buildListMeta({
        filters,
        sortBy: sort.sortBy,
        sortDir: sort.sortDir,
        count: rows.length,
      }),
      scope: {
        branch_forensic_focus: true,
        system_events_visible: filters.includeSystem,
      },
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/price-history', async (req, res) => {
  const filters = parseCommonFilters(req);
  const { page, pageSize, offset } = parsePagination(req);
  const jumpWindowDays = toInt(req.query.jumpWindowDays, 7);
  const jumpThresholdPct = toNumber(req.query.jumpThresholdPct, 0.25);
  const sort = parseSort(
    req,
    {
      changed_at: 'changed_at',
      change_pct: 'change_pct',
      pharmacy_name: 'pharmacy_name',
    },
    'changed_at'
  );

  try {
    const result = await db.query(
      `WITH price_history_events AS (
         SELECT
           ph.history_uuid::text AS event_id,
           'price_history'::text AS source_family,
           CASE
             WHEN ph.source IN ('web', 'admin') THEN 'registry_update'
             WHEN ph.source = 'pos' THEN 'branch_price_edit'
             ELSE 'branch_price_edit'
           END AS event_type,
           CASE
             WHEN ph.source IN ('web', 'admin') THEN 'Government registry update'
             WHEN ph.source = 'pos' THEN 'Branch price edit'
             ELSE 'Recorded price change'
           END AS source_label,
           p.id AS pharmacy_id,
           COALESCE(p.name, 'MoPH Registry') AS pharmacy_name,
           p.license_number,
           p.hwid,
           p.region,
           ph.barcode,
           COALESCE(mr.trade_name, ph.barcode) AS medicine_name,
           ph.previous_price_minor,
           ph.new_price_minor,
           ph.currency_code,
           ph.source,
           ph.changed_by,
           ph.changed_at AS changed_at,
           ph.metadata,
           (mr.moph_ceiling * 100)::numeric AS regulated_price_minor,
           CASE
             WHEN ph.previous_price_minor IS NULL OR ph.previous_price_minor = 0 THEN NULL
             ELSE ROUND(((ph.new_price_minor - ph.previous_price_minor)::numeric / NULLIF(ph.previous_price_minor, 0)), 4)
           END AS change_pct,
           CASE
             WHEN mr.moph_ceiling IS NOT NULL AND ph.new_price_minor > (mr.moph_ceiling * 100) THEN 'high_price'
             ELSE 'ok'
           END AS status,
           CASE
             WHEN ph.previous_price_minor IS NOT NULL
              AND ph.previous_price_minor <> 0
              AND ABS((ph.new_price_minor - ph.previous_price_minor)::numeric / NULLIF(ph.previous_price_minor, 0)) >= $9
             THEN true
             ELSE false
           END AS suspicious_jump,
           false AS is_system_event,
           1::int AS source_rank
         FROM price_history ph
         LEFT JOIN pharmacies p ON p.id = ph.pharmacy_id
         LEFT JOIN moph_registry mr ON mr.barcode = ph.barcode
         WHERE ($1 = '' OR p.name ILIKE $2 OR p.license_number ILIKE $2)
           AND ($3 = '' OR ph.barcode ILIKE $4 OR mr.trade_name ILIKE $4)
           AND ($5 = '' OR p.region ILIKE $6)
           AND ($7::timestamptz IS NULL OR ph.changed_at >= $7::timestamptz)
           AND ($8::timestamptz IS NULL OR ph.changed_at <= $8::timestamptz)
       ), inventory_price_events AS (
         SELECT
           im.event_uuid::text AS event_id,
           'inventory_movements'::text AS source_family,
           'branch_price_edit'::text AS event_type,
           CASE
             WHEN COALESCE(NULLIF(im.source, ''), NULLIF(im.metadata->>'source', '')) IN ('web', 'admin') THEN 'Government pricing sync applied'
             ELSE 'POS price change'
           END AS source_label,
           p.id AS pharmacy_id,
           COALESCE(p.name, 'Unknown pharmacy') AS pharmacy_name,
           p.license_number,
           p.hwid,
           p.region,
           im.barcode,
           COALESCE(mr.trade_name, im.barcode) AS medicine_name,
           LAG(im.unit_price_minor) OVER (PARTITION BY im.pharmacy_id, im.barcode ORDER BY im.happened_at, im.id) AS previous_price_minor,
           im.unit_price_minor::numeric AS new_price_minor,
           NULL::varchar AS currency_code,
           COALESCE(NULLIF(im.source, ''), NULLIF(im.metadata->>'source', ''), 'pos') AS source,
           NULLIF(im.metadata->>'changed_by', '') AS changed_by,
           im.happened_at AS changed_at,
           COALESCE(im.metadata, '{}'::jsonb) AS metadata,
           (mr.moph_ceiling * 100)::numeric AS regulated_price_minor,
           NULL::numeric AS change_pct,
           CASE
             WHEN mr.moph_ceiling IS NOT NULL AND im.unit_price_minor > (mr.moph_ceiling * 100) THEN 'high_price'
             ELSE 'ok'
           END AS status,
           false AS suspicious_jump,
           false AS is_system_event,
           2::int AS source_rank
         FROM inventory_movements im
         JOIN pharmacies p ON p.id = im.pharmacy_id
         LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
         WHERE im.deleted_at IS NULL
           AND im.movement_type = 'price_change'
           AND im.unit_price_minor IS NOT NULL
           AND ($1 = '' OR p.name ILIKE $2 OR p.license_number ILIKE $2)
           AND ($3 = '' OR im.barcode ILIKE $4 OR mr.trade_name ILIKE $4)
           AND ($5 = '' OR p.region ILIKE $6)
           AND ($7::timestamptz IS NULL OR im.happened_at >= $7::timestamptz)
           AND ($8::timestamptz IS NULL OR im.happened_at <= $8::timestamptz)
       ), registry_price_events AS (
         SELECT
           CONCAT('change_log:', cl.id)::text AS event_id,
           'registry_update'::text AS source_family,
           'registry_update'::text AS event_type,
           'Government registry update'::text AS source_label,
           NULL::int AS pharmacy_id,
           'MoPH Registry'::text AS pharmacy_name,
           NULL::text AS license_number,
           NULL::text AS hwid,
           'National'::text AS region,
           mr.barcode,
           COALESCE(mr.trade_name, mr.barcode) AS medicine_name,
           CASE
             WHEN NULLIF(cl.old_value->>'price', '') IS NULL THEN NULL
             ELSE ((cl.old_value->>'price')::numeric * 100.0)
           END AS previous_price_minor,
           CASE
             WHEN NULLIF(cl.new_value->>'price', '') IS NULL THEN NULL
             ELSE ((cl.new_value->>'price')::numeric * 100.0)
           END AS new_price_minor,
           NULL::varchar AS currency_code,
           COALESCE(NULLIF(cl.changed_by, ''), 'admin') AS source,
           cl.changed_by,
           cl.created_at AS changed_at,
           COALESCE(cl.new_value, '{}'::jsonb) || COALESCE(cl.old_value, '{}'::jsonb) AS metadata,
           (mr.moph_ceiling * 100)::numeric AS regulated_price_minor,
           CASE
             WHEN NULLIF(cl.old_value->>'price', '') IS NULL OR (cl.old_value->>'price')::numeric = 0 THEN NULL
             ELSE ROUND((((cl.new_value->>'price')::numeric - (cl.old_value->>'price')::numeric) / NULLIF((cl.old_value->>'price')::numeric, 0))::numeric, 4)
           END AS change_pct,
           CASE
             WHEN mr.moph_ceiling IS NOT NULL AND ((cl.new_value->>'price')::numeric * 100.0) > (mr.moph_ceiling * 100) THEN 'high_price'
             ELSE 'ok'
           END AS status,
           CASE
             WHEN NULLIF(cl.old_value->>'price', '') IS NOT NULL
              AND ABS(((cl.new_value->>'price')::numeric - (cl.old_value->>'price')::numeric) / NULLIF((cl.old_value->>'price')::numeric, 0)) >= $9
             THEN true
             ELSE false
           END AS suspicious_jump,
           false AS is_system_event,
           3::int AS source_rank
         FROM change_log cl
         JOIN moph_registry mr ON mr.id = cl.entity_id
         WHERE cl.change_type = 'price_update'
           AND cl.entity_type = 'medication'
       ), all_events AS (
         SELECT * FROM price_history_events
         UNION ALL
         SELECT * FROM inventory_price_events
         UNION ALL
         SELECT * FROM registry_price_events
       ), ranked AS (
         SELECT
           ae.*,
           ROW_NUMBER() OVER (
             PARTITION BY ae.source_family, ae.event_id
             ORDER BY ae.source_rank ASC, ae.changed_at DESC
           ) AS row_rank
         FROM all_events ae
       ), filtered AS (
         SELECT *, COUNT(*) OVER()::int AS total_count
         FROM ranked
         WHERE row_rank = 1
           AND ($10 = '' OR status = $10)
       )
       SELECT *
       FROM filtered
       ORDER BY ${sort.sortColumn} ${sort.sortDir} NULLS LAST
       LIMIT $11 OFFSET $12`,
      [
        filters.pharmacy,
        `%${filters.pharmacy}%`,
        filters.medicine,
        `%${filters.medicine}%`,
        filters.region,
        `%${filters.region}%`,
        filters.from ? filters.from.toISOString() : null,
        filters.to ? filters.to.toISOString() : null,
        jumpThresholdPct,
        filters.status,
        pageSize,
        offset,
      ]
    );

    const total = result.rows[0]?.total_count || 0;
    res.json({
      status: 'success',
      data: result.rows,
      pagination: {
        page,
        pageSize,
        total,
        totalPages: Math.max(1, Math.ceil(total / pageSize)),
      },
      rules: {
        jumpWindowDays,
        jumpThresholdPct,
      },
      meta: buildListMeta({
        filters,
        sortBy: sort.sortBy,
        sortDir: sort.sortDir,
        count: result.rows.length,
      }),
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/alerts', async (req, res) => {
  const filters = parseCommonFilters(req);
  const { page, pageSize, offset } = parsePagination(req);
  const markupThreshold = toNumber(req.query.markupThreshold, 0.15);
  const jumpWindowDays = toInt(req.query.jumpWindowDays, 7);
  const jumpThresholdPct = toNumber(req.query.jumpThresholdPct, 0.25);
  const daysOfStockCritical = toInt(req.query.daysOfStockCritical, 60);
  const allowedSortFields = new Set(['created_at', 'updated_at', 'severity', 'status', 'alert_type', 'source']);
  const requestedSortBy = String(req.query.sortBy || 'created_at').trim();
  const alertSortBy = allowedSortFields.has(requestedSortBy) ? requestedSortBy : 'created_at';
  const alertSortDir = String(req.query.sortDir || 'desc').toLowerCase() === 'asc' ? 1 : -1;

  try {
    const [compliance, highPrice, hoarding, sharpJumps] = await Promise.all([
      db.query(
        `SELECT
           'compliance'::text AS source,
           alert_uuid::text AS source_id,
           pharmacy_id,
           barcode,
           alert_type,
           severity,
           title,
           details,
           status,
           created_at,
           updated_at
         FROM compliance_alerts
         WHERE deleted_at IS NULL
           AND status = 'open'`
      ),
      db.query(
        `WITH latest_price_events AS (
           SELECT
             ph.pharmacy_id,
             ph.barcode,
             ph.new_price_minor::numeric AS local_price_minor,
             ph.changed_at AS event_time
           FROM price_history ph
           WHERE ph.new_price_minor IS NOT NULL

           UNION ALL

           SELECT
             im.pharmacy_id,
             im.barcode,
             im.unit_price_minor::numeric AS local_price_minor,
             im.happened_at AS event_time
           FROM inventory_movements im
           WHERE im.deleted_at IS NULL
             AND im.movement_type = 'price_change'
             AND im.unit_price_minor IS NOT NULL
         ), latest_local_price AS (
           SELECT DISTINCT ON (lpe.pharmacy_id, lpe.barcode)
             lpe.pharmacy_id,
             lpe.barcode,
             lpe.local_price_minor
           FROM latest_price_events lpe
           ORDER BY lpe.pharmacy_id, lpe.barcode, lpe.event_time DESC
         ), canonical_price_fallback AS (
           SELECT
             pr.barcode,
             pr.local_price_minor::numeric AS local_price_minor
           FROM prices pr
           WHERE pr.deleted_at IS NULL
             AND pr.local_price_minor IS NOT NULL
         ), pricing_sales AS (
           SELECT
             im.pharmacy_id,
             im.barcode,
             AVG(im.unit_price_minor)::numeric AS avg_selling_price_minor,
             MAX((mr.moph_ceiling * 100)::numeric) AS regulated_price_minor,
             MAX(im.happened_at) AS created_at
           FROM inventory_movements im
           LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
           WHERE im.deleted_at IS NULL
             AND im.movement_type = 'sale'
             AND im.happened_at >= NOW() - INTERVAL '30 days'
           GROUP BY im.pharmacy_id, im.barcode
         ), pricing AS (
           SELECT
             ps.pharmacy_id,
             ps.barcode,
             COALESCE(llp.local_price_minor, cpf.local_price_minor, ps.avg_selling_price_minor) AS avg_selling_price_minor,
             ps.regulated_price_minor,
             ps.created_at
           FROM pricing_sales ps
           LEFT JOIN latest_local_price llp
               ON llp.pharmacy_id = ps.pharmacy_id
              AND llp.barcode = ps.barcode
           LEFT JOIN canonical_price_fallback cpf
             ON cpf.barcode = ps.barcode
         )
         SELECT
           'derived'::text AS source,
           CONCAT('high-price-', pharmacy_id, '-', barcode) AS source_id,
           pharmacy_id,
           barcode,
           'high_price'::text AS alert_type,
           'high'::text AS severity,
           'Actual selling price exceeds regulated threshold'::text AS title,
           jsonb_build_object(
             'avg_selling_price_minor', avg_selling_price_minor,
             'regulated_price_minor', regulated_price_minor,
             'markup_pct', ROUND(((avg_selling_price_minor - regulated_price_minor) / NULLIF(regulated_price_minor, 0))::numeric, 4)
           ) AS details,
           'open'::text AS status,
           created_at,
           created_at AS updated_at
         FROM pricing
         WHERE regulated_price_minor IS NOT NULL
           AND avg_selling_price_minor IS NOT NULL
           AND (
             avg_selling_price_minor > regulated_price_minor
             OR ((avg_selling_price_minor - regulated_price_minor) / NULLIF(regulated_price_minor, 0)) > $1
           )`
      , [markupThreshold]),
      db.query(
        `WITH stock_rules AS (
           SELECT
             im.pharmacy_id,
             im.barcode,
             GREATEST(0, SUM(im.quantity_delta))::numeric AS stock_units,
             SUM(CASE WHEN im.movement_type='sale' AND im.happened_at >= NOW() - INTERVAL '30 days' THEN ABS(im.quantity_delta) ELSE 0 END)::numeric AS sales_30d,
             MAX(im.happened_at) AS created_at
           FROM inventory_movements im
           WHERE im.deleted_at IS NULL
           GROUP BY im.pharmacy_id, im.barcode
         )
         SELECT
           'derived'::text AS source,
           CONCAT('hoarding-', pharmacy_id, '-', barcode) AS source_id,
           pharmacy_id,
           barcode,
           'hoarding_risk'::text AS alert_type,
           'critical'::text AS severity,
           'Possible hoarding / stock accumulation pattern'::text AS title,
           jsonb_build_object(
             'stock_units', stock_units,
             'sales_30d', sales_30d,
             'days_of_stock', ROUND(stock_units / NULLIF(sales_30d / 30.0, 0), 2)
           ) AS details,
           'open'::text AS status,
           created_at,
           created_at AS updated_at
         FROM stock_rules
         WHERE (sales_30d <= 5 AND stock_units >= 10)
            OR (stock_units / NULLIF(sales_30d / 30.0, 0)) > $1`
      , [daysOfStockCritical]),
      db.query(
        `WITH jumps AS (
           SELECT
             ph.pharmacy_id,
             ph.barcode,
             ph.changed_at,
             ph.new_price_minor,
             LAG(ph.new_price_minor) OVER (PARTITION BY ph.pharmacy_id, ph.barcode ORDER BY ph.changed_at) AS prev_price_minor,
             LAG(ph.changed_at) OVER (PARTITION BY ph.pharmacy_id, ph.barcode ORDER BY ph.changed_at) AS prev_changed_at
           FROM price_history ph
         )
         SELECT
           'derived'::text AS source,
           CONCAT('price-jump-', pharmacy_id, '-', barcode, '-', EXTRACT(EPOCH FROM changed_at)::bigint) AS source_id,
           pharmacy_id,
           barcode,
           'sharp_price_jump'::text AS alert_type,
           'high'::text AS severity,
           'Sharp price jump in short period'::text AS title,
           jsonb_build_object(
             'new_price_minor', new_price_minor,
             'prev_price_minor', prev_price_minor,
             'jump_pct', ROUND(((new_price_minor - prev_price_minor)::numeric / NULLIF(prev_price_minor, 0)), 4),
             'window_days', $1::int
           ) AS details,
           'open'::text AS status,
           changed_at AS created_at,
           changed_at AS updated_at
         FROM jumps
         WHERE prev_price_minor IS NOT NULL
           AND changed_at - prev_changed_at <= make_interval(days => $1::int)
           AND ABS((new_price_minor - prev_price_minor)::numeric / NULLIF(prev_price_minor, 0)) >= $2::numeric`
      , [jumpWindowDays, jumpThresholdPct]),
    ]);

    const allAlerts = [...compliance.rows, ...highPrice.rows, ...hoarding.rows, ...sharpJumps.rows]
      .map((row) => {
        const normalizedCreatedAt = toIsoString(row.created_at);
        const normalizedUpdatedAt = toIsoString(row.updated_at);
        const alert = {
          source: row.source,
          source_id: row.source_id,
          pharmacy_id: row.pharmacy_id,
          barcode: row.barcode,
          alert_type: row.alert_type,
          severity: row.severity,
          title: row.title,
          details: row.details && typeof row.details === 'object' ? row.details : {},
          status: row.status,
          created_at: normalizedCreatedAt,
          updated_at: normalizedUpdatedAt,
        };

        return {
          ...alert,
          alert_id: encodeAlertId(alert),
          alert_uuid: row.alert_uuid || row.source_id,
          id: encodeAlertId(alert),
        };
      })
      .filter((row) => {
        if (filters.status && row.status !== filters.status) return false;
        if (filters.medicine && !(String(row.barcode || '').toLowerCase().includes(filters.medicine.toLowerCase()))) return false;
        return true;
      })
      .sort((a, b) => {
        const av = a[alertSortBy];
        const bv = b[alertSortBy];
        if (alertSortBy === 'created_at' || alertSortBy === 'updated_at') {
          return (new Date(av).getTime() - new Date(bv).getTime()) * alertSortDir;
        }
        if (typeof av === 'number' && typeof bv === 'number') {
          return (av - bv) * alertSortDir;
        }
        return String(av || '').localeCompare(String(bv || '')) * alertSortDir;
      });

    const paged = allAlerts.slice(offset, offset + pageSize);

    res.json({
      status: 'success',
      data: paged,
      pagination: {
        page,
        pageSize,
        total: allAlerts.length,
        totalPages: Math.max(1, Math.ceil(allAlerts.length / pageSize)),
      },
      meta: buildListMeta({
        filters,
        sortBy: alertSortBy,
        sortDir: alertSortDir === 1 ? 'asc' : 'desc',
        count: paged.length,
      }),
      rules: {
        markupThreshold,
        jumpWindowDays,
        jumpThresholdPct,
        daysOfStockCritical,
      },
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/alerts/:alertId', async (req, res) => {
  const rawAlertId = String(req.params.alertId || '').trim();
  if (!rawAlertId || rawAlertId === 'undefined' || rawAlertId === 'null') {
    return res.status(400).json({ error: 'invalid alert id' });
  }

  let decoded = decodeAlertId(rawAlertId);
  if (!decoded) {
    // Backward-compatible fallback for legacy selector values (source_id/barcode),
    // while preserving direct compliance UUID selection compatibility.
    decoded = looksLikeUuid(rawAlertId)
      ? { source: 'compliance', source_id: rawAlertId }
      : { source: 'legacy', source_id: rawAlertId };
  }

  if (decoded.source === 'compliance') {
    const sourceId = String(decoded.source_id || decoded.alert_uuid || decoded.id || '').trim();
    if (!sourceId) {
      return res.status(400).json({ error: 'invalid alert id' });
    }

    try {
      const result = await db.query(
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
           updated_at
         FROM compliance_alerts
         WHERE alert_uuid::text = $1::text
         LIMIT 1`,
        [sourceId]
      );

      if (!result.rows.length) {
        return res.status(404).json({ error: 'alert not found' });
      }

      const row = result.rows[0];
      const normalized = {
        source: 'compliance',
        source_id: row.alert_uuid,
        alert_id: req.params.alertId,
        alert_uuid: row.alert_uuid,
        id: req.params.alertId,
        pharmacy_id: row.pharmacy_id,
        device_id: row.device_id,
        barcode: row.barcode,
        alert_type: row.alert_type,
        severity: row.severity,
        title: row.title,
        details: row.details && typeof row.details === 'object' ? row.details : {},
        status: row.status,
        created_at: toIsoString(row.created_at),
        updated_at: toIsoString(row.updated_at),
      };

      return res.json({ status: 'success', data: normalized });
    } catch {
      return res.status(500).json({ error: 'failed to fetch alert details' });
    }
  }

  const sourceId = String(decoded.source_id || decoded.alert_uuid || decoded.id || '').trim();
  if (!sourceId) {
    return res.status(400).json({ error: 'invalid alert id' });
  }
  const allowBarcodeFallback = decoded.source === 'legacy';

  try {
    // Resolve non-compliance and legacy identifiers by deriving the live alert row.
    const markupThreshold = 0.15;
    const daysOfStockCritical = 60;
    const jumpWindowDays = 7;
    const jumpThresholdPct = 0.25;

    const result = await db.query(
      `WITH latest_price_events AS (
         SELECT
           ph.pharmacy_id,
           ph.barcode,
           ph.new_price_minor::numeric AS local_price_minor,
           ph.changed_at AS event_time
         FROM price_history ph
         WHERE ph.new_price_minor IS NOT NULL

         UNION ALL

         SELECT
           im.pharmacy_id,
           im.barcode,
           im.unit_price_minor::numeric AS local_price_minor,
           im.happened_at AS event_time
         FROM inventory_movements im
         WHERE im.deleted_at IS NULL
           AND im.movement_type = 'price_change'
           AND im.unit_price_minor IS NOT NULL
       ), latest_local_price AS (
         SELECT DISTINCT ON (lpe.pharmacy_id, lpe.barcode)
           lpe.pharmacy_id,
           lpe.barcode,
           lpe.local_price_minor
         FROM latest_price_events lpe
         ORDER BY lpe.pharmacy_id, lpe.barcode, lpe.event_time DESC
       ), canonical_price_fallback AS (
         SELECT
           pr.barcode,
           pr.local_price_minor::numeric AS local_price_minor
         FROM prices pr
         WHERE pr.deleted_at IS NULL
           AND pr.local_price_minor IS NOT NULL
       ), pricing_sales AS (
         SELECT
           im.pharmacy_id,
           im.barcode,
           AVG(im.unit_price_minor)::numeric AS avg_selling_price_minor,
           MAX((mr.moph_ceiling * 100)::numeric) AS regulated_price_minor,
           MAX(im.happened_at) AS created_at
         FROM inventory_movements im
         LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
         WHERE im.deleted_at IS NULL
           AND im.movement_type = 'sale'
           AND im.happened_at >= NOW() - INTERVAL '30 days'
         GROUP BY im.pharmacy_id, im.barcode
       ), pricing AS (
         SELECT
           ps.pharmacy_id,
           ps.barcode,
           COALESCE(llp.local_price_minor, cpf.local_price_minor, ps.avg_selling_price_minor) AS avg_selling_price_minor,
           ps.regulated_price_minor,
           ps.created_at
         FROM pricing_sales ps
         LEFT JOIN latest_local_price llp
           ON llp.pharmacy_id = ps.pharmacy_id
          AND llp.barcode = ps.barcode
         LEFT JOIN canonical_price_fallback cpf
           ON cpf.barcode = ps.barcode
       ), high_price AS (
         SELECT
           'derived'::text AS source,
           CONCAT('high-price-', pharmacy_id, '-', barcode) AS source_id,
           pharmacy_id,
           barcode,
           'high_price'::text AS alert_type,
           'high'::text AS severity,
           'Actual selling price exceeds regulated threshold'::text AS title,
           jsonb_build_object(
             'avg_selling_price_minor', avg_selling_price_minor,
             'regulated_price_minor', regulated_price_minor,
             'markup_pct', ROUND(((avg_selling_price_minor - regulated_price_minor) / NULLIF(regulated_price_minor, 0))::numeric, 4)
           ) AS details,
           'open'::text AS status,
           created_at,
           created_at AS updated_at
         FROM pricing
         WHERE regulated_price_minor IS NOT NULL
           AND avg_selling_price_minor IS NOT NULL
           AND (
             avg_selling_price_minor > regulated_price_minor
             OR ((avg_selling_price_minor - regulated_price_minor) / NULLIF(regulated_price_minor, 0)) > $2
           )
       ), stock_rules AS (
         SELECT
           im.pharmacy_id,
           im.barcode,
           GREATEST(0, SUM(im.quantity_delta))::numeric AS stock_units,
           SUM(CASE WHEN im.movement_type='sale' AND im.happened_at >= NOW() - INTERVAL '30 days' THEN ABS(im.quantity_delta) ELSE 0 END)::numeric AS sales_30d,
           MAX(im.happened_at) AS created_at
         FROM inventory_movements im
         WHERE im.deleted_at IS NULL
         GROUP BY im.pharmacy_id, im.barcode
       ), hoarding AS (
         SELECT
           'derived'::text AS source,
           CONCAT('hoarding-', pharmacy_id, '-', barcode) AS source_id,
           pharmacy_id,
           barcode,
           'hoarding_risk'::text AS alert_type,
           'critical'::text AS severity,
           'Possible hoarding / stock accumulation pattern'::text AS title,
           jsonb_build_object(
             'stock_units', stock_units,
             'sales_30d', sales_30d,
             'days_of_stock', ROUND(stock_units / NULLIF(sales_30d / 30.0, 0), 2)
           ) AS details,
           'open'::text AS status,
           created_at,
           created_at AS updated_at
         FROM stock_rules
         WHERE (sales_30d <= 5 AND stock_units >= 10)
            OR (stock_units / NULLIF(sales_30d / 30.0, 0)) > $3
       ), jumps AS (
         SELECT
           ph.pharmacy_id,
           ph.barcode,
           ph.changed_at,
           ph.new_price_minor,
           LAG(ph.new_price_minor) OVER (PARTITION BY ph.pharmacy_id, ph.barcode ORDER BY ph.changed_at) AS prev_price_minor,
           LAG(ph.changed_at) OVER (PARTITION BY ph.pharmacy_id, ph.barcode ORDER BY ph.changed_at) AS prev_changed_at
         FROM price_history ph
       ), sharp_jumps AS (
         SELECT
           'derived'::text AS source,
           CONCAT('price-jump-', pharmacy_id, '-', barcode, '-', EXTRACT(EPOCH FROM changed_at)::bigint) AS source_id,
           pharmacy_id,
           barcode,
           'sharp_price_jump'::text AS alert_type,
           'high'::text AS severity,
           'Sharp price jump in short period'::text AS title,
           jsonb_build_object(
             'new_price_minor', new_price_minor,
             'prev_price_minor', prev_price_minor,
             'jump_pct', ROUND(((new_price_minor - prev_price_minor)::numeric / NULLIF(prev_price_minor, 0)), 4),
             'window_days', $4::int
           ) AS details,
           'open'::text AS status,
           changed_at AS created_at,
           changed_at AS updated_at
         FROM jumps
         WHERE prev_price_minor IS NOT NULL
           AND changed_at - prev_changed_at <= make_interval(days => $4::int)
           AND ABS((new_price_minor - prev_price_minor)::numeric / NULLIF(prev_price_minor, 0)) >= $5::numeric
       ), unioned AS (
         SELECT * FROM high_price
         UNION ALL
         SELECT * FROM hoarding
         UNION ALL
         SELECT * FROM sharp_jumps
       )
       SELECT *
       FROM unioned
       WHERE source_id = $1::text OR ($6::boolean AND barcode = $1::text)
       ORDER BY created_at DESC
       LIMIT 1`,
      [sourceId, markupThreshold, daysOfStockCritical, jumpWindowDays, jumpThresholdPct, allowBarcodeFallback],
    );

    if (!result.rows.length) {
      return res.status(404).json({ error: 'alert not found' });
    }

    const row = result.rows[0];
    const normalized = {
      source: row.source,
      source_id: row.source_id,
      alert_id: encodeAlertId({
        source: row.source,
        source_id: row.source_id,
        pharmacy_id: row.pharmacy_id,
        barcode: row.barcode,
        alert_type: row.alert_type,
        severity: row.severity,
        title: row.title,
        status: row.status,
        created_at: toIsoString(row.created_at),
        updated_at: toIsoString(row.updated_at),
      }),
      alert_uuid: row.source_id,
      id: encodeAlertId({
        source: row.source,
        source_id: row.source_id,
      }),
      pharmacy_id: row.pharmacy_id,
      barcode: row.barcode,
      alert_type: row.alert_type,
      severity: row.severity,
      title: row.title,
      details: row.details && typeof row.details === 'object' ? row.details : {},
      status: row.status,
      created_at: toIsoString(row.created_at),
      updated_at: toIsoString(row.updated_at),
    };

    return res.json({ status: 'success', data: normalized });
  } catch {
    return res.status(500).json({ error: 'failed to fetch alert details' });
  }
});

module.exports = router;
