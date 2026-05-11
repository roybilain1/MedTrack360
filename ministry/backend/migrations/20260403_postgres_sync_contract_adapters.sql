BEGIN;

-- Compatibility adapters to preserve legacy naming while canonical tables are used.
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

CREATE OR REPLACE VIEW products AS
SELECT
  medicine_uuid AS product_uuid,
  barcode,
  trade_name AS name,
  dosage,
  category,
  regulated_price_minor,
  currency_code,
  is_blocked,
  version,
  updated_at,
  deleted_at
FROM medicines;

CREATE OR REPLACE VIEW pos_sales_compat AS
SELECT
  s.sale_uuid,
  s.receipt_id,
  s.pharmacy_id,
  s.device_id,
  s.sold_at,
  s.payment_method,
  s.customer_name,
  s.subtotal_minor,
  s.moph_tax_minor,
  s.vat_minor,
  s.grand_total_minor,
  s.currency_code,
  s.payload,
  s.version,
  s.sync_status,
  s.updated_at,
  s.deleted_at
FROM sales s;

CREATE INDEX IF NOT EXISTS idx_products_barcode ON medicines(barcode);
CREATE INDEX IF NOT EXISTS idx_sync_outbox_direction_stream ON sync_outbox(direction, stream, sync_status);
CREATE INDEX IF NOT EXISTS idx_compliance_alerts_type_status ON compliance_alerts(alert_type, status, created_at DESC);

COMMIT;
