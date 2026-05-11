BEGIN TRANSACTION;

-- Create sync tables if they do not already exist.
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

CREATE INDEX IF NOT EXISTS idx_sync_outbox_status ON sync_outbox(sync_status, created_at);

-- Normalize legacy pending statuses (incremental, non-destructive).
UPDATE offline_sale_queue
SET sync_status = CASE WHEN synced = 1 THEN 'synced' ELSE 'pending' END
WHERE sync_status IS NULL OR sync_status = '';

UPDATE inventory_movement_queue
SET sync_status = 'pending'
WHERE sync_status IS NULL OR sync_status = '';

UPDATE inventory_movement_queue
SET version = 1
WHERE version IS NULL OR version < 1;

UPDATE inventory_movement_queue
SET updated_at = happened_at
WHERE updated_at IS NULL OR updated_at = 0;

UPDATE inventory_movement_queue
SET movement_uuid = printf('eeeeeeee-eeee-4eee-8eee-%012x', id)
WHERE movement_uuid IS NULL OR movement_uuid = '';

UPDATE offline_sale_queue
SET sale_uuid = printf('ffffffff-ffff-4fff-8fff-%012x', id)
WHERE sale_uuid IS NULL OR sale_uuid = '';

-- Backfill outbox from pending movement queue.
INSERT OR IGNORE INTO sync_outbox (
  event_uuid,
  stream,
  payload,
  sync_status,
  retry_count,
  last_error,
  created_at,
  updated_at,
  deleted_at
)
SELECT
  movement_uuid,
  'pos_to_server.inventory_movement',
  json_object(
    'movement_uuid', movement_uuid,
    'barcode', barcode,
    'movement_type', movement_type,
    'reference_type', reference_type,
    'reference_id', reference_id,
    'happened_at', happened_at
  ),
  CASE WHEN sync_status = 'synced' THEN 'synced' ELSE 'pending' END,
  0,
  NULL,
  COALESCE(updated_at, happened_at),
  COALESCE(updated_at, happened_at),
  deleted_at
FROM inventory_movement_queue
WHERE sync_status IN ('pending', 'in_progress', 'failed');

-- Backfill outbox from pending offline sales.
INSERT OR IGNORE INTO sync_outbox (
  event_uuid,
  stream,
  payload,
  sync_status,
  retry_count,
  last_error,
  created_at,
  updated_at,
  deleted_at
)
SELECT
  sale_uuid,
  'pos_to_server.sale',
  json_object(
    'sale_uuid', sale_uuid,
    'receipt_id', receipt_id,
    'queue_id', id,
    'created_at', created_at
  ),
  CASE WHEN synced = 1 THEN 'synced' ELSE 'pending' END,
  0,
  NULL,
  created_at,
  COALESCE(updated_at, created_at),
  deleted_at
FROM offline_sale_queue
WHERE synced = 0 OR sync_status IN ('pending', 'in_progress', 'failed');

-- Insert default checkpoints if absent.
INSERT OR IGNORE INTO sync_checkpoint (
  stream,
  checkpoint_token,
  checkpoint_time,
  updated_at
)
VALUES
  ('pos_to_server', 'bootstrap-pos-to-server', 0, CAST(strftime('%s','now') AS INTEGER) * 1000),
  ('server_to_pos', 'bootstrap-server-to-pos', 0, CAST(strftime('%s','now') AS INTEGER) * 1000);

COMMIT;
