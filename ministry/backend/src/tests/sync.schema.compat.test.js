const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function read(relPath) {
  const p = path.resolve(__dirname, relPath);
  return fs.readFileSync(p, 'utf8');
}

test('postgres canonical sync entities exist in schema reference', () => {
  const sql = read('../../schema.sql');
  const required = [
    'CREATE TABLE IF NOT EXISTS medicines',
    'CREATE TABLE IF NOT EXISTS product_batches',
    'CREATE TABLE IF NOT EXISTS inventory_movements',
    'CREATE TABLE IF NOT EXISTS sales',
    'CREATE TABLE IF NOT EXISTS sale_items',
    'CREATE TABLE IF NOT EXISTS purchases',
    'CREATE TABLE IF NOT EXISTS purchase_items',
    'CREATE TABLE IF NOT EXISTS returns',
    'CREATE TABLE IF NOT EXISTS stock_adjustments',
    'CREATE TABLE IF NOT EXISTS prices',
    'CREATE TABLE IF NOT EXISTS price_history',
    'CREATE TABLE IF NOT EXISTS compliance_alerts',
    'CREATE TABLE IF NOT EXISTS sync_outbox',
    'CREATE TABLE IF NOT EXISTS sync_checkpoint',
    'CREATE TABLE IF NOT EXISTS sync_requests',
    'CREATE TABLE IF NOT EXISTS sync_conflict_log',
    'CREATE TABLE IF NOT EXISTS audit_change_log',
  ];

  for (const token of required) {
    assert.equal(sql.includes(token), true, `missing token: ${token}`);
  }
});

test('sqlite canonical sync entities exist in local schema reference', () => {
  const sql = read('../../../../../../POS_frontend/medtrack_pos/database/schema_pos_local.sql');
  const required = [
    'CREATE TABLE IF NOT EXISTS inventory_movement_queue',
    'CREATE TABLE IF NOT EXISTS product_batches',
    'CREATE TABLE IF NOT EXISTS returns',
    'CREATE TABLE IF NOT EXISTS stock_adjustments',
    'CREATE TABLE IF NOT EXISTS prices',
    'CREATE TABLE IF NOT EXISTS price_history',
    'CREATE TABLE IF NOT EXISTS compliance_alerts',
    'CREATE TABLE IF NOT EXISTS sync_outbox',
    'CREATE TABLE IF NOT EXISTS sync_checkpoint',
    'CREATE VIEW IF NOT EXISTS sales',
    'CREATE VIEW IF NOT EXISTS sale_items',
    'CREATE VIEW IF NOT EXISTS medicines',
  ];

  for (const token of required) {
    assert.equal(sql.includes(token), true, `missing token: ${token}`);
  }
});

test('migration scripts include canonical adapters and entities', () => {
  const pgMigration = read('../../migrations/20260403_postgres_sync_contract_adapters.sql');
  const secureSyncMigration = read('../../migrations/20260403_secure_sync_api.sql');
  const deterministicMigration = read('../../migrations/20260403_deterministic_reconciliation.sql');
  const securityHardeningMigration = read('../../migrations/20260403_security_hardening.sql');
  const sqliteMigration = read('../../../../../../POS_frontend/medtrack_pos/database/migrations/20260403_sqlite_sync_contract_entities.sql');

  assert.equal(pgMigration.includes('CREATE OR REPLACE VIEW products AS'), true);
  assert.equal(pgMigration.includes('CREATE OR REPLACE VIEW audit_log AS'), true);
  assert.equal(secureSyncMigration.includes('CREATE TABLE IF NOT EXISTS sync_requests'), true);
  assert.equal(secureSyncMigration.includes('idx_inventory_movements_pharmacy_cursor'), true);
  assert.equal(deterministicMigration.includes('CREATE TABLE IF NOT EXISTS sync_conflict_log'), true);
  assert.equal(deterministicMigration.includes('ADD COLUMN IF NOT EXISTS source'), true);
  assert.equal(securityHardeningMigration.includes('CREATE TABLE IF NOT EXISTS audit_change_log'), true);
  assert.equal(securityHardeningMigration.includes('idx_audit_change_log_request'), true);

  assert.equal(sqliteMigration.includes('CREATE TABLE IF NOT EXISTS sync_outbox'), true);
  assert.equal(sqliteMigration.includes('CREATE TABLE IF NOT EXISTS compliance_alerts'), true);
  assert.equal(sqliteMigration.includes('CREATE VIEW IF NOT EXISTS medicines'), true);
});
