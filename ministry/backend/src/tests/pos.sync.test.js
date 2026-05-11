const test = require('node:test');
const assert = require('node:assert/strict');

const posRoute = require('../routes/pos');

const {
  stableUuid,
  parseJsonSafely,
  asUtcDateFromEpochMs,
  isStockMovementType,
  normalizeMovement,
  stockStatus,
} = posRoute._test;

test('stableUuid is deterministic for same seed', () => {
  const a = stableUuid('sale:1:RX-123');
  const b = stableUuid('sale:1:RX-123');
  const c = stableUuid('sale:1:RX-124');

  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.match(a, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
});

test('normalizeMovement keeps UUID/device/version and parses metadata JSON', () => {
  const movement = normalizeMovement(
    {
      movement_uuid: '2c6c8a7a-f696-4f89-a4f7-90e2f8be7554',
      device_id: 'POS-A',
      version: 3,
      barcode: '6289201012345',
      movement_type: 'sale',
      quantity_delta: -2,
      unit_price_minor: 1800,
      metadata: '{"receipt_id":"RX-1"}',
      happened_at: 1713206400000,
      updated_at: 1713206405000,
    },
    'fallback-device',
    99
  );

  assert.equal(movement.movementUuid, '2c6c8a7a-f696-4f89-a4f7-90e2f8be7554');
  assert.equal(movement.deviceId, 'POS-A');
  assert.equal(movement.version, 3);
  assert.equal(movement.pharmacyId, 99);
  assert.equal(movement.metadata.receipt_id, 'RX-1');
  assert.equal(movement.quantityDelta, -2);
});

test('normalizeMovement falls back for invalid values', () => {
  const movement = normalizeMovement(
    {
      movement_uuid: '',
      barcode: 'X',
      movement_type: 'unknown',
      quantity_delta: 'bad',
      metadata: 'not json',
      happened_at: 0,
      updated_at: 0,
    },
    'fallback-device',
    10
  );

  assert.equal(movement.movementUuid, '');
  assert.equal(movement.deviceId, 'fallback-device');
  assert.equal(movement.version, 1);
  assert.equal(movement.quantityDelta, 0);
  assert.deepEqual(movement.metadata, {});
});

test('stock movement type and status helpers enforce expected semantics', () => {
  assert.equal(isStockMovementType('sale'), true);
  assert.equal(isStockMovementType('purchase'), true);
  assert.equal(isStockMovementType('price_change'), false);

  assert.equal(stockStatus(0, 1000), 'critical');
  assert.equal(stockStatus(200, 1000), 'critical');
  assert.equal(stockStatus(600, 1000), 'low');
  assert.equal(stockStatus(1200, 1000), 'safe');
});

test('utility parser/date helpers are deterministic for valid inputs', () => {
  const parsed = parseJsonSafely('{"ok":true}', {});
  assert.equal(parsed.ok, true);

  const dt = asUtcDateFromEpochMs(1704067200000);
  assert.equal(dt.toISOString(), '2024-01-01T00:00:00.000Z');
});

test('normalizeMovement maps deleted_at for soft delete sync payloads', () => {
  const movement = normalizeMovement(
    {
      movement_uuid: 'f635b154-2ed6-4e34-8fb3-c965f70ab825',
      device_id: 'POS-A',
      version: 2,
      barcode: '6250000000010',
      movement_type: 'adjustment',
      quantity_delta: -1,
      deleted_at: 1713206409000,
      happened_at: 1713206400000,
      updated_at: 1713206405000,
    },
    'fallback-device',
    99
  );

  assert.equal(movement.deletedAt instanceof Date, true);
  assert.equal(movement.deletedAt.toISOString(), '2024-04-15T18:40:09.000Z');
});
