const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const db = require('../db');
const syncRoutes = require('../routes/sync');
const webRoutes = require('../routes/web');
const {
  movementEvent,
  priceUpdateEvent,
  pushBody,
} = require('./fixtures/sync_scenarios.fixture');

function createMockDbState() {
  return {
    pharmacies: [
      {
        id: 1,
        name: 'Al-Amin Pharmacy',
        license_number: 'LIC-BEY-0041',
        hwid: 'HW-00423',
        region: 'Beirut',
        status: 'online',
        last_seen: 'just now',
        sync_version: '2.6.1',
        sync_pct: 100,
      },
    ],
    syncRequests: new Map(),
    inventoryMovements: [],
    complianceAlerts: [],
    auditChanges: [],
    prices: [],
    priceHistory: [],
    syncOutbox: [],
    checkpoints: [],
  };
}

function makeMockDbClient(state) {
  return {
    async query(sql, params = []) {
      const normalizedSql = String(sql).replace(/\s+/g, ' ').trim().toLowerCase();

      if (normalizedSql === 'begin' || normalizedSql === 'commit' || normalizedSql === 'rollback') {
        return { rows: [], rowCount: 0 };
      }

      if (normalizedSql.includes('select * from pharmacies where id =')) {
        const id = Number(params[0]);
        const row = state.pharmacies.find((p) => p.id === id);
        return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
      }

      if (normalizedSql.includes('select * from pharmacies where license_number =')) {
        const license = String(params[0] || '');
        const row = state.pharmacies.find((p) => p.license_number === license);
        return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
      }

      if (normalizedSql.includes('update pharmacies set hwid =')) {
        const hwid = params[0];
        const id = Number(params[1]);
        const pharmacy = state.pharmacies.find((p) => p.id === id);
        if (!pharmacy) return { rows: [], rowCount: 0 };
        pharmacy.hwid = hwid;
        pharmacy.status = 'online';
        pharmacy.last_seen = 'just now';
        return { rows: [pharmacy], rowCount: 1 };
      }

      if (normalizedSql.includes('update pharmacies set status =')) {
        return { rows: [], rowCount: 1 };
      }

      if (normalizedSql.includes('insert into sync_requests')) {
        const requestId = params[0];
        if (state.syncRequests.has(requestId)) {
          return { rows: [], rowCount: 0 };
        }
        const next = {
          id: state.syncRequests.size + 1,
          request_id: requestId,
          pharmacy_id: params[1],
          device_id: params[2],
          endpoint: params[3],
          payload: params[4],
          request_status: 'processing',
          response_payload: null,
        };
        state.syncRequests.set(requestId, next);
        return { rows: [{ id: next.id }], rowCount: 1 };
      }

      if (normalizedSql.includes('select id, response_payload, request_status from sync_requests')) {
        const requestId = params[0];
        const found = state.syncRequests.get(requestId);
        return { rows: found ? [found] : [], rowCount: found ? 1 : 0 };
      }

      if (normalizedSql.includes('update sync_requests set request_status =')) {
        const id = Number(params[0]);
        for (const req of state.syncRequests.values()) {
          if (req.id === id) {
            req.request_status = params[1];
            req.response_payload = JSON.parse(params[2]);
            break;
          }
        }
        return { rows: [], rowCount: 1 };
      }

      if (normalizedSql.includes('insert into inventory_movements')) {
        const eventUuid = params[0];
        const exists = state.inventoryMovements.some((m) => m.event_uuid === eventUuid);
        if (exists) return { rows: [], rowCount: 0 };
        state.inventoryMovements.push({
          event_uuid: eventUuid,
          pharmacy_id: params[1],
          device_id: params[2],
          source: params[3],
          barcode: params[4],
          movement_type: params[5],
          quantity_delta: params[6],
          unit_price_minor: params[7],
          currency_code: params[8],
          reference_type: params[9],
          reference_id: params[10],
          metadata: JSON.parse(params[11]),
          happened_at: params[12],
          version: params[13],
          updated_at: new Date().toISOString(),
        });
        return { rows: [{ id: state.inventoryMovements.length }], rowCount: 1 };
      }

      if (normalizedSql.includes('from inventory_movements') && normalizedSql.includes('reference_type =')) {
        const [pharmacyId, barcode, referenceType, referenceId, movementType] = params;
        const rows = state.inventoryMovements
          .filter((m) =>
            Number(m.pharmacy_id) === Number(pharmacyId)
            && String(m.barcode) === String(barcode)
            && String(m.reference_type) === String(referenceType)
            && String(m.reference_id) === String(referenceId)
            && String(m.movement_type) === String(movementType)
          )
          .slice(-1)
          .map((m) => ({
            event_uuid: m.event_uuid,
            version: m.version,
            updated_at: m.updated_at,
            device_id: m.device_id,
          }));
        return { rows, rowCount: rows.length };
      }

      if (normalizedSql.includes('select coalesce(sum(quantity_delta), 0)::int as stock_units from inventory_movements')) {
        const pharmacyId = Number(params[0]);
        const barcode = String(params[1]);
        const stockUnits = state.inventoryMovements
          .filter((m) => Number(m.pharmacy_id) === pharmacyId && String(m.barcode) === barcode)
          .reduce((sum, m) => sum + Number(m.quantity_delta || 0), 0);
        return { rows: [{ stock_units: stockUnits }], rowCount: 1 };
      }

      if (normalizedSql.includes('insert into audit_change_log')) {
        state.auditChanges.push({
          change_uuid: params[0],
          pharmacy_id: params[1],
          entity_type: params[2],
          entity_id: params[3],
          change_type: params[4],
          old_value: JSON.parse(params[5]),
          new_value: JSON.parse(params[6]),
          actor_identity: params[7],
          actor_role: params[8],
          device_id: params[9],
          source_ip: params[10],
          source: params[11],
          request_id: params[12],
        });
        return { rows: [], rowCount: 1 };
      }

      if (normalizedSql.includes('select local_price_minor from prices where barcode =')) {
        const barcode = String(params[0]);
        const found = state.prices.find((p) => String(p.barcode) === barcode) || null;
        return {
          rows: found ? [{ local_price_minor: found.local_price_minor }] : [],
          rowCount: found ? 1 : 0,
        };
      }

      if (normalizedSql.includes('insert into prices')) {
        const barcode = String(params[0]);
        const localPriceMinor = Number(params[1]);
        const currencyCode = String(params[2] || 'USD');
        const idx = state.prices.findIndex((p) => String(p.barcode) === barcode);
        if (idx >= 0) {
          const prev = state.prices[idx];
          state.prices[idx] = {
            ...prev,
            local_price_minor: localPriceMinor,
            currency_code: currencyCode,
            source: 'pos',
            version: Number(prev.version || 1) + 1,
            updated_at: new Date().toISOString(),
          };
        } else {
          state.prices.push({
            barcode,
            regulated_price_minor: null,
            local_price_minor: localPriceMinor,
            currency_code: currencyCode,
            source: 'pos',
            version: 1,
            updated_at: new Date().toISOString(),
            deleted_at: null,
          });
        }
        return { rows: [], rowCount: 1 };
      }

      if (normalizedSql.includes('insert into price_history')) {
        state.priceHistory.push({
          history_uuid: params[0],
          barcode: params[1],
          pharmacy_id: params[2],
          previous_price_minor: params[3],
          new_price_minor: params[4],
          currency_code: params[5],
          changed_by: params[6],
          metadata: JSON.parse(params[7]),
        });
        return { rows: [], rowCount: 1 };
      }

      if (normalizedSql.includes('select id from price_history where history_uuid =')) {
        const historyUuid = String(params[0]);
        const found = state.priceHistory.find((row) => String(row.history_uuid) === historyUuid);
        return {
          rows: found ? [{ id: 1 }] : [],
          rowCount: found ? 1 : 0,
        };
      }

      if (normalizedSql.includes('insert into sync_conflict_log')) {
        return { rows: [], rowCount: 1 };
      }

      if (normalizedSql.includes('select moph_ceiling, is_blocked from moph_registry')) {
        return { rows: [{ moph_ceiling: 4.5, is_blocked: false }], rowCount: 1 };
      }

      if (normalizedSql.includes('insert into compliance_alerts')) {
        state.complianceAlerts.push({ id: state.complianceAlerts.length + 1, raw: params });
        return { rows: [], rowCount: 1 };
      }

      if (normalizedSql.includes('insert into audit_logs')) {
        return { rows: [], rowCount: 1 };
      }

      if (normalizedSql.includes('select event_uuid, barcode, movement_type')) {
        const cursorTime = new Date(params[1]);
        const cursorId = String(params[2] || '00000000-0000-0000-0000-000000000000');
        const limit = Number(params[3] || 200);
        const items = [...state.inventoryMovements]
          .filter((m) => {
            const updated = new Date(m.updated_at);
            if (Number.isNaN(updated.getTime())) return false;
            if (updated > cursorTime) return true;
            if (updated < cursorTime) return false;
            return String(m.event_uuid) > cursorId;
          })
          .sort((a, b) => String(a.updated_at).localeCompare(String(b.updated_at)))
          .slice(0, limit)
          .map((m) => ({
            event_uuid: m.event_uuid,
            barcode: m.barcode,
            movement_type: m.movement_type,
            quantity_delta: m.quantity_delta,
            source: m.source || 'pos',
            unit_price_minor: m.unit_price_minor,
            currency_code: m.currency_code,
            reference_type: m.reference_type,
            reference_id: m.reference_id,
            metadata: m.metadata,
            happened_at: m.happened_at,
            updated_at: m.updated_at,
            version: m.version,
          }));
        return { rows: items, rowCount: items.length };
      }

      if (normalizedSql.includes('select barcode, regulated_price_minor')) {
        return { rows: state.prices, rowCount: state.prices.length };
      }

      if (normalizedSql.includes('from prices') && normalizedSql.includes('regulated_price_minor')) {
        return { rows: state.prices, rowCount: state.prices.length };
      }

      if (normalizedSql.includes('select md5(barcode)::uuid as medicine_uuid')) {
        return {
          rows: [
            {
              medicine_uuid: '4e87bd68-972f-4c6d-8b34-0aebf967f6d2',
              barcode: '6250000000010',
              official_code: 'REG-0010',
              official_name: 'Paracetamol',
              dosage: '500mg',
              form: 'Tablet',
              category: 'Analgesic',
              regulated_price_minor: 250,
              is_blocked: false,
              updated_at: new Date().toISOString(),
              deleted_at: null,
              source: 'moph_registry',
              version: 1,
              pharmacy_id: 1,
            },
          ],
          rowCount: 1,
        };
      }

      if (normalizedSql.includes("select value from system_settings where key = 'max_markup_pct'")) {
        return { rows: [{ value: { value: 0.15 } }], rowCount: 1 };
      }

      if (normalizedSql.includes('from sync_conflict_log')) {
        return { rows: [], rowCount: 0 };
      }

      if (normalizedSql.includes('select alert_uuid, barcode, alert_type')) {
        return { rows: state.complianceAlerts, rowCount: state.complianceAlerts.length };
      }

      if (normalizedSql.includes('from compliance_alerts') && normalizedSql.includes('alert_uuid')) {
        return { rows: state.complianceAlerts, rowCount: state.complianceAlerts.length };
      }

      if (normalizedSql.includes('from compliance_alerts c') && normalizedSql.includes('left join pharmacies p')) {
        const rows = state.complianceAlerts.map((alert) => {
          const pharmacy = state.pharmacies.find((p) => Number(p.id) === Number(alert.pharmacy_id));
          return {
            ...alert,
            pharmacy_name: pharmacy?.name || null,
            license_number: pharmacy?.license_number || null,
          };
        });
        return { rows, rowCount: rows.length };
      }

      if (normalizedSql.includes('select barcode, greatest(0, sum(quantity_delta))::int as stock_units')) {
        const byBarcode = new Map();
        for (const movement of state.inventoryMovements) {
          const key = movement.barcode;
          const prev = byBarcode.get(key) || 0;
          byBarcode.set(key, Math.max(0, prev + Number(movement.quantity_delta || 0)));
        }
        const rows = [...byBarcode.entries()].map(([barcode, stock_units]) => ({ barcode, stock_units }));
        return { rows, rowCount: rows.length };
      }

      if (normalizedSql.includes('insert into sync_outbox')) {
        state.syncOutbox.push({ event_uuid: params[0], payload: JSON.parse(params[3]) });
        return { rows: [], rowCount: 1 };
      }

      if (normalizedSql.includes('update sync_outbox set sync_status =')) {
        return { rows: [], rowCount: 1 };
      }

      if (normalizedSql.includes('insert into sync_checkpoint')) {
        state.checkpoints.push({
          pharmacy_id: params[0],
          device_id: params[1],
          token: params[2],
        });
        return { rows: [], rowCount: 1 };
      }

      if (normalizedSql.includes('select barcode, trade_name, dosage')) {
        return {
          rows: [
            {
              barcode: '6250000000010',
              trade_name: 'Paracetamol',
              dosage: '500mg',
              regulated_price_minor: 250,
              currency_code: 'USD',
              is_blocked: false,
              updated_at: new Date().toISOString(),
            },
          ],
          rowCount: 1,
        };
      }

      if (normalizedSql.includes('select alert_uuid, pharmacy_id, device_id')) {
        return { rows: state.complianceAlerts, rowCount: state.complianceAlerts.length };
      }

      if (normalizedSql.includes('select p.id as pharmacy_id')) {
        return {
          rows: [
            {
              pharmacy_id: 1,
              pharmacy_name: 'Al-Amin Pharmacy',
              device_id: 'HW-00423',
              pending_outbox: 0,
              open_alerts: state.complianceAlerts.length,
            },
          ],
          rowCount: 1,
        };
      }

      throw new Error(`Unhandled SQL in test mock: ${normalizedSql}`);
    },
    release() {},
  };
}

