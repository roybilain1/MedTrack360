BEGIN;

INSERT INTO pharmacies (id, name, license_number, hwid, region, status, last_seen)
VALUES
  (101, 'Al-Amin Pharmacy', 'LIC-BEY-0041', 'HW-00423', 'Beirut', 'online', 'just now'),
  (102, 'Byblos Health Pharmacy', 'LIC-JBE-0220', 'HW-00999', 'Jbeil', 'online', 'just now')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  license_number = EXCLUDED.license_number,
  hwid = EXCLUDED.hwid,
  region = EXCLUDED.region,
  status = EXCLUDED.status,
  last_seen = EXCLUDED.last_seen,
  updated_at = NOW();

INSERT INTO moph_registry (
  barcode,
  reg_number,
  trade_name,
  generic_name,
  dosage,
  form,
  manufacturer,
  category,
  moph_ceiling,
  is_blocked
)
VALUES
  ('6250000000010', 'REG-0010', 'Paracetamol', 'Paracetamol', '500mg', 'Tablet', 'MedLab', 'Analgesic', 4.50, false),
  ('6250000000027', 'REG-0027', 'Amoxicillin', 'Amoxicillin', '1g', 'Capsule', 'MedLab', 'Antibiotic', 6.20, false)
ON CONFLICT (barcode) DO UPDATE SET
  trade_name = EXCLUDED.trade_name,
  generic_name = EXCLUDED.generic_name,
  dosage = EXCLUDED.dosage,
  form = EXCLUDED.form,
  manufacturer = EXCLUDED.manufacturer,
  category = EXCLUDED.category,
  moph_ceiling = EXCLUDED.moph_ceiling,
  is_blocked = EXCLUDED.is_blocked,
  updated_at = NOW();

INSERT INTO prices (
  barcode,
  regulated_price_minor,
  local_price_minor,
  currency_code,
  source,
  version,
  updated_at,
  deleted_at
)
VALUES
  ('6250000000010', 450, 380, 'USD', 'server', 1, NOW(), NULL),
  ('6250000000027', 620, 620, 'USD', 'server', 1, NOW(), NULL)
ON CONFLICT (barcode) DO UPDATE SET
  regulated_price_minor = EXCLUDED.regulated_price_minor,
  local_price_minor = EXCLUDED.local_price_minor,
  currency_code = EXCLUDED.currency_code,
  source = EXCLUDED.source,
  version = GREATEST(prices.version, EXCLUDED.version),
  updated_at = NOW(),
  deleted_at = NULL;

INSERT INTO national_stock (
  barcode,
  medication_name,
  category,
  pharmacy_name,
  license_number,
  hwid,
  stock_units,
  threshold,
  status,
  region,
  last_sync,
  updated_at
)
VALUES
  ('6250000000010', 'Paracetamol 500mg', 'Analgesic', 'Al-Amin Pharmacy', 'LIC-BEY-0041', 'HW-00423', 120, 100, 'safe', 'Beirut', NOW()::text, NOW()),
  ('6250000000027', 'Amoxicillin 1g', 'Antibiotic', 'Al-Amin Pharmacy', 'LIC-BEY-0041', 'HW-00423', 20, 100, 'critical', 'Beirut', NOW()::text, NOW())
ON CONFLICT (barcode, license_number) DO UPDATE SET
  medication_name = EXCLUDED.medication_name,
  category = EXCLUDED.category,
  pharmacy_name = EXCLUDED.pharmacy_name,
  hwid = EXCLUDED.hwid,
  stock_units = EXCLUDED.stock_units,
  threshold = EXCLUDED.threshold,
  status = EXCLUDED.status,
  region = EXCLUDED.region,
  last_sync = EXCLUDED.last_sync,
  updated_at = NOW();

INSERT INTO pos_sync_state (hwid, pharmacy_id, last_sync_up, last_sync_down, pending_updates, app_version)
VALUES
  ('HW-00423', 101, NOW() - INTERVAL '13 hours', NOW() - INTERVAL '14 hours', true, '2.6.1'),
  ('HW-00999', 102, NOW() - INTERVAL '2 hours', NOW() - INTERVAL '2 hours', false, '2.6.1')
ON CONFLICT (hwid) DO UPDATE SET
  pharmacy_id = EXCLUDED.pharmacy_id,
  last_sync_up = EXCLUDED.last_sync_up,
  last_sync_down = EXCLUDED.last_sync_down,
  pending_updates = EXCLUDED.pending_updates,
  app_version = EXCLUDED.app_version,
  updated_at = NOW();

COMMIT;
