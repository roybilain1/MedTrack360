const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const db = require('../db');
const webRoutes = require('../routes/web');

function createAppWithMockDb() {
  const app = express();
  app.use(express.json());
  app.use('/api/web', webRoutes);

  const originalQuery = db.query;
  db.query = async (sql, params = []) => {
    const text = String(sql).replace(/\s+/g, ' ').toLowerCase();

    if (text.includes('from moph_registry r') && text.includes('left join national_stock')) {
      return {
        rows: [{
          id: 1,
          barcode: '6250',
          trade_name: 'Paracetamol',
          reg_number: 'REG-1',
          dosage: '500mg',
          category: 'Analgesic',
          moph_ceiling: 2.2,
          stock_units: 18,
          stock_status: 'safe',
          threshold: 10,
        }],
        rowCount: 1,
      };
    }

    if (text.includes('from audit_logs') && text.includes("event_type = 'price_hike'") && text.includes('metadata->>\'receipt_id\'')) {
      return {
        rows: [{
          id: 10,
          event_id: 'EVT-10',
          pharmacy_name: 'Al-Amin Pharmacy',
          hwid: 'HW-00423',
          license_number: 'LIC-BEY-0041',
          region: 'Beirut',
          event_type: 'price_hike',
          item_name: 'Paracetamol 500mg',
          registry_price: 2.1,
          charged_price: 2.7,
          unit_count: 2,
          metadata: { receipt_id: 'R-1' },
          created_at: new Date('2026-04-08T09:00:00.000Z').toISOString(),
        }],
        rowCount: 1,
      };
    }

    if (text.includes('from audit_logs') && text.includes('count(*) over()::int as total_count')) {
      return {
        rows: [{
          id: 20,
          event_id: 'EVT-20',
          event_type: 'sale',
          pharmacy_name: 'Al-Amin Pharmacy',
          total_count: 1,
          created_at: new Date('2026-04-08T09:01:00.000Z').toISOString(),
        }],
        rowCount: 1,
      };
    }

    if (text.includes('select * from pharmacies order by name asc, id asc')) {
      return {
        rows: [{
          id: 3,
          name: 'Al-Amin Pharmacy',
          hwid: 'HW-00423',
          license_number: 'LIC-BEY-0041',
          region: 'Beirut',
          status: 'online',
        }],
        rowCount: 1,
      };
    }

    if (text.includes('from compliance_alerts c') && text.includes('count(*) over()::int as total_count')) {
      return {
        rows: [{
          id: 4,
          pharmacy_id: 3,
          alert_type: 'high_price',
          status: 'open',
          pharmacy_name: 'Al-Amin Pharmacy',
          license_number: 'LIC-BEY-0041',
          total_count: 1,
          created_at: new Date('2026-04-08T09:02:00.000Z').toISOString(),
        }],
        rowCount: 1,
      };
    }

    if (text.includes('from registration_requests') && text.includes('count(*) over()::int as total_count')) {
      return {
        rows: [{
          id: 5,
          reg_id: 'REG-REQ-1',
          name: 'New Pharmacy',
          status: 'pending_review',
          submitted_date: '2026-04-08',
          total_count: 1,
        }],
        rowCount: 1,
      };
    }

    if (text.includes('from medicine_registration_requests m') && text.includes('count(*) over()::int as total_count')) {
      return {
        rows: [{
          id: 7,
          request_uuid: '8a05c936-7675-4bae-a7e5-2d9d881ea78f',
          barcode: '1234',
          requested_name: 'Amoxil',
          dosage: '500mg',
          category: 'Antibiotic',
          request_status: 'pending_review',
          pharmacy_name: 'Al-Amin Pharmacy',
          license_number: 'LIC-BEY-0041',
          region: 'Beirut',
          total_count: 1,
          created_at: new Date('2026-04-08T09:06:00.000Z').toISOString(),
        }],
        rowCount: 1,
      };
    }

    if (text.includes('from national_stock ns')) {
      return {
        rows: [{
          id: 6,
          barcode: '6250',
          medication_name: 'Paracetamol 500mg',
          category: 'Analgesic',
          stock_units: 12,
          threshold: 20,
          status: 'low',
          region: 'Beirut',
          last_sync: 'just now',
          pharmacy_name: 'Al-Amin Pharmacy',
          license_number: 'LIC-BEY-0041',
        }],
        rowCount: 1,
      };
    }

    if (text.includes('select * from scored') && text.includes('where pharmacy_name is not null')) {
      return {
        rows: [{
          id: 1,
          pharmacy_name: 'Al-Amin Pharmacy',
          license_number: 'LIC-BEY-0041',
          hwid: 'HW-00423',
          region: 'Beirut',
          incoming_units: 50,
          outgoing_units: 10,
          ratio: 5,
          score: 100,
          flag: 'critical',
          flagged_items: ['Paracetamol'],
        }],
        rowCount: 1,
      };
    }

    if (text.includes('from scored') && text.includes('where id = $1')) {
      return {
        rows: [{ pharmacy_name: 'Al-Amin Pharmacy', license_number: 'LIC-BEY-0041' }],
        rowCount: 1,
      };
    }

    if (text.includes('with weeks as')) {
      return {
        rows: [
          { week: 'Wk 14', incoming: 5, outgoing: 2 },
          { week: 'Wk 15', incoming: 7, outgoing: 4 },
        ],
        rowCount: 2,
      };
    }

    if (text.includes('select * from moph_registry where barcode=$1')) {
      return {
        rows: [{
          id: 1,
          barcode: params[0] || '6250',
          trade_name: 'Paracetamol',
          dosage: '500mg',
          reg_number: 'REG-1',
          manufacturer: 'ACME',
          category: 'Analgesic',
          created_at: new Date('2026-01-01T00:00:00.000Z').toISOString(),
          updated_at: new Date('2026-04-08T09:30:00.000Z').toISOString(),
        }],
        rowCount: 1,
      };
    }

    if (text.includes('from pharmacies p') && text.includes('left join pos_sync_state s on s.hwid = p.hwid')) {
      return {
        rows: [{
          id: 3,
          hwid: 'HW-00423',
          name: 'Al-Amin Pharmacy',
          license_number: 'LIC-BEY-0041',
          region: 'Beirut',
          sync_version: '2.6.1',
          status: 'online',
          sync_pct: 98,
          last_seen: new Date('2026-04-08T09:05:00.000Z').toISOString(),
          last_sync_up: new Date('2026-04-08T09:04:00.000Z').toISOString(),
          last_sync_down: new Date('2026-04-08T09:02:00.000Z').toISOString(),
          pending_outbox: 1,
          open_compliance_alerts: 0,
          registration_status: 'approved',
        }],
        rowCount: 1,
      };
    }

    if (text.includes('count(*)::int as total_terminals') && text.includes('from pharmacies')) {
      return {
        rows: [{
          total_terminals: 1,
          online_count: 1,
          offline_count: 0,
          degraded_count: 0,
          unknown_version_count: 0,
          never_seen_count: 0,
        }],
        rowCount: 1,
      };
    }

    if (text.includes('count(*) filter (where moph_ceiling is not null)::int as regulated_medicine_count') && text.includes('from moph_registry')) {
      return {
        rows: [{
          regulated_medicine_count: 125,
          high_price_violations: 2,
          last_registry_sync: new Date('2026-04-08T08:00:00.000Z').toISOString(),
          last_price_event_at: new Date('2026-04-08T09:00:00.000Z').toISOString(),
        }],
        rowCount: 1,
      };
    }

    if (text.includes("coalesce(metadata->>'barcode', '') as barcode") && text.includes('from audit_logs') && text.includes("event_type = 'price_hike'")) {
      return {
        rows: [{
          item_name: 'Paracetamol 500mg',
          barcode: '6250',
          pharmacy_name: 'Al-Amin Pharmacy',
          license_number: 'LIC-BEY-0041',
          registry_price: 2.1,
          charged_price: 2.7,
          status: 'violation',
          created_at: new Date('2026-04-08T09:00:00.000Z').toISOString(),
        }],
        rowCount: 1,
      };
    }

    if (text.includes('select reason from adjustment_reasons')) {
      return { rows: [{ reason: 'Manual adjustment' }], rowCount: 1 };
    }

    if (text.includes('from audit_logs') && text.includes("event_type = 'stock_adjust'") && text.includes('limit 10')) {
      return {
        rows: [{
          pharmacy_name: 'Al-Amin Pharmacy',
          item_name: 'Paracetamol 500mg',
          unit_count: -3,
          reason: 'Damaged',
          source: 'manual_adjustment',
          created_at: new Date('2026-04-08T09:10:00.000Z').toISOString(),
        }],
        rowCount: 1,
      };
    }

    if (text.includes('count(*)::int as total_adjustments') && text.includes("interval '30 days'")) {
      return {
        rows: [{
          total_adjustments: 11,
          adjustments_last_30d: 4,
          last_adjustment_at: new Date('2026-04-08T09:10:00.000Z').toISOString(),
        }],
        rowCount: 1,
      };
    }

    if (text.includes('coalesce(nullif(metadata->>\'reason\', \'\'), \'unspecified\') as reason') && text.includes('usage_count')) {
      return {
        rows: [{ reason: 'Damaged', usage_count: 3 }],
        rowCount: 1,
      };
    }

    throw new Error(`Unhandled SQL in web.read.contracts test mock: ${text} :: ${JSON.stringify(params)}`);
  };

  const server = app.listen(0);
  return {
    server,
    restore() {
      db.query = originalQuery;
      server.close();
    },
  };
}

