BEGIN;

CREATE TABLE IF NOT EXISTS audit_change_log (
  id                BIGSERIAL PRIMARY KEY,
  change_uuid       UUID NOT NULL UNIQUE,
  pharmacy_id       INT REFERENCES pharmacies(id),
  entity_type       VARCHAR(50) NOT NULL,
  entity_id         VARCHAR(120) NOT NULL,
  change_type       VARCHAR(50) NOT NULL,
  old_value         JSONB,
  new_value         JSONB,
  actor_identity    VARCHAR(120),
  actor_role        VARCHAR(40),
  device_id         VARCHAR(64),
  source_ip         VARCHAR(80),
  source            VARCHAR(30) NOT NULL DEFAULT 'api',
  request_id        VARCHAR(120),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_audit_change_log_pharmacy_created
  ON audit_change_log(pharmacy_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_audit_change_log_entity
  ON audit_change_log(entity_type, entity_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_change_log_request
  ON audit_change_log(request_id, created_at DESC);

COMMIT;
