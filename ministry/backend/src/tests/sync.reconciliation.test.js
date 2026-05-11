const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeEventTimestamp,
  deterministicVersionWinner,
  normalizeInventoryMovementEvent,
} = require('../services/reconciliation_service');

test('duplicate push after timeout resolves to same deterministic winner', () => {
  const current = {
    version: 3,
    updated_at: '2026-04-03T10:00:00.000Z',
    device_id: 'HW-00423',
    event_uuid: '11111111-1111-1111-1111-111111111111',
  };

  const duplicate = {
    version: 3,
    updated_at: '2026-04-03T10:00:00.000Z',
    device_id: 'HW-00423',
    event_uuid: '11111111-1111-1111-1111-111111111111',
  };

  const winner = deterministicVersionWinner(current, duplicate);
  assert.equal(winner, 'current');
});

test('out-of-order delivery keeps newer deterministic event', () => {
  const current = {
    version: 5,
    updated_at: '2026-04-03T10:10:00.000Z',
    device_id: 'HW-00423',
    event_uuid: 'aaaaaaaa-1111-1111-1111-111111111111',
  };
  const incomingOlder = {
    version: 4,
    updated_at: '2026-04-03T09:59:00.000Z',
    device_id: 'HW-00423',
    event_uuid: 'bbbbbbbb-1111-1111-1111-111111111111',
  };

  const winner = deterministicVersionWinner(current, incomingOlder);
  assert.equal(winner, 'current');
});

test('same product edited on multiple devices uses deterministic tie-breaker', () => {
  const current = {
    version: 2,
    updated_at: '2026-04-03T10:00:00.000Z',
    device_id: 'HW-00423',
    event_uuid: '00000000-0000-0000-0000-000000000010',
  };
  const incoming = {
    version: 2,
    updated_at: '2026-04-03T10:00:00.000Z',
    device_id: 'HW-00499',
    event_uuid: '00000000-0000-0000-0000-000000000001',
  };

  const winner = deterministicVersionWinner(current, incoming);
  assert.equal(winner, 'incoming');
});

test('government price update while POS offline can still be represented as server source event shape', () => {
  const normalized = normalizeInventoryMovementEvent(
    {
      event_id: '6a5d7244-bdcc-4d10-a198-f4ff8cfbd21b',
      payload: {
        barcode: '6250000000010',
        movement_type: 'price_update',
        quantity_delta: 0,
        source: 'server',
        happened_at: '2026-04-03T09:00:00.000Z',
        version: 7,
      },
    },
    { pharmacyId: 101, deviceId: 'HW-00423' }
  );

  assert.equal(normalized.source, 'server');
  assert.equal(normalized.version, 7);
  assert.equal(normalized.pharmacy_id, 101);
  assert.equal(normalized.barcode, '6250000000010');
});

test('retry after partial server failure keeps skew-safe timestamp normalization', () => {
  const now = new Date('2026-04-03T10:00:00.000Z');
  const veryFuture = new Date('2026-04-03T15:30:00.000Z').toISOString();
  const normalized = normalizeEventTimestamp({
    happenedAt: veryFuture,
    now,
    futureToleranceMs: 60 * 1000,
  });

  assert.equal(normalized.skewed, true);
  assert.equal(normalized.timestamp.toISOString(), now.toISOString());
  assert.equal(normalized.note, 'future_clock_skew_clamped');
});

test('retry after partial server failure keeps accepted event stable and allows newer event', () => {
  const acceptedAlready = {
    version: 3,
    updated_at: '2026-04-03T10:00:00.000Z',
    device_id: 'HW-00423',
    event_uuid: '10000000-0000-0000-0000-000000000001',
  };

  const retryDuplicate = {
    version: 3,
    updated_at: '2026-04-03T10:00:00.000Z',
    device_id: 'HW-00423',
    event_uuid: '10000000-0000-0000-0000-000000000001',
  };

  const retryNewer = {
    version: 4,
    updated_at: '2026-04-03T10:02:00.000Z',
    device_id: 'HW-00423',
    event_uuid: '10000000-0000-0000-0000-000000000002',
  };

  assert.equal(deterministicVersionWinner(acceptedAlready, retryDuplicate), 'current');
  assert.equal(deterministicVersionWinner(acceptedAlready, retryNewer), 'incoming');
});
