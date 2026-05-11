BEGIN;

ALTER TABLE moph_registry
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT false;

ALTER TABLE sales_log
  ADD COLUMN IF NOT EXISTS device_id VARCHAR(64),
  ADD COLUMN IF NOT EXISTS version INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS sync_status VARCHAR(20) DEFAULT 'synced',
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS pos_inventory_movements (
  id BIGSERIAL PRIMARY KEY,
  movement_uuid UUID NOT NULL UNIQUE,
  pharmacy_id INT NOT NULL REFERENCES pharmacies(id),
  device_id VARCHAR(64) NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  barcode VARCHAR(50) NOT NULL,
  movement_type VARCHAR(40) NOT NULL,
  quantity_delta INTEGER NOT NULL DEFAULT 0,
  unit_price_minor BIGINT,
  currency_code VARCHAR(3) NOT NULL DEFAULT 'USD',
  reference_type VARCHAR(40) NOT NULL DEFAULT '',
  reference_id VARCHAR(120) NOT NULL DEFAULT '',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  happened_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  sync_status VARCHAR(20) NOT NULL DEFAULT 'synced',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_moph_blocked ON moph_registry(is_blocked);
CREATE INDEX IF NOT EXISTS idx_sales_log_device ON sales_log(device_id);
CREATE INDEX IF NOT EXISTS idx_sales_log_updated_at ON sales_log(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_pim_pharmacy_happened_at ON pos_inventory_movements(pharmacy_id, happened_at DESC);
CREATE INDEX IF NOT EXISTS idx_pim_barcode ON pos_inventory_movements(barcode);

COMMIT;
