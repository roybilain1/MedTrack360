BEGIN;

-- This migration is intentionally additive and idempotent.
-- It does not delete or overwrite production business records.

CREATE TABLE IF NOT EXISTS backfill_unmapped_stock (
  id BIGSERIAL PRIMARY KEY,
  national_stock_id BIGINT NOT NULL,
  barcode VARCHAR(50),
  license_number VARCHAR(50),
  hwid VARCHAR(64),
  stock_units INTEGER,
  reason VARCHAR(120) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (national_stock_id, reason)
);

-- Ensure nullable legacy fields are safely initialized where possible.
UPDATE sales_log
SET version = 1
WHERE version IS NULL OR version < 1;

UPDATE sales_log
SET updated_at = COALESCE(pos_created_at, created_at, NOW())
WHERE updated_at IS NULL;

UPDATE sales_log sl
SET pharmacy_id = p.id
FROM pharmacies p
WHERE sl.pharmacy_id IS NULL
  AND sl.device_id IS NOT NULL
  AND p.hwid = sl.device_id;

UPDATE prices
SET version = 1
WHERE version IS NULL OR version < 1;

UPDATE prices
SET updated_at = NOW()
WHERE updated_at IS NULL;

-- Record unmapped stock rows for manual remediation before canonical event replay.
INSERT INTO backfill_unmapped_stock (
  national_stock_id,
  barcode,
  license_number,
  hwid,
  stock_units,
  reason
)
SELECT
  ns.id,
  ns.barcode,
  ns.license_number,
  ns.hwid,
  ns.stock_units,
  'no_matching_pharmacy'
FROM national_stock ns
LEFT JOIN LATERAL (
  SELECT p.id
  FROM pharmacies p
  WHERE (ns.license_number IS NOT NULL AND p.license_number = ns.license_number)
     OR (ns.license_number IS NULL AND ns.hwid IS NOT NULL AND p.hwid = ns.hwid)
  ORDER BY CASE WHEN ns.license_number IS NOT NULL AND p.license_number = ns.license_number THEN 0 ELSE 1 END
  LIMIT 1
) pm ON TRUE
WHERE COALESCE(ns.stock_units, 0) <> 0
  AND pm.id IS NULL
ON CONFLICT (national_stock_id, reason) DO NOTHING;

-- Backfill inventory_movements from stock snapshots where pharmacy mapping exists.
-- reference_type/reference_id make this operation idempotent and traceable.
WITH mapped_stock AS (
  SELECT
    ns.id AS national_stock_id,
    ns.barcode,
    ns.stock_units,
    COALESCE(ns.updated_at, NOW()) AS happened_at,
    ns.license_number,
    ns.hwid,
    pm.id AS pharmacy_id,
    pm.hwid AS mapped_hwid
  FROM national_stock ns
  JOIN LATERAL (
    SELECT p.id, p.hwid
    FROM pharmacies p
    WHERE (ns.license_number IS NOT NULL AND p.license_number = ns.license_number)
       OR (ns.license_number IS NULL AND ns.hwid IS NOT NULL AND p.hwid = ns.hwid)
    ORDER BY CASE WHEN ns.license_number IS NOT NULL AND p.license_number = ns.license_number THEN 0 ELSE 1 END
    LIMIT 1
  ) pm ON TRUE
  WHERE COALESCE(ns.stock_units, 0) <> 0
)
INSERT INTO inventory_movements (
  event_uuid,
  pharmacy_id,
  device_id,
  source,
  barcode,
  movement_type,
  quantity_delta,
  unit_price_minor,
  currency_code,
  reference_type,
  reference_id,
  metadata,
  happened_at,
  version,
  sync_status,
  updated_at,
  deleted_at
)
SELECT
  (
    substr(md5('stock-snapshot:' || ms.national_stock_id::text || ':' || ms.pharmacy_id::text), 1, 8) || '-' ||
    substr(md5('stock-snapshot:' || ms.national_stock_id::text || ':' || ms.pharmacy_id::text), 9, 4) || '-' ||
    substr(md5('stock-snapshot:' || ms.national_stock_id::text || ':' || ms.pharmacy_id::text), 13, 4) || '-' ||
    substr(md5('stock-snapshot:' || ms.national_stock_id::text || ':' || ms.pharmacy_id::text), 17, 4) || '-' ||
    substr(md5('stock-snapshot:' || ms.national_stock_id::text || ':' || ms.pharmacy_id::text), 21, 12)
  )::uuid AS event_uuid,
  ms.pharmacy_id,
  COALESCE(NULLIF(ms.mapped_hwid, ''), NULLIF(ms.hwid, ''), 'LEGACY-SNAPSHOT') AS device_id,
  'server_backfill' AS source,
  ms.barcode,
  CASE WHEN ms.stock_units >= 0 THEN 'snapshot_opening_balance' ELSE 'snapshot_correction' END AS movement_type,
  ms.stock_units AS quantity_delta,
  NULL AS unit_price_minor,
  'USD' AS currency_code,
  'snapshot_backfill' AS reference_type,
  'national_stock:' || ms.national_stock_id::text AS reference_id,
  jsonb_build_object(
    'backfill_source', 'national_stock',
    'national_stock_id', ms.national_stock_id,
    'license_number', ms.license_number,
    'hwid', ms.hwid
  ) AS metadata,
  ms.happened_at,
  1 AS version,
  'synced' AS sync_status,
  ms.happened_at AS updated_at,
  NULL::timestamptz AS deleted_at
FROM mapped_stock ms
WHERE NOT EXISTS (
  SELECT 1
  FROM inventory_movements im
  WHERE im.reference_type = 'snapshot_backfill'
    AND im.reference_id = 'national_stock:' || ms.national_stock_id::text
);

-- Initialize price_history from current price records when missing.
INSERT INTO price_history (
  history_uuid,
  barcode,
  pharmacy_id,
  previous_price_minor,
  new_price_minor,
  currency_code,
  source,
  changed_by,
  changed_at,
  metadata
)
SELECT
  (
    substr(md5('price-init:' || p.barcode || ':' || COALESCE(p.updated_at::text, 'epoch')), 1, 8) || '-' ||
    substr(md5('price-init:' || p.barcode || ':' || COALESCE(p.updated_at::text, 'epoch')), 9, 4) || '-' ||
    substr(md5('price-init:' || p.barcode || ':' || COALESCE(p.updated_at::text, 'epoch')), 13, 4) || '-' ||
    substr(md5('price-init:' || p.barcode || ':' || COALESCE(p.updated_at::text, 'epoch')), 17, 4) || '-' ||
    substr(md5('price-init:' || p.barcode || ':' || COALESCE(p.updated_at::text, 'epoch')), 21, 12)
  )::uuid AS history_uuid,
  p.barcode,
  NULL::int AS pharmacy_id,
  NULL::bigint AS previous_price_minor,
  COALESCE(p.local_price_minor, p.regulated_price_minor) AS new_price_minor,
  COALESCE(p.currency_code, 'USD') AS currency_code,
  'backfill_initialization' AS source,
  'migration:20260403_event_sync_backfill_safe' AS changed_by,
  COALESCE(p.updated_at, NOW()) AS changed_at,
  jsonb_build_object(
    'regulated_price_minor', p.regulated_price_minor,
    'local_price_minor', p.local_price_minor,
    'price_version', p.version
  ) AS metadata
FROM prices p
WHERE p.deleted_at IS NULL
  AND COALESCE(p.local_price_minor, p.regulated_price_minor) IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM price_history ph
    WHERE ph.barcode = p.barcode
      AND ph.source = 'backfill_initialization'
  );

COMMIT;
