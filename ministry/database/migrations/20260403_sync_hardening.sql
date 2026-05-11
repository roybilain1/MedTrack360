BEGIN TRANSACTION;

ALTER TABLE offline_sale_queue ADD COLUMN sale_uuid TEXT;
ALTER TABLE offline_sale_queue ADD COLUMN pharmacy_id INTEGER;
ALTER TABLE offline_sale_queue ADD COLUMN device_id TEXT;
ALTER TABLE offline_sale_queue ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE offline_sale_queue ADD COLUMN updated_at INTEGER;
ALTER TABLE offline_sale_queue ADD COLUMN deleted_at INTEGER;
ALTER TABLE offline_sale_queue ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending';

CREATE TABLE IF NOT EXISTS inventory_movement_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  movement_uuid TEXT NOT NULL UNIQUE,
  pharmacy_id INTEGER,
  device_id TEXT NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  barcode TEXT NOT NULL,
  movement_type TEXT NOT NULL,
  quantity_delta INTEGER NOT NULL,
  unit_price_minor INTEGER,
  currency_code TEXT NOT NULL DEFAULT 'USD',
  reference_type TEXT NOT NULL DEFAULT '',
  reference_id TEXT NOT NULL DEFAULT '',
  metadata TEXT NOT NULL DEFAULT '{}',
  happened_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  sync_status TEXT NOT NULL DEFAULT 'pending',
  synced_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_osq_sync_status ON offline_sale_queue(sync_status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_osq_sale_uuid_unique ON offline_sale_queue(sale_uuid) WHERE sale_uuid IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_imq_sync_status ON inventory_movement_queue(sync_status);
CREATE INDEX IF NOT EXISTS idx_imq_barcode_happened_at ON inventory_movement_queue(barcode, happened_at);

COMMIT;