function startTestServer(state) {
  const app = express();
  app.use(express.json());
  app.use('/api/sync', syncRoutes);
  app.use('/api/web', webRoutes);

  const originalConnect = db.pool.connect;
  const originalQuery = db.query;

  db.pool.connect = async () => makeMockDbClient(state);
  db.query = async (sql, params = []) => {
    const c = makeMockDbClient(state);
    return c.query(sql, params);
  };

  const server = app.listen(0);

  return {
    server,
    restore() {
      db.pool.connect = originalConnect;
      db.query = originalQuery;
      server.close();
    },
  };
}

function apiBase(server) {
  const addr = server.address();
  return `http://127.0.0.1:${addr.port}/api/sync`;
}

test('sync push is idempotent by request_id and event_id', async () => {
  const state = createMockDbState();
  const harness = startTestServer(state);

  try {
    const base = apiBase(harness.server);
    const headers = {
      'content-type': 'application/json',
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00423',
    };

    const body = {
      request_id: 'REQ-1',
      events: [
        {
          event_id: '8e3cba2f-23ca-4bcf-9d40-05b1d95bf70b',
          event_type: 'inventory_movement',
          payload: {
            barcode: '6250000000010',
            movement_type: 'sale',
            quantity_delta: -2,
            unit_price_minor: 300,
            happened_at: Date.now(),
          },
        },
      ],
    };

    const firstResp = await fetch(`${base}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    });
    assert.equal(firstResp.status, 200);
    const firstJson = await firstResp.json();
    assert.equal(firstJson.status, 'success');
    assert.equal(firstJson.accepted_event_ids.length, 1);

    const secondResp = await fetch(`${base}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    });
    assert.equal(secondResp.status, 200);
    const secondJson = await secondResp.json();
    assert.equal(secondJson.request_id, 'REQ-1');

    assert.equal(state.inventoryMovements.length, 1);
    assert.equal(state.auditChanges.length, 1);
    assert.equal(state.auditChanges[0].entity_type, 'inventory');
    assert.equal(state.auditChanges[0].change_type, 'stock_change');
  } finally {
    harness.restore();
  }
});

