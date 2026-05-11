BEGIN;

ALTER TABLE inventory_movements
  ADD COLUMN IF NOT EXISTS source VARCHAR(30) NOT NULL DEFAULT 'pos';

ALTER TABLE compliance_alerts
  ADD COLUMN IF NOT EXISTS source VARCHAR(30) NOT NULL DEFAULT 'server',
  ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS sync_conflict_log (
  id                BIGSERIAL PRIMARY KEY,
  conflict_uuid     UUID NOT NULL UNIQUE,
  pharmacy_id       INT NOT NULL REFERENCES pharmacies(id),
  device_id         VARCHAR(64),
  entity_type       VARCHAR(50) NOT NULL,
  entity_id         VARCHAR(120) NOT NULL,
  field             VARCHAR(80) NOT NULL,
  conflict_code     VARCHAR(80) NOT NULL,
  local_value       JSONB,
  server_value      JSONB,
  resolution        VARCHAR(40) NOT NULL DEFAULT 'server_override',
  note              TEXT NOT NULL DEFAULT '',
  source            VARCHAR(30) NOT NULL DEFAULT 'server',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_sync_conflict_log_pharmacy_created
  ON sync_conflict_log(pharmacy_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_sync_conflict_log_entity
  ON sync_conflict_log(entity_type, entity_id, created_at DESC);

COMMIT;
