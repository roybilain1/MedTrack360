BEGIN;

-- Reconciliation view: event-derived stock vs snapshot stock.
CREATE OR REPLACE VIEW vw_reconcile_stock_event_vs_snapshot AS
WITH event_totals AS (
  SELECT
    im.pharmacy_id,
    im.barcode,
    SUM(im.quantity_delta)::bigint AS event_stock_units,
    MAX(im.updated_at) AS last_event_at
  FROM inventory_movements im
  WHERE im.deleted_at IS NULL
  GROUP BY im.pharmacy_id, im.barcode
), snapshot_mapped AS (
  SELECT
    pm.id AS pharmacy_id,
    ns.barcode,
    SUM(ns.stock_units)::bigint AS snapshot_stock_units,
    MAX(ns.updated_at) AS last_snapshot_at
  FROM national_stock ns
  JOIN LATERAL (
    SELECT p.id
    FROM pharmacies p
    WHERE (ns.license_number IS NOT NULL AND p.license_number = ns.license_number)
       OR (ns.license_number IS NULL AND ns.hwid IS NOT NULL AND p.hwid = ns.hwid)
    ORDER BY CASE WHEN ns.license_number IS NOT NULL AND p.license_number = ns.license_number THEN 0 ELSE 1 END
    LIMIT 1
  ) pm ON TRUE
  GROUP BY pm.id, ns.barcode
)
SELECT
  COALESCE(e.pharmacy_id, s.pharmacy_id) AS pharmacy_id,
  COALESCE(e.barcode, s.barcode) AS barcode,
  COALESCE(e.event_stock_units, 0) AS event_stock_units,
  COALESCE(s.snapshot_stock_units, 0) AS snapshot_stock_units,
  (COALESCE(e.event_stock_units, 0) - COALESCE(s.snapshot_stock_units, 0)) AS stock_delta,
  e.last_event_at,
  s.last_snapshot_at
FROM event_totals e
FULL OUTER JOIN snapshot_mapped s
  ON e.pharmacy_id = s.pharmacy_id
 AND e.barcode = s.barcode;

-- Reconciliation view: current prices and initialization history coverage.
CREATE OR REPLACE VIEW vw_reconcile_price_history_coverage AS
SELECT
  p.barcode,
  p.regulated_price_minor,
  p.local_price_minor,
  p.version AS price_version,
  p.updated_at AS price_updated_at,
  COUNT(ph.id) FILTER (WHERE ph.source = 'backfill_initialization') AS init_history_rows,
  MAX(ph.changed_at) AS last_history_at
FROM prices p
LEFT JOIN price_history ph ON ph.barcode = p.barcode
GROUP BY
  p.barcode,
  p.regulated_price_minor,
  p.local_price_minor,
  p.version,
  p.updated_at;

-- Reconciliation view: checkpoint health by active device.
CREATE OR REPLACE VIEW vw_reconcile_checkpoint_health AS
SELECT
  p.id AS pharmacy_id,
  p.name AS pharmacy_name,
  p.hwid AS device_id,
  MAX(CASE WHEN sc.stream = 'pos_to_server' THEN sc.checkpoint_time END) AS pos_to_server_checkpoint,
  MAX(CASE WHEN sc.stream = 'server_to_pos' THEN sc.checkpoint_time END) AS server_to_pos_checkpoint,
  COALESCE(ps.last_sync_up, NULL) AS last_sync_up,
  COALESCE(ps.last_sync_down, NULL) AS last_sync_down
FROM pharmacies p
LEFT JOIN sync_checkpoint sc ON sc.device_id = p.hwid
LEFT JOIN pos_sync_state ps ON ps.hwid = p.hwid
GROUP BY p.id, p.name, p.hwid, ps.last_sync_up, ps.last_sync_down;

COMMIT;
