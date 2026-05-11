BEGIN TRANSACTION;

ALTER TABLE inventory ADD COLUMN is_blocked INTEGER NOT NULL DEFAULT 0;
ALTER TABLE inventory ADD COLUMN server_updated_at INTEGER;

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

COMMIT;
