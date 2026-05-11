BEGIN;

INSERT INTO pharmacies (id, name, license_number, hwid, region, status, last_seen)
VALUES
  (101, 'Al-Amin Pharmacy', 'LIC-BEY-0041', 'HW-00423', 'Beirut', 'online', 'just now'),
  (102, 'Cedar Care Pharmacy', 'LIC-MET-0112', 'HW-00991', 'Metn', 'online', 'just now')
ON CONFLICT (id) DO NOTHING;

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
  created_at,
  updated_at
)
VALUES
  ('6250000000010', 'REG-0010', 'Paracetamol', 'Acetaminophen', '500mg', 'Tablet', 'Medica Labs', 'Analgesic', 2.50, false, NOW(), NOW()),
  ('6250000000027', 'REG-0027', 'Ibuprofen', 'Ibuprofen', '400mg', 'Tablet', 'Levant Pharma', 'Anti-inflammatory', 3.20, false, NOW(), NOW()),
  ('6250000000034', 'REG-0034', 'Codeine', 'Codeine', '30mg', 'Tablet', 'Controlled Meds', 'Controlled', 5.75, true, NOW(), NOW())
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
  ('6250000000010', 250, 250, 'USD', 'moph', 1, NOW(), NULL),
  ('6250000000027', 320, 320, 'USD', 'moph', 1, NOW(), NULL),
  ('6250000000034', 575, 575, 'USD', 'moph', 1, NOW(), NULL)
ON CONFLICT (barcode) DO UPDATE SET
  regulated_price_minor = EXCLUDED.regulated_price_minor,
  local_price_minor = EXCLUDED.local_price_minor,
  source = EXCLUDED.source,
  version = prices.version + 1,
  updated_at = NOW();

INSERT INTO inventory_movements (
  event_uuid,
  pharmacy_id,
  device_id,
  barcode,
  movement_type,
  quantity_delta,
  unit_price_minor,
  currency_code,
  reference_type,
  reference_id,
  metadata,
  happened_at,
  version,
  sync_status,
  updated_at,
  deleted_at
)
VALUES
  ('9b9df9f8-cab0-4b26-96e0-0e44f2f69290', 101, 'HW-00423', '6250000000010', 'purchase', 100, 180, 'USD', 'invoice', 'INV-1001', '{"supplier":"Distributor A"}'::jsonb, NOW() - INTERVAL '2 days', 1, 'synced', NOW(), NULL),
  ('f85f2764-9e6a-4e53-acf8-19d86a393b63', 101, 'HW-00423', '6250000000010', 'sale', -8, 250, 'USD', 'receipt', 'RCPT-8801', '{"cashier":"Nadia"}'::jsonb, NOW() - INTERVAL '1 day', 1, 'synced', NOW(), NULL),
  ('7f262fb4-e95f-4218-9f7c-88df2459585d', 102, 'HW-00991', '6250000000027', 'purchase', 60, 210, 'USD', 'invoice', 'INV-2207', '{"supplier":"Distributor B"}'::jsonb, NOW() - INTERVAL '3 days', 1, 'synced', NOW(), NULL)
ON CONFLICT (event_uuid) DO NOTHING;

INSERT INTO compliance_alerts (
  alert_uuid,
  pharmacy_id,
  device_id,
  barcode,
  alert_type,
  severity,
  title,
  details,
  status,
  created_at,
  updated_at,
  deleted_at
)
VALUES
  ('5bb3acb7-f205-4dfa-9f2b-8f088f749335', 101, 'HW-00423', '6250000000034', 'blocked_sale', 'critical', 'Blocked medicine sold', '{"receipt_id":"RCPT-9902"}'::jsonb, 'open', NOW(), NOW(), NULL),
  ('cc15f509-5d16-4d74-9376-3898aaf34acd', 101, 'HW-00423', '6250000000010', 'price_violation', 'high', 'Price above ceiling', '{"regulated_price_minor":250,"charged_price_minor":320}'::jsonb, 'open', NOW(), NOW(), NULL)
ON CONFLICT (alert_uuid) DO NOTHING;

INSERT INTO price_history (
  history_uuid,
  barcode,
  pharmacy_id,
  previous_price_minor,
  new_price_minor,
  currency_code,
  source,
  changed_by,
  changed_at,
  metadata
)
VALUES
  ('1f53be64-5845-4cb4-b87f-c1fd31cb23f2', '6250000000010', 101, 220, 250, 'USD', 'moph', 'admin', NOW() - INTERVAL '10 days', '{"reason":"ceiling update"}'::jsonb),
  ('67b97756-f8c7-45f7-b3f6-0465f04750cf', '6250000000010', 101, 250, 340, 'USD', 'pos', 'HW-00423', NOW() - INTERVAL '2 days', '{"reason":"suspicious spike"}'::jsonb),
  ('93ee85d2-ff11-4aa8-8f4a-99f42d06507f', '6250000000027', 102, 300, 320, 'USD', 'moph', 'admin', NOW() - INTERVAL '4 days', '{"reason":"minor increase"}'::jsonb)
ON CONFLICT (history_uuid) DO NOTHING;

DELETE FROM audit_logs
WHERE event_id IN ('EVT-SAMPLE-001', 'EVT-SAMPLE-002', 'EVT-SAMPLE-003');

INSERT INTO audit_logs (
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
  created_at
)
VALUES
  ('EVT-SAMPLE-001', 'Al-Amin Pharmacy', 'HW-00423', 'LIC-BEY-0041', 'Beirut', 'sale', 'Paracetamol 500mg', 2.50, 2.50, 5, '{"source":"seed"}'::jsonb, NOW() - INTERVAL '1 day'),
  ('EVT-SAMPLE-002', 'Al-Amin Pharmacy', 'HW-00423', 'LIC-BEY-0041', 'Beirut', 'price_hike', 'Paracetamol 500mg', 2.50, 3.40, 2, '{"source":"seed"}'::jsonb, NOW() - INTERVAL '20 hours'),
  ('EVT-SAMPLE-003', 'Cedar Care Pharmacy', 'HW-00991', 'LIC-MET-0112', 'Metn', 'stock_adjust', 'Ibuprofen 400mg', 3.20, 3.20, 30, '{"source":"seed","reason":"bulk intake"}'::jsonb, NOW() - INTERVAL '3 days');

INSERT INTO sync_checkpoint (
  pharmacy_id,
  device_id,
  stream,
  checkpoint_token,
  checkpoint_time,
  updated_at
)
VALUES
  (101, 'HW-00423', 'server_to_pos', 'sample-server-cursor-1', NOW(), NOW()),
  (101, 'HW-00423', 'pos_to_server', 'sample-pos-cursor-1', NOW(), NOW())
ON CONFLICT (device_id, stream) DO UPDATE SET
  checkpoint_token = EXCLUDED.checkpoint_token,
  checkpoint_time = EXCLUDED.checkpoint_time,
  updated_at = NOW();

COMMIT;