test('sync pull returns cursor and sync ack stores checkpoint', async () => {
  const state = createMockDbState();
  state.inventoryMovements.push({
    event_uuid: '9554f166-0e1a-46a6-83ba-bb3638dd1c3a',
    pharmacy_id: 1,
    device_id: 'HW-00423',
    barcode: '6250000000010',
    movement_type: 'purchase',
    quantity_delta: 10,
    unit_price_minor: 220,
    currency_code: 'USD',
    reference_type: 'invoice',
    reference_id: 'INV-10',
    metadata: {},
    happened_at: new Date().toISOString(),
    version: 1,
    updated_at: new Date().toISOString(),
  });

  const harness = startTestServer(state);

  try {
    const base = apiBase(harness.server);
    const headers = {
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00423',
    };

    const pullResp = await fetch(`${base}/pull?limit=10`, { headers });
    assert.equal(pullResp.status, 200);
    const pullJson = await pullResp.json();
    assert.equal(pullJson.status, 'success');
    assert.equal(Array.isArray(pullJson.data.events), true);
    assert.equal(pullJson.data.events.length, 1);
    assert.equal(Array.isArray(pullJson.data.authoritative_medicines), true);
    assert.equal(pullJson.data.authoritative_medicines.length > 0, true);
    assert.equal(
      Number.isFinite(Number(pullJson.data.authoritative_medicines[0].regulated_price_minor)),
      true,
    );
    assert.ok(pullJson.batch_id);

    const ackResp = await fetch(`${base}/ack`, {
      method: 'POST',
      headers: { ...headers, 'content-type': 'application/json' },
      body: JSON.stringify({
        request_id: 'ACK-1',
        batch_id: pullJson.batch_id,
        checkpoint_token: pullJson.next_cursor || 'manual-checkpoint',
      }),
    });

    assert.equal(ackResp.status, 200);
    const ackJson = await ackResp.json();
    assert.equal(ackJson.status, 'success');
    assert.equal(ackJson.acked_batch_id, pullJson.batch_id);
    assert.equal(state.checkpoints.length > 0, true);
  } finally {
    harness.restore();
  }
});

