BEGIN;

-- Deterministic seed for offline sale -> sync -> analytics -> dashboard verification.

INSERT INTO pharmacies (id, name, license_number, hwid, region, status, last_seen)
VALUES (1, 'Al-Amin Pharmacy', 'LIC-BEY-0041', 'HW-00423', 'Beirut', 'online', NOW()::text)
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
  is_blocked,
  updated_at
)
VALUES
  ('6250000000010', 'REG-0010', 'Paracetamol', 'Paracetamol', '500mg', 'Tablet', 'MedLab', 'Analgesic', 4.50, false, NOW()),
  ('6250000000034', 'REG-0034', 'Codeine', 'Codeine', '30mg', 'Tablet', 'Controlled Meds', 'Controlled', 5.75, true, NOW())
ON CONFLICT (barcode) DO UPDATE SET
  reg_number = EXCLUDED.reg_number,
  trade_name = EXCLUDED.trade_name,
  generic_name = EXCLUDED.generic_name,
  dosage = EXCLUDED.dosage,
  form = EXCLUDED.form,
  manufacturer = EXCLUDED.manufacturer,
  category = EXCLUDED.category,
  moph_ceiling = EXCLUDED.moph_ceiling,
  is_blocked = EXCLUDED.is_blocked,
  updated_at = NOW();

DELETE FROM inventory_movements WHERE pharmacy_id = 1;
DELETE FROM compliance_alerts WHERE pharmacy_id = 1;
DELETE FROM sync_outbox WHERE pharmacy_id = 1;
DELETE FROM sync_checkpoint WHERE pharmacy_id = 1;
DELETE FROM audit_logs WHERE license_number = 'LIC-BEY-0041';

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
  ('6250000000010', 450, 450, 'USD', 'moph', 1, NOW(), NULL),
  ('6250000000034', 575, 575, 'USD', 'moph', 1, NOW(), NULL)
ON CONFLICT (barcode) DO UPDATE SET
  regulated_price_minor = EXCLUDED.regulated_price_minor,
  local_price_minor = EXCLUDED.local_price_minor,
  source = EXCLUDED.source,
  updated_at = NOW(),
  deleted_at = NULL;

COMMIT;
