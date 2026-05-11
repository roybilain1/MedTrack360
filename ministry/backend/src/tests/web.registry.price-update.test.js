const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const db = require('../db');
const webRoutes = require('../routes/web');

function createHarness() {
  const app = express();
  app.use(express.json());
  app.use('/api/web', webRoutes);

  const state = {
    priceById: new Map([[1, 20.0]]),
    changeLog: [],
  };

  const originalQuery = db.query;
  db.query = async (sql, params = []) => {
    const q = String(sql).replace(/\s+/g, ' ').trim().toLowerCase();

    if (q.startsWith('select moph_ceiling from moph_registry where id=')) {
      const id = Number(params[0]);
      const price = state.priceById.get(id);
      return { rows: price == null ? [] : [{ moph_ceiling: price }], rowCount: price == null ? 0 : 1 };
    }

    if (q.startsWith('update moph_registry set moph_ceiling=')) {
      const nextPrice = Number(params[0]);
      const id = Number(params[1]);
      if (!state.priceById.has(id)) {
        return { rows: [], rowCount: 0 };
      }
      state.priceById.set(id, nextPrice);
      return {
        rows: [{ id, barcode: '6250000000010', trade_name: 'Amoxil', dosage: '500mg', moph_ceiling: nextPrice }],
        rowCount: 1,
      };
    }

    if (q.startsWith('insert into change_log')) {
      state.changeLog.push({
        change_type: params[0],
        entity_id: String(params[1]),
        old_value: JSON.parse(params[3]),
        new_value: JSON.parse(params[4]),
      });
      return { rows: [], rowCount: 1 };
    }

    throw new Error(`Unhandled SQL in web.registry.price-update test mock: ${q}`);
  };

  const server = app.listen(0);
  return {
    server,
    state,
    restore() {
      db.query = originalQuery;
      server.close();
    },
  };
}

test('registry price update persists authoritative price and logs change', async () => {
  const h = createHarness();

  try {
    const { port } = h.server.address();
    const response = await fetch(`http://127.0.0.1:${port}/api/web/registry/1/price`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ price: 50 }),
    });

    assert.equal(response.status, 200);
    const json = await response.json();
    assert.equal(json.status, 'success');
    assert.equal(json.data.moph_ceiling, 50);

    assert.equal(h.state.priceById.get(1), 50);
    assert.equal(h.state.changeLog.length, 1);
    assert.equal(h.state.changeLog[0].change_type, 'price_update');
    assert.equal(h.state.changeLog[0].old_value.price, 20);
    assert.equal(h.state.changeLog[0].new_value.price, 50);
  } finally {
    h.restore();
  }
});