test('regulations, compliance and sync health endpoints respond with secured pharmacy context', async () => {
  const state = createMockDbState();
  const harness = startTestServer(state);

  try {
    const base = apiBase(harness.server);
    const headers = {
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00423',
    };

    const pricesResp = await fetch(`${base}/regulations/prices?limit=20`, { headers });
    assert.equal(pricesResp.status, 200);
    const pricesJson = await pricesResp.json();
    assert.equal(pricesJson.status, 'success');
    assert.equal(pricesJson.count, 1);

    const alertsResp = await fetch(`${base}/compliance/alerts?status=open`, { headers });
    assert.equal(alertsResp.status, 200);
    const alertsJson = await alertsResp.json();
    assert.equal(alertsJson.status, 'success');

    const healthResp = await fetch(`${base}/health`, { headers });
    assert.equal(healthResp.status, 200);
    const healthJson = await healthResp.json();
    assert.equal(healthJson.status, 'success');
    assert.equal(healthJson.count, 1);
  } finally {
    harness.restore();
  }
});

test('high price detection triggers conflict and compliance alert on sync push', async () => {
  const state = createMockDbState();
  const harness = startTestServer(state);

  try {
    const base = apiBase(harness.server);
    const headers = {
      'content-type': 'application/json',
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00423',
    };

    const body = pushBody({
      requestId: 'REQ-HIGH-PRICE-1',
      events: [
        movementEvent({
          eventId: '1f88a65b-ea52-4d3f-9b1a-7f5ba3f4f081',
          movementType: 'sale',
          quantityDelta: -1,
          unitPriceMinor: 700,
          referenceId: 'RX-HIGH-1',
        }),
      ],
    });

    const response = await fetch(`${base}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
    });

    assert.equal(response.status, 200);
    const json = await response.json();
    assert.equal(json.status, 'success');
    assert.equal(json.conflicts.some((c) => c.code === 'price_violation'), true);
    assert.equal(state.complianceAlerts.length > 0, true);
  } finally {
    harness.restore();
  }
});

test('partial sync failure can resume with remaining valid events', async () => {
  const state = createMockDbState();
  const harness = startTestServer(state);

  try {
    const base = apiBase(harness.server);
    const headers = {
      'content-type': 'application/json',
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00423',
    };

    const first = await fetch(`${base}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(pushBody({
        requestId: 'REQ-PARTIAL-1',
        events: [
          movementEvent({
            eventId: '5cc5a56c-dce3-4365-a7f8-ebc044f689cb',
            quantityDelta: -2,
            referenceId: 'RX-PARTIAL-1',
          }),
          {
            event_id: '8f3ec4da-8099-4420-8193-f6f4c01862f1',
            event_type: 'price_update',
            payload: { barcode: '6250000000010' },
          },
        ],
      })),
    });

    assert.equal(first.status, 200);
    const firstJson = await first.json();
    assert.equal(firstJson.accepted_event_ids.length, 1);
    assert.equal(firstJson.conflicts.some((c) => c.code === 'invalid_event_payload'), true);
    assert.equal(firstJson.rejected_event_ids.length, 1);

    const retry = await fetch(`${base}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(pushBody({
        requestId: 'REQ-PARTIAL-2',
        events: [
          priceUpdateEvent({
            eventId: 'b10fb646-313f-4f14-8cf5-c669f99ca4d0',
            newPriceMinor: 390,
          }),
        ],
      })),
    });

    assert.equal(retry.status, 200);
    const retryJson = await retry.json();
    assert.equal(retryJson.accepted_event_ids.length, 1);
    assert.equal(state.prices.length, 1);
    assert.equal(state.priceHistory.length, 1);
  } finally {
    harness.restore();
  }
});

test('interrupted retry keeps already accepted event idempotent and applies remaining event', async () => {
  const state = createMockDbState();
  const harness = startTestServer(state);

  try {
    const base = apiBase(harness.server);
    const headers = {
      'content-type': 'application/json',
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00423',
    };

    const firstEventId = '22c8ae8e-0ef8-48de-abcd-3d7dc7e612c1';

    const first = await fetch(`${base}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(pushBody({
        requestId: 'REQ-INTERRUPT-1',
        events: [
          movementEvent({ eventId: firstEventId, quantityDelta: -1, referenceId: 'RX-I-1' }),
          {
            event_id: 'e637a633-f724-4369-9359-1ca4a73f44c7',
            event_type: 'price_update',
            payload: { barcode: '6250000000010' },
          },
        ],
      })),
    });

    assert.equal(first.status, 200);
    const firstJson = await first.json();
    assert.equal(firstJson.accepted_event_ids.includes(firstEventId), true);
    assert.equal(firstJson.rejected_event_ids.length, 1);

    const retry = await fetch(`${base}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(pushBody({
        requestId: 'REQ-INTERRUPT-2',
        events: [
          movementEvent({ eventId: firstEventId, quantityDelta: -1, referenceId: 'RX-I-1' }),
          priceUpdateEvent({
            eventId: 'f913f3c5-0d42-4870-a77b-638a3f07dd02',
            barcode: '6250000000010',
            newPriceMinor: 355,
          }),
        ],
      })),
    });

    assert.equal(retry.status, 200);
    const retryJson = await retry.json();
    assert.equal(retryJson.duplicate_event_ids.includes(firstEventId), true);
    assert.equal(retryJson.accepted_event_ids.includes('f913f3c5-0d42-4870-a77b-638a3f07dd02'), true);
    assert.equal(state.inventoryMovements.length, 1);
  } finally {
    harness.restore();
  }
});

test('sync pull resumes from checkpoint cursor', async () => {
  const state = createMockDbState();
  state.inventoryMovements.push(
    {
      event_uuid: '00000000-0000-4000-8000-000000000001',
      pharmacy_id: 1,
      device_id: 'HW-00423',
      barcode: '6250000000010',
      movement_type: 'purchase',
      quantity_delta: 3,
      unit_price_minor: 200,
      currency_code: 'USD',
      reference_type: 'invoice',
      reference_id: 'INV-1',
      metadata: {},
      happened_at: new Date('2026-04-01T00:00:00.000Z').toISOString(),
      version: 1,
      updated_at: new Date('2026-04-01T00:00:00.000Z').toISOString(),
    },
    {
      event_uuid: '00000000-0000-4000-8000-000000000002',
      pharmacy_id: 1,
      device_id: 'HW-00423',
      barcode: '6250000000010',
      movement_type: 'sale',
      quantity_delta: -1,
      unit_price_minor: 240,
      currency_code: 'USD',
      reference_type: 'receipt',
      reference_id: 'RX-2',
      metadata: {},
      happened_at: new Date('2026-04-01T00:05:00.000Z').toISOString(),
      version: 1,
      updated_at: new Date('2026-04-01T00:05:00.000Z').toISOString(),
    },
  );
  const harness = startTestServer(state);

  try {
    const base = apiBase(harness.server);
    const headers = {
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00423',
    };

    const firstPullResp = await fetch(`${base}/pull?limit=1`, { headers });
    assert.equal(firstPullResp.status, 200);
    const firstPullJson = await firstPullResp.json();
    assert.equal(firstPullJson.data.events.length, 1);
    assert.ok(firstPullJson.next_cursor);

    const secondPullResp = await fetch(
      `${base}/pull?limit=1&cursor=${encodeURIComponent(firstPullJson.next_cursor)}`,
      { headers },
    );
    assert.equal(secondPullResp.status, 200);
    const secondPullJson = await secondPullResp.json();
    assert.equal(secondPullJson.data.events.length, 1);
    assert.notEqual(
      secondPullJson.data.events[0].event_uuid,
      firstPullJson.data.events[0].event_uuid,
    );
  } finally {
    harness.restore();
  }
});

test('second device for same pharmacy is rejected when HWID lock is enabled', async () => {
  const state = createMockDbState();
  const harness = startTestServer(state);

  try {
    const base = apiBase(harness.server);
    const headersA = {
      'content-type': 'application/json',
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00423',
    };
    const headersB = {
      'content-type': 'application/json',
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00999',
    };

    const responseA = await fetch(`${base}/push`, {
      method: 'POST',
      headers: headersA,
      body: JSON.stringify(pushBody({
        requestId: 'REQ-DEVICE-A-1',
        events: [
          movementEvent({
            eventId: '61dc6dae-eebc-4aa9-bf53-72fb1af8ea9a',
            movementType: 'sale',
            quantityDelta: -1,
            referenceId: 'RX-A-1',
          }),
        ],
      })),
    });
    assert.equal(responseA.status, 200);

    const responseB = await fetch(`${base}/push`, {
      method: 'POST',
      headers: headersB,
      body: JSON.stringify(pushBody({
        requestId: 'REQ-DEVICE-B-1',
        events: [
          movementEvent({
            eventId: '9f6f3c56-4732-4d6b-a3d8-abcd5f52f7ab',
            movementType: 'purchase',
            quantityDelta: 4,
            referenceType: 'invoice',
            referenceId: 'INV-B-1',
          }),
        ],
      })),
    });
    assert.equal(responseB.status, 403);

    assert.equal(state.inventoryMovements.length, 1);
    const fromA = state.inventoryMovements.find((m) => m.event_uuid === '61dc6dae-eebc-4aa9-bf53-72fb1af8ea9a');
    const fromB = state.inventoryMovements.find((m) => m.event_uuid === '9f6f3c56-4732-4d6b-a3d8-abcd5f52f7ab');
    assert.equal(!!fromA, true);
    assert.equal(!!fromB, false);
  } finally {
    harness.restore();
  }
});

test('unknown pharmacy identity returns 404 instead of generic sync 500', async () => {
  const state = createMockDbState();
  const harness = startTestServer(state);

  try {
    const base = apiBase(harness.server);
    const headers = {
      'content-type': 'application/json',
      'x-license-number': 'LIC-BAD-9999',
      'x-device-id': 'HW-00423',
    };

    const response = await fetch(`${base}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(pushBody({
        requestId: 'REQ-NO-PHARMACY-1',
        events: [
          movementEvent({
            eventId: '5e0fe3b5-1ef6-4ce5-b6fd-a0bc7f81818f',
            movementType: 'purchase',
            quantityDelta: 1,
            referenceType: 'invoice',
            referenceId: 'INV-404-1',
          }),
        ],
      })),
    });

    assert.equal(response.status, 404);
    const json = await response.json();
    assert.equal(String(json.error || '').includes('pharmacy not found'), true);
    assert.equal(state.inventoryMovements.length, 0);
  } finally {
    harness.restore();
  }
});