function base(server) {
  const { port } = server.address();
  return `http://127.0.0.1:${port}/api/web`;
}

test('web read routes return stable list contracts for registry/audit/pharmacies/compliance/registration', async () => {
  const h = createAppWithMockDb();
  try {
    const b = base(h.server);

    const registry = await fetch(`${b}/registry`).then((r) => r.json());
    assert.equal(registry.status, 'success');
    assert.equal(registry.pagination.total, 1);
    assert.equal(registry.meta.sort.by, 'trade_name');

    const audits = await fetch(`${b}/audit-logs?page=1&limit=10`).then((r) => r.json());
    assert.equal(audits.status, 'success');
    assert.equal(audits.pagination.total, 1);
    assert.equal(audits.meta.empty, false);

    const pharmacies = await fetch(`${b}/pharmacies`).then((r) => r.json());
    assert.equal(pharmacies.status, 'success');
    assert.equal(pharmacies.meta.sort.by, 'name,id');

    const compliance = await fetch(`${b}/compliance-alerts?only_open=true&limit=10`).then((r) => r.json());
    assert.equal(compliance.status, 'success');
    assert.equal(compliance.pagination.total, 1);
    assert.equal(compliance.meta.filters.only_open, true);

    const regs = await fetch(`${b}/registration-requests?status=pending_review&limit=10`).then((r) => r.json());
    assert.equal(regs.status, 'success');
    assert.equal(regs.pagination.total, 1);
    assert.equal(regs.meta.filters.status, 'pending_review');

    const medReqs = await fetch(`${b}/medicine-requests?status=pending_review&limit=10`).then((r) => r.json());
    assert.equal(medReqs.status, 'success');
    assert.equal(medReqs.pagination.total, 1);
    assert.equal(medReqs.data[0].barcode, '1234');
  } finally {
    h.restore();
  }
});

