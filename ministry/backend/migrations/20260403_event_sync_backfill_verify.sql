-- Verification queries for 20260403_event_sync_backfill_safe.sql and reconciliation views.

-- 1) How many stock snapshot rows were backfilled into canonical event stream?
SELECT
  COUNT(*) AS backfilled_snapshot_events
FROM inventory_movements
WHERE reference_type = 'snapshot_backfill';

-- 2) Any stock snapshots still unmapped to a pharmacy?
SELECT
  COUNT(*) AS unmapped_stock_rows
FROM backfill_unmapped_stock;

SELECT *
FROM backfill_unmapped_stock
ORDER BY created_at DESC
LIMIT 100;

-- 3) Price initialization coverage.
SELECT
  COUNT(*) FILTER (WHERE init_history_rows > 0) AS prices_with_init_history,
  COUNT(*) FILTER (WHERE init_history_rows = 0) AS prices_without_init_history
FROM vw_reconcile_price_history_coverage;

SELECT *
FROM vw_reconcile_price_history_coverage
WHERE init_history_rows = 0
ORDER BY price_updated_at DESC
LIMIT 100;

-- 4) Event vs snapshot stock drift.
SELECT
  COUNT(*) AS mismatched_rows,
  MAX(ABS(stock_delta)) AS max_abs_delta
FROM vw_reconcile_stock_event_vs_snapshot
WHERE stock_delta <> 0;

SELECT *
FROM vw_reconcile_stock_event_vs_snapshot
WHERE stock_delta <> 0
ORDER BY ABS(stock_delta) DESC
LIMIT 200;

-- 5) Checkpoint coverage for active devices.
SELECT
  COUNT(*) FILTER (WHERE pos_to_server_checkpoint IS NOT NULL) AS devices_with_pos_to_server_checkpoint,
  COUNT(*) FILTER (WHERE server_to_pos_checkpoint IS NOT NULL) AS devices_with_server_to_pos_checkpoint,
  COUNT(*) AS total_devices
FROM vw_reconcile_checkpoint_health;

SELECT *
FROM vw_reconcile_checkpoint_health
WHERE pos_to_server_checkpoint IS NULL
   OR server_to_pos_checkpoint IS NULL
ORDER BY pharmacy_id;
