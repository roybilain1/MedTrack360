BEGIN TRANSACTION;

ALTER TABLE inventory ADD COLUMN product_uuid TEXT;
ALTER TABLE inventory ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE inventory ADD COLUMN updated_at INTEGER;
ALTER TABLE inventory ADD COLUMN deleted_at INTEGER;
ALTER TABLE inventory ADD COLUMN is_blocked INTEGER NOT NULL DEFAULT 0;
ALTER TABLE inventory ADD COLUMN server_updated_at INTEGER;

ALTER TABLE purchases ADD COLUMN purchase_uuid TEXT;
ALTER TABLE purchases ADD COLUMN pharmacy_id INTEGER;
ALTER TABLE purchases ADD COLUMN device_id TEXT;
ALTER TABLE purchases ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE purchases ADD COLUMN updated_at INTEGER;
ALTER TABLE purchases ADD COLUMN deleted_at INTEGER;
ALTER TABLE purchases ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending';

ALTER TABLE purchase_items ADD COLUMN line_uuid TEXT;
ALTER TABLE purchase_items ADD COLUMN updated_at INTEGER;
ALTER TABLE purchase_items ADD COLUMN deleted_at INTEGER;

CREATE TABLE IF NOT EXISTS sale_items_cache (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  line_uuid TEXT NOT NULL UNIQUE,
  sale_uuid TEXT NOT NULL,
  receipt_id TEXT NOT NULL,
  barcode TEXT NOT NULL,
  product_name TEXT NOT NULL,
  dosage TEXT NOT NULL DEFAULT '',
  qty INTEGER NOT NULL,
  unit_price_minor INTEGER NOT NULL,
  line_total_minor INTEGER NOT NULL,
  batch_number TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE TABLE IF NOT EXISTS product_batches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  batch_uuid TEXT NOT NULL UNIQUE,
  barcode TEXT NOT NULL,
  batch_number TEXT NOT NULL,
  expiry TEXT NOT NULL DEFAULT '',
  qty_on_hand INTEGER NOT NULL DEFAULT 0,
  unit_cost_minor INTEGER,
  unit_price_minor INTEGER,
  currency_code TEXT NOT NULL DEFAULT 'USD',
  supplier_name TEXT,
  reference_id TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE TABLE IF NOT EXISTS returns (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  return_uuid TEXT NOT NULL UNIQUE,
  barcode TEXT NOT NULL,
  return_type TEXT NOT NULL,
  qty INTEGER NOT NULL,
  unit_price_minor INTEGER,
  reason TEXT,
  reference_id TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  sync_status TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS stock_adjustments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  adjustment_uuid TEXT NOT NULL UNIQUE,
  barcode TEXT NOT NULL,
  quantity_delta INTEGER NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  reference_id TEXT,
  version INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  sync_status TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS prices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  price_uuid TEXT NOT NULL UNIQUE,
  barcode TEXT NOT NULL UNIQUE,
  regulated_price_minor INTEGER,
  local_price_minor INTEGER,
  currency_code TEXT NOT NULL DEFAULT 'USD',
  source TEXT NOT NULL DEFAULT 'server',
  version INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE TABLE IF NOT EXISTS price_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  history_uuid TEXT NOT NULL UNIQUE,
  barcode TEXT NOT NULL,
  previous_price_minor INTEGER,
  new_price_minor INTEGER,
  currency_code TEXT NOT NULL DEFAULT 'USD',
  source TEXT NOT NULL,
  changed_by TEXT,
  changed_at INTEGER NOT NULL,
  metadata TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS compliance_alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  alert_uuid TEXT NOT NULL UNIQUE,
  alert_type TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'medium',
  title TEXT NOT NULL,
  details TEXT NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'open',
  created_at INTEGER NOT NULL,
  acknowledged_at INTEGER,
  resolved_at INTEGER,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE TABLE IF NOT EXISTS sync_outbox (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_uuid TEXT NOT NULL UNIQUE,
  stream TEXT NOT NULL,
  payload TEXT NOT NULL,
  sync_status TEXT NOT NULL DEFAULT 'pending',
  retry_count INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);

CREATE TABLE IF NOT EXISTS sync_checkpoint (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  stream TEXT NOT NULL UNIQUE,
  checkpoint_token TEXT NOT NULL,
  checkpoint_time INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_product_uuid_unique ON inventory(product_uuid) WHERE product_uuid IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_purchases_uuid_unique ON purchases(purchase_uuid) WHERE purchase_uuid IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_purchase_items_line_uuid_unique ON purchase_items(line_uuid) WHERE line_uuid IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_uuid ON sale_items_cache(sale_uuid);
CREATE INDEX IF NOT EXISTS idx_product_batches_barcode ON product_batches(barcode);
CREATE INDEX IF NOT EXISTS idx_returns_sync_status ON returns(sync_status, updated_at);
CREATE INDEX IF NOT EXISTS idx_stock_adjustments_sync_status ON stock_adjustments(sync_status, updated_at);
CREATE INDEX IF NOT EXISTS idx_prices_barcode ON prices(barcode);
CREATE INDEX IF NOT EXISTS idx_price_history_barcode_changed_at ON price_history(barcode, changed_at);
CREATE INDEX IF NOT EXISTS idx_compliance_alerts_status_created_at ON compliance_alerts(status, created_at);
CREATE INDEX IF NOT EXISTS idx_sync_outbox_status ON sync_outbox(sync_status, created_at);

CREATE VIEW IF NOT EXISTS sales AS
SELECT sale_uuid, receipt_id, sale_data, created_at, updated_at, deleted_at, version, sync_status
FROM offline_sale_queue;

CREATE VIEW IF NOT EXISTS sale_items AS
SELECT line_uuid, sale_uuid, receipt_id, barcode, product_name, dosage, qty, unit_price_minor, line_total_minor, batch_number, version, updated_at, deleted_at
FROM sale_items_cache;

CREATE VIEW IF NOT EXISTS medicines AS
SELECT product_uuid AS medicine_uuid, barcode, name AS trade_name, dosage, category, moph_ceiling, is_blocked, version, updated_at, deleted_at
FROM inventory;

COMMIT;
