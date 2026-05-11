BEGIN;

CREATE INDEX IF NOT EXISTS idx_inventory_movements_pharmacy_barcode_happened
  ON inventory_movements(pharmacy_id, barcode, happened_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_inventory_movements_type_happened
  ON inventory_movements(movement_type, happened_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_price_history_pharmacy_barcode_changed
  ON price_history(pharmacy_id, barcode, changed_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_pharmacy_event_created
  ON audit_logs(pharmacy_name, event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_pharmacies_region_status
  ON pharmacies(region, status);

COMMIT;
