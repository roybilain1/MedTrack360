BEGIN;

CREATE TABLE IF NOT EXISTS sync_requests (
  id BIGSERIAL PRIMARY KEY,
  request_id VARCHAR(120) NOT NULL UNIQUE,
  pharmacy_id INT NOT NULL REFERENCES pharmacies(id),
  device_id VARCHAR(64) NOT NULL,
  endpoint VARCHAR(120) NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  response_payload JSONB,
  request_status VARCHAR(20) NOT NULL DEFAULT 'processing',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sync_requests_pharmacy_endpoint
  ON sync_requests(pharmacy_id, endpoint, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sync_requests_device_created
  ON sync_requests(device_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_movements_pharmacy_cursor
  ON inventory_movements(pharmacy_id, updated_at ASC, event_uuid ASC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_compliance_alerts_pharmacy_open
  ON compliance_alerts(pharmacy_id, status, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_prices_updated
  ON prices(updated_at DESC)
  WHERE deleted_at IS NULL;

COMMIT;
