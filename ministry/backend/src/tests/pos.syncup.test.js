const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const db = require('../db');
const posRoutes = require('../routes/pos');

function createState() {
  return {
    pharmacies: [
      {
        id: 1,
        name: 'Al-Amin Pharmacy',
        license_number: 'LIC-BEY-0041',
        hwid: 'HW-00423',
        region: 'Beirut',
      },
    ],
    purchaseItems: [],
    movements: [],
    medicineRequests: [],
  };
}

function makeClient(state) {
  return {
    async query(sql, params = []) {
      const q = String(sql).replace(/\s+/g, ' ').trim().toLowerCase();

      if (q === 'begin' || q === 'commit' || q === 'rollback') {
        return { rows: [], rowCount: 0 };
      }

      if (q.includes('select * from pharmacies where id =')) {
        const row = state.pharmacies.find((p) => p.id === Number(params[0]));
        return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
      }

      if (q.includes('update pharmacies set')) {
        return { rows: [state.pharmacies[0]], rowCount: 1 };
      }

      if (q.includes('insert into pos_inventory_movements')) {
        state.movements.push({ movement_uuid: params[0], barcode: params[4] });
        return { rows: [{ movement_uuid: params[0] }], rowCount: 1 };
      }

      if (q.includes('insert into inventory_movements')) {
        return { rows: [], rowCount: 1 };
      }

      if (q.includes('select trade_name, dosage, category, moph_ceiling, is_blocked from moph_registry')) {
        return {
          rows: [
            {
              trade_name: 'Paracetamol',
              dosage: '500mg',
              category: 'Analgesic',
              moph_ceiling: 4.5,
              is_blocked: false,
            },
          ],
          rowCount: 1,
        };
      }

      if (q.includes('insert into purchases')) {
        return { rows: [], rowCount: 1 };
      }

      if (q.includes('select id from purchases where purchase_uuid =')) {
        return { rows: [{ id: 10 }], rowCount: 1 };
      }

      if (q.includes('insert into purchase_items')) {
        state.purchaseItems.push({ barcode: params[2], product_name: params[3] });
        return { rows: [], rowCount: 1 };
      }

      if (q.includes('insert into national_stock')) {
        return { rows: [], rowCount: 1 };
      }

      if (q.includes('with flow as')) {
        return { rows: [{ incoming: 1, outgoing: 1, ratio: 1 }], rowCount: 1 };
      }

      if (q.includes('insert into sync_outbox')) {
        return { rows: [], rowCount: 1 };
      }

      if (q.includes('insert into pos_sync_state')) {
        return { rows: [], rowCount: 1 };
      }

      if (q.includes('insert into sync_checkpoint')) {
        return { rows: [], rowCount: 1 };
      }

      if (q.includes('insert into medicine_registration_requests')) {
        state.medicineRequests.push({
          request_uuid: params[0],
          pharmacy_id: params[1],
          barcode: params[3],
          requested_name: params[4],
        });
        return { rows: [{ id: 1 }], rowCount: 1 };
      }

      if (q.includes('insert into audit_logs')) {
        return { rows: [], rowCount: 1 };
      }

      if (q.includes('insert into compliance_alerts')) {
        return { rows: [], rowCount: 1 };
      }

      throw new Error(`Unhandled SQL in pos.syncup test mock: ${q}`);
    },
    release() {},
  };
}

function startServer(state) {
  const app = express();
  app.use(express.json());
  app.use('/api/pos', posRoutes);

  const originalConnect = db.pool.connect;
  db.pool.connect = async () => makeClient(state);

  const server = app.listen(0);
  return {
    server,
    restore() {
      db.pool.connect = originalConnect;
      server.close();
    },
  };
}

test('sync-up purchase movement persists purchase item without runtime crash', async () => {
  const state = createState();
  const harness = startServer(state);

  try {
    const { port } = harness.server.address();
    const response = await fetch(`http://127.0.0.1:${port}/api/pos/sync-up`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        pharmacy_id: 1,
        hwid: 'HW-00423',
        movements: [
          {
            movement_uuid: '1a5f1d65-6f56-493b-9bd4-d4dfec17da17',
            barcode: '6250000000010',
            movement_type: 'purchase',
            quantity_delta: 12,
            unit_price_minor: 250,
            currency_code: 'USD',
            reference_type: 'invoice',
            reference_id: 'INV-200',
            metadata: JSON.stringify({ supplier_name: 'ACME', invoice_number: 'INV-200' }),
            happened_at: Date.now(),
            updated_at: Date.now(),
            version: 1,
          },
        ],
      }),
    });

    assert.equal(response.status, 200);
    const json = await response.json();
    assert.equal(json.status, 'success');
    assert.equal(state.purchaseItems.length, 1);
    assert.equal(state.purchaseItems[0].product_name, 'Paracetamol 500mg');
  } finally {
    harness.restore();
  }
});

test('sync-up accepts medicine_request_submitted event in legacy adapter', async () => {
  const state = createState();
  const harness = startServer(state);

  try {
    const { port } = harness.server.address();
    const eventId = '8a05c936-7675-4bae-a7e5-2d9d881ea78f';
    const response = await fetch(`http://127.0.0.1:${port}/api/pos/sync-up`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        pharmacy_id: 1,
        hwid: 'HW-00423',
        events: [
          {
            event_id: eventId,
            event_type: 'medicine_request_submitted',
            payload: {
              request_uuid: eventId,
              barcode: '1234',
              requested_name: 'Amoxil',
              dosage: '500mg',
              category: 'Antibiotic',
              proposed_price: 4.5,
              stock: 10,
              expiry: '2027-01-01',
              request_status: 'pending_review',
            },
          },
        ],
      }),
    });

    assert.equal(response.status, 200);
    const json = await response.json();
    assert.equal(json.status, 'success');
    assert.equal(json.accepted_event_ids.includes(eventId), true);
    assert.equal(state.medicineRequests.length, 1);
    assert.equal(state.medicineRequests[0].barcode, '1234');
  } finally {
    harness.restore();
  }
});
