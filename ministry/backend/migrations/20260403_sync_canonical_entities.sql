BEGIN;

CREATE TABLE IF NOT EXISTS medicines (
  id BIGSERIAL PRIMARY KEY,
  medicine_uuid UUID NOT NULL UNIQUE,
  barcode VARCHAR(50) NOT NULL UNIQUE,
  reg_number VARCHAR(50),
  trade_name VARCHAR(255) NOT NULL,
  generic_name VARCHAR(255) NOT NULL DEFAULT '',
  dosage VARCHAR(100) NOT NULL DEFAULT '',
  form VARCHAR(100) NOT NULL DEFAULT '',
  manufacturer VARCHAR(255) NOT NULL DEFAULT '',
  category VARCHAR(100) NOT NULL DEFAULT '',
  regulated_price_minor BIGINT,
  currency_code VARCHAR(3) NOT NULL DEFAULT 'USD',
  is_blocked BOOLEAN NOT NULL DEFAULT false,
  compliance_flags JSONB NOT NULL DEFAULT '[]'::jsonb,
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS product_batches (
  id BIGSERIAL PRIMARY KEY,
  batch_uuid UUID NOT NULL UNIQUE,
  pharmacy_id INT NOT NULL REFERENCES pharmacies(id),
  barcode VARCHAR(50) NOT NULL,
  batch_number VARCHAR(120) NOT NULL,
  expiry_at TIMESTAMPTZ,
  quantity_on_hand INTEGER NOT NULL DEFAULT 0,
  unit_cost_minor BIGINT,
  unit_price_minor BIGINT,
  currency_code VARCHAR(3) NOT NULL DEFAULT 'USD',
  supplier_name VARCHAR(255),
  source_reference_id VARCHAR(120),
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS inventory_movements (
  id BIGSERIAL PRIMARY KEY,
  event_uuid UUID NOT NULL UNIQUE,
  pharmacy_id INT NOT NULL REFERENCES pharmacies(id),
  device_id VARCHAR(64) NOT NULL,
  barcode VARCHAR(50) NOT NULL,
  movement_type VARCHAR(40) NOT NULL,
  quantity_delta INTEGER NOT NULL DEFAULT 0,
  unit_price_minor BIGINT,
  currency_code VARCHAR(3) NOT NULL DEFAULT 'USD',
  reference_type VARCHAR(40) NOT NULL DEFAULT '',
  reference_id VARCHAR(120) NOT NULL DEFAULT '',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  happened_at TIMESTAMPTZ NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  sync_status VARCHAR(20) NOT NULL DEFAULT 'synced',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS sales (
  id BIGSERIAL PRIMARY KEY,
  sale_uuid UUID NOT NULL UNIQUE,
  pharmacy_id INT NOT NULL REFERENCES pharmacies(id),
  device_id VARCHAR(64) NOT NULL,
  receipt_id VARCHAR(100) NOT NULL,
  sold_at TIMESTAMPTZ NOT NULL,
  customer_name VARCHAR(255),
  payment_method VARCHAR(30) NOT NULL DEFAULT 'CASH',
  subtotal_minor BIGINT NOT NULL DEFAULT 0,
  moph_tax_minor BIGINT NOT NULL DEFAULT 0,
  vat_minor BIGINT NOT NULL DEFAULT 0,
  grand_total_minor BIGINT NOT NULL DEFAULT 0,
  currency_code VARCHAR(3) NOT NULL DEFAULT 'USD',
  version INTEGER NOT NULL DEFAULT 1,
  sync_status VARCHAR(20) NOT NULL DEFAULT 'synced',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS sale_items (
  id BIGSERIAL PRIMARY KEY,
  sale_id BIGINT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
  line_uuid UUID NOT NULL UNIQUE,
  barcode VARCHAR(50) NOT NULL,
  product_name VARCHAR(255) NOT NULL,
  dosage VARCHAR(100) NOT NULL DEFAULT '',
  quantity INTEGER NOT NULL,
  unit_price_minor BIGINT NOT NULL,
  line_total_minor BIGINT NOT NULL,
  batch_number VARCHAR(120),
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS purchases (
  id BIGSERIAL PRIMARY KEY,
  purchase_uuid UUID NOT NULL UNIQUE,
  pharmacy_id INT NOT NULL REFERENCES pharmacies(id),
  device_id VARCHAR(64) NOT NULL,
  receipt_id VARCHAR(120) NOT NULL,
  supplier_name VARCHAR(255),
  invoice_number VARCHAR(120),
  purchased_at TIMESTAMPTZ NOT NULL,
  total_cost_minor BIGINT NOT NULL DEFAULT 0,
  currency_code VARCHAR(3) NOT NULL DEFAULT 'USD',
  version INTEGER NOT NULL DEFAULT 1,
  sync_status VARCHAR(20) NOT NULL DEFAULT 'synced',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS purchase_items (
  id BIGSERIAL PRIMARY KEY,
  purchase_id BIGINT NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
  line_uuid UUID NOT NULL UNIQUE,
  barcode VARCHAR(50) NOT NULL,
  product_name VARCHAR(255) NOT NULL,
  dosage VARCHAR(100) NOT NULL DEFAULT '',
  quantity INTEGER NOT NULL,
  unit_cost_minor BIGINT NOT NULL,
  line_total_minor BIGINT NOT NULL,
  batch_number VARCHAR(120),
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS returns (
  id BIGSERIAL PRIMARY KEY,
  return_uuid UUID NOT NULL UNIQUE,
  pharmacy_id INT NOT NULL REFERENCES pharmacies(id),
  device_id VARCHAR(64) NOT NULL,
  barcode VARCHAR(50) NOT NULL,
  return_type VARCHAR(30) NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price_minor BIGINT,
  reason VARCHAR(255),
  reference_id VARCHAR(120),
  happened_at TIMESTAMPTZ NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  sync_status VARCHAR(20) NOT NULL DEFAULT 'synced',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS stock_adjustments (
  id BIGSERIAL PRIMARY KEY,
  adjustment_uuid UUID NOT NULL UNIQUE,
  pharmacy_id INT NOT NULL REFERENCES pharmacies(id),
  device_id VARCHAR(64) NOT NULL,
  barcode VARCHAR(50) NOT NULL,
  quantity_delta INTEGER NOT NULL,
  reason VARCHAR(255) NOT NULL DEFAULT '',
  reference_id VARCHAR(120),
  happened_at TIMESTAMPTZ NOT NULL,
  version INTEGER NOT NULL DEFAULT 1,
  sync_status VARCHAR(20) NOT NULL DEFAULT 'synced',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS prices (
  id BIGSERIAL PRIMARY KEY,
  barcode VARCHAR(50) NOT NULL UNIQUE,
  regulated_price_minor BIGINT,
  local_price_minor BIGINT,
  currency_code VARCHAR(3) NOT NULL DEFAULT 'USD',
  source VARCHAR(30) NOT NULL DEFAULT 'moph',
  version INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS price_history (
  id BIGSERIAL PRIMARY KEY,
  history_uuid UUID NOT NULL UNIQUE,
  barcode VARCHAR(50) NOT NULL,
  pharmacy_id INT REFERENCES pharmacies(id),
  previous_price_minor BIGINT,
  new_price_minor BIGINT,
  currency_code VARCHAR(3) NOT NULL DEFAULT 'USD',
  source VARCHAR(30) NOT NULL,
  changed_by VARCHAR(255),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS compliance_alerts (
  id BIGSERIAL PRIMARY KEY,
  alert_uuid UUID NOT NULL UNIQUE,
  pharmacy_id INT REFERENCES pharmacies(id),
  device_id VARCHAR(64),
  barcode VARCHAR(50),
  alert_type VARCHAR(40) NOT NULL,
  severity VARCHAR(20) NOT NULL DEFAULT 'medium',
  title VARCHAR(255) NOT NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  status VARCHAR(20) NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  acknowledged_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS sync_outbox (
  id BIGSERIAL PRIMARY KEY,
  event_uuid UUID NOT NULL UNIQUE,
  pharmacy_id INT REFERENCES pharmacies(id),
  device_id VARCHAR(64),
  direction VARCHAR(10) NOT NULL,
  stream VARCHAR(50) NOT NULL,
  payload JSONB NOT NULL,
  sync_status VARCHAR(20) NOT NULL DEFAULT 'pending',
  retry_count INTEGER NOT NULL DEFAULT 0,
  next_retry_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS sync_checkpoint (
  id BIGSERIAL PRIMARY KEY,
  pharmacy_id INT REFERENCES pharmacies(id),
  device_id VARCHAR(64) NOT NULL,
  stream VARCHAR(50) NOT NULL,
  checkpoint_token VARCHAR(255) NOT NULL,
  checkpoint_time TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (device_id, stream)
);

CREATE OR REPLACE VIEW audit_log AS
SELECT
  id,
  event_id,
  pharmacy_name,
  hwid,
  license_number,
  region,
  event_type,
  item_name,
  registry_price,
  charged_price,
  unit_count,
  metadata,
  resolved,
  created_at
FROM audit_logs;

COMMIT;