test('price history and audit log are preserved for price updates', async () => {
  const state = createMockDbState();
  state.prices.push({
    barcode: '6250000000010',
    regulated_price_minor: 450,
    local_price_minor: 300,
    currency_code: 'USD',
    source: 'pos',
    version: 1,
    updated_at: new Date().toISOString(),
    deleted_at: null,
  });

  const harness = startTestServer(state);
  try {
    const base = apiBase(harness.server);
    const headers = {
      'content-type': 'application/json',
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00423',
    };

    const response = await fetch(`${base}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(pushBody({
        requestId: 'REQ-PRICE-AUDIT-1',
        events: [
          priceUpdateEvent({
            eventId: '39edcac6-ab6e-433c-bbe8-812bb0e6b269',
            barcode: '6250000000010',
            newPriceMinor: 360,
          }),
        ],
      })),
    });

    assert.equal(response.status, 200);
    const json = await response.json();
    assert.equal(json.accepted_event_ids.length, 1);

    assert.equal(state.priceHistory.length, 1);
    assert.equal(state.priceHistory[0].previous_price_minor, 300);
    assert.equal(state.priceHistory[0].new_price_minor, 360);

    const priceAudit = state.auditChanges.find((c) => c.entity_type === 'price');
    assert.equal(!!priceAudit, true);
    assert.equal(priceAudit.old_value.local_price_minor, 300);
    assert.equal(priceAudit.new_value.local_price_minor, 360);
  } finally {
    harness.restore();
  }
});

test('duplicate price_update event id across requests is ignored', async () => {
  const state = createMockDbState();
  const harness = startTestServer(state);

  try {
    const base = apiBase(harness.server);
    const headers = {
      'content-type': 'application/json',
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00423',
    };

    const eventId = '8fbfb1fb-a947-43f4-8ea2-8456c431f43d';

    const first = await fetch(`${base}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(pushBody({
        requestId: 'REQ-PRICE-DUP-1',
        events: [priceUpdateEvent({ eventId, newPriceMinor: 410 })],
      })),
    });
    assert.equal(first.status, 200);

    const second = await fetch(`${base}/push`, {
      method: 'POST',
      headers,
      body: JSON.stringify(pushBody({
        requestId: 'REQ-PRICE-DUP-2',
        events: [priceUpdateEvent({ eventId, newPriceMinor: 410 })],
      })),
    });
    assert.equal(second.status, 200);
    const secondJson = await second.json();

    assert.equal(secondJson.duplicate_event_ids.includes(eventId), true);
    assert.equal(state.priceHistory.length, 1);
    assert.equal(state.auditChanges.filter((c) => c.entity_type === 'price').length, 1);
  } finally {
    harness.restore();
  }
});