test('web read routes for shortage/hoarding/settings/traceability expose render-safe defaults and metadata', async () => {
  const h = createAppWithMockDb();
  try {
    const b = base(h.server);

    const shortage = await fetch(`${b}/shortage`).then((r) => r.json());
    assert.equal(shortage.status, 'success');
    assert.equal(shortage.pagination.total, 1);
    assert.equal(shortage.meta.sort.by, 'status,medication_name,barcode,id');

    const anomalies = await fetch(`${b}/hoarding-anomalies`).then((r) => r.json());
    assert.equal(anomalies.status, 'success');
    assert.equal(anomalies.data[0].flag, 'critical');
    assert.equal(anomalies.meta.count, 1);

    const trend = await fetch(`${b}/hoarding-anomalies/1/trend`).then((r) => r.json());
    assert.equal(trend.status, 'success');
    assert.equal(trend.data.length, 2);
    assert.equal(trend.meta.filters.pharmacy_name, 'Al-Amin Pharmacy');

    const settings = await fetch(`${b}/settings-data`).then((r) => r.json());
    assert.equal(settings.status, 'success');
    assert.equal(Array.isArray(settings.data.terminals), true);
    assert.equal(Array.isArray(settings.data.recent_price_events), true);
    assert.equal(Array.isArray(settings.data.adjustment_reasons), true);
    assert.equal(Array.isArray(settings.data.recent_adjustments), true);
    assert.equal(Array.isArray(settings.data.top_adjustment_reasons), true);
    assert.equal(typeof settings.data.terminal_summary, 'object');
    assert.equal(typeof settings.data.pricing_policy, 'object');
    assert.equal(typeof settings.data.adjustment_summary, 'object');
    assert.equal(typeof settings.meta.generated_at, 'string');

    const custody = await fetch(`${b}/chain-of-custody/6250`).then((r) => r.json());
    assert.equal(custody.status, 'success');
    assert.equal(custody.data.medication_name, 'Paracetamol');
    assert.equal(custody.data.name, 'Paracetamol');
    assert.equal(typeof custody.data.updated_at, 'string');
  } finally {
    h.restore();
  }
});

test('price violation summary returns real data only with predictable ordering', async () => {
  const h = createAppWithMockDb();
  try {
    const b = base(h.server);

    const summary = await fetch(`${b}/price-violations-summary?limit=3`).then((r) => r.json());
    assert.equal(summary.status, 'success');
    assert.equal(Array.isArray(summary.data), true);
    assert.equal(summary.pagination.total, summary.data.length);
    assert.equal(summary.meta.sort.by, 'created_at');
  } finally {
    h.restore();
  }
});