test('offline sale queues locally, syncs once on recovery, and dashboard reflects alert data', async () => {
  const localOutbox = [];
  const offlineEvent = movementEvent({
    eventId: '8ef10438-bf60-4dd7-8d07-46e6fcfef161',
    movementType: 'sale',
    quantityDelta: -1,
    unitPriceMinor: 700,
    referenceId: 'RX-OFFLINE-1',
  });

  // Backend unavailable: POS keeps event queued locally.
  let backendUnavailable = false;
  try {
    await fetch('http://127.0.0.1:1/api/sync/push', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-pharmacy-id': '1',
        'x-device-id': 'HW-00423',
      },
      body: JSON.stringify(pushBody({ requestId: 'REQ-OFFLINE-ATTEMPT', events: [offlineEvent] })),
      signal: AbortSignal.timeout(500),
    });
  } catch {
    backendUnavailable = true;
    localOutbox.push(offlineEvent);
  }

  assert.equal(backendUnavailable, true);
  assert.equal(localOutbox.length, 1);

  const state = createMockDbState();
  const harness = startTestServer(state);

  try {
    const syncBase = apiBase(harness.server);
    const webBase = syncBase.replace('/api/sync', '/api/web');

    const syncHeaders = {
      'content-type': 'application/json',
      'x-pharmacy-id': '1',
      'x-device-id': 'HW-00423',
    };

    const firstSync = await fetch(`${syncBase}/push`, {
      method: 'POST',
      headers: syncHeaders,
      body: JSON.stringify(pushBody({ requestId: 'REQ-OFFLINE-RECOVERY-1', events: localOutbox })),
    });
    assert.equal(firstSync.status, 200);
    const firstSyncJson = await firstSync.json();
    assert.equal(firstSyncJson.status, 'success');
    assert.equal(firstSyncJson.accepted_event_ids.length, 1);

    const secondSync = await fetch(`${syncBase}/push`, {
      method: 'POST',
      headers: syncHeaders,
      body: JSON.stringify(pushBody({ requestId: 'REQ-OFFLINE-RECOVERY-2', events: localOutbox })),
    });
    assert.equal(secondSync.status, 200);
    const secondSyncJson = await secondSync.json();
    assert.equal(secondSyncJson.duplicate_event_ids.includes('8ef10438-bf60-4dd7-8d07-46e6fcfef161'), true);
    assert.equal(state.inventoryMovements.length, 1);

    const dashboardAlertsResp = await fetch(`${webBase}/compliance-alerts?only_open=true&limit=20`);
    assert.equal(dashboardAlertsResp.status, 200);
    const dashboardAlerts = await dashboardAlertsResp.json();
    assert.equal(dashboardAlerts.status, 'success');
    assert.equal(dashboardAlerts.count > 0, true);
  } finally {
    harness.restore();
  }
});
