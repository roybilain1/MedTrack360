const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const db = require('../db');
const monitoringRoutes = require('../routes/monitoring');

function createAppWithMockDb() {
  const app = express();
  app.use('/api/web/monitoring', monitoringRoutes);

  const originalQuery = db.query;
  db.query = async (sql, params = []) => {
    const text = String(sql).replace(/\s+/g, ' ').toLowerCase();

    if (text.includes('select (select high_price_count from pricing_flags)')) {
      return { rows: [{ high_price_count: 2, hoarding_count: 1, unhealthy_pharmacies: 1, total_pharmacies: 4, open_alerts: 5 }], rowCount: 1 };
    }

    if (text.includes('grouped as') && text.includes('from filtered f')) {
      return {
        rows: [{
          pharmacy_name: 'Al-Amin',
          license_number: 'LIC-1',
          hwid: 'HW-1',
          region: 'Beirut',
          medicine_name: 'Paracetamol',
          dosage: '500mg',
          category: 'Analgesic',
          barcode: '6250',
          stock_units: 20,
          threshold_units: 30,
          sales_30d: 30,
          purchases_30d: 40,
          avg_daily_sales: 1,
          days_of_stock: 20,
          coverage_basis: 'recent_sales_30d',
          status_basis: 'near_threshold_or_low_coverage',
          status: 'low',
          risk_rank: 2,
          current_price_minor: 1200,
          regulated_price_minor: 2000,
          expiry_at: '2026-12-01T00:00:00.000Z',
          active_pharmacies: 1,
          total_count: 1,
        }],
        rowCount: 1,
      };
    }

    if (text.includes('from with_rule')) {
      return {
        rows: [{ pharmacy_name: 'Al-Amin', medicine_name: 'Paracetamol', barcode: '6250', status: 'high_price', total_count: 1 }],
        rowCount: 1,
      };
    }

    if (text.includes('from tagged')) {
      return {
        rows: [{ pharmacy_name: 'Al-Amin', medicine_name: 'Paracetamol', alert_type: 'high_days_of_stock', total_count: 1 }],
        rowCount: 1,
      };
    }

    if (text.includes('from health')) {
      return {
        rows: [{ pharmacy_name: 'Al-Amin', health_status: 'overdue_sync', total_count: 1 }],
        rowCount: 1,
      };
    }

    if (text.includes('from medicine_rows')) {
      return {
        rows: [{ source: 'movement', barcode: '6250', medicine_name: 'Paracetamol' }],
        rowCount: 1,
      };
    }

    if (text.includes('with price_history_events as') && text.includes('from ranked')) {
      assert.equal(text.includes('join moph_registry mr on mr.id = cl.entity_id'), true);
      assert.equal(text.includes('mr.id::text = cl.entity_id'), false);
      assert.equal(typeof params[2], 'string');
      return {
        rows: [{
          event_id: 'ph-1',
          source_family: 'price_history',
          event_type: 'branch_price_edit',
          source_label: 'Branch price edit',
          pharmacy_name: 'Al-Amin',
          license_number: 'LIC-1',
          hwid: 'HW-1',
          region: 'Beirut',
          barcode: '6250',
          medicine_name: 'Paracetamol',
          previous_price_minor: 400,
          new_price_minor: 500,
          currency_code: 'USD',
          source: 'pos',
          changed_by: 'device-1',
          changed_at: new Date().toISOString(),
          regulated_price_minor: 450,
          change_pct: 0.25,
          status: 'high_price',
          suspicious_jump: true,
          is_system_event: false,
          total_count: 1,
        }],
        rowCount: 1,
      };
    }

    if (text.includes('with latest_alert as') && text.includes('from all_events')) {
      return {
        rows: [{
          event_uuid: 'evt-1',
          event_family: 'compliance',
          event_type: 'price_violation',
          event_title: 'Sold above regulated ceiling',
          event_summary: 'Derived from compliance alert stream',
          severity: 'high',
          pharmacy_name: 'Al-Amin',
          license_number: 'LIC-1',
          hwid: 'HW-1',
          region: 'Beirut',
          medicine_name: 'Paracetamol',
          barcode: '6250',
          quantity_delta: 4,
          regulated_price_minor: 200,
          actual_price_minor: 260,
          source: 'pos',
          outcome: 'warning',
          linked_alert_id: 'a1',
          chain_key: 'pharmacy:1|barcode:6250',
          event_time: new Date().toISOString(),
          metadata: {},
          is_system_event: false,
          total_count: 1,
        }],
        rowCount: 1,
      };
    }

    if (text.includes('from rows')) {
      return {
        rows: [{ history_uuid: 'h1', barcode: '6250', suspicious_jump: true, total_count: 1 }],
        rowCount: 1,
      };
    }

    if (text.includes("'compliance'::text as source")) {
      return { rows: [{ source: 'compliance', source_id: 'a1', alert_type: 'price_violation', status: 'open', created_at: new Date().toISOString() }], rowCount: 1 };
    }

    if (text.includes("concat('high-price-'")) {
      return { rows: [], rowCount: 0 };
    }

    if (text.includes("concat('hoarding-'")) {
      return { rows: [], rowCount: 0 };
    }

    if (text.includes("concat('price-jump-'")) {
      return { rows: [], rowCount: 0 };
    }

    if (text.includes('from compliance_alerts where alert_uuid::text =')) {
      return { rows: [{ alert_uuid: 'a1', title: 'x' }], rowCount: 1 };
    }

    throw new Error(`Unhandled SQL in monitoring test mock: ${text} :: ${JSON.stringify(params)}`);
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
  return `http://127.0.0.1:${port}/api/web/monitoring`;
}

test('monitoring overview and list endpoints return success payloads', async () => {
  const h = createAppWithMockDb();
  try {
    const b = base(h.server);

    const overview = await fetch(`${b}/overview`).then((r) => r.json());
    assert.equal(overview.status, 'success');
    assert.equal(overview.data.high_price_count, 2);
    assert.equal(typeof overview.meta?.generated_at, 'string');
    assert.equal(overview.rules.markupThreshold, 0.15);

    const stock = await fetch(`${b}/stock`).then((r) => r.json());
    assert.equal(stock.status, 'success');
    assert.equal(stock.data.length, 1);
    assert.equal(stock.pagination.total, 1);
    assert.equal(stock.meta.sort.by, 'risk_rank');
    assert.equal(stock.rules.minimumDailyRate, 0.25);
    assert.equal(stock.scope.active_pharmacies, 1);
    assert.equal(typeof stock.scope.scope_label, 'string');

    const pricing = await fetch(`${b}/pricing`).then((r) => r.json());
    assert.equal(pricing.status, 'success');
    assert.equal(pricing.meta.sort.by, 'markup_pct');
    assert.equal(pricing.rules.markupThreshold, 0.15);

    const hoarding = await fetch(`${b}/hoarding-alerts`).then((r) => r.json());
    assert.equal(hoarding.status, 'success');
    assert.equal(hoarding.meta.sort.by, 'days_of_stock');
    assert.equal(hoarding.rules.daysOfStockCritical, 60);

    const sync = await fetch(`${b}/sync-health`).then((r) => r.json());
    assert.equal(sync.status, 'success');
    assert.equal(sync.meta.sort.by, 'hours_since_sync');
    assert.equal(sync.rules.syncOverdueHours, 12);
  } finally {
    h.restore();
  }
});

test('monitoring detail and alerts endpoints return data', async () => {
  const h = createAppWithMockDb();
  try {
    const b = base(h.server);

    const medicine = await fetch(`${b}/medicine-history?medicine=6250`).then((r) => r.json());
    assert.equal(medicine.status, 'success');
    assert.equal(medicine.pagination.totalPages >= 1, true);
    assert.equal(medicine.meta.filters.medicine, '6250');

    const audit = await fetch(`${b}/pharmacy-audit`).then((r) => r.json());
    assert.equal(audit.status, 'success');
    assert.equal(audit.pagination.total, 1);
    assert.equal(audit.meta.sort.by, 'event_time');
    assert.equal(audit.data[0].event_family, 'compliance');
    assert.equal(audit.data[0].event_title.includes('regulated'), true);

    const feed = await fetch(`${b}/audit-feed?includeSystem=false`).then((r) => r.json());
    assert.equal(feed.status, 'success');
    assert.equal(feed.pagination.total, 1);
    assert.equal(feed.meta.sort.by, 'event_time');
    assert.equal(feed.scope.default_view_policy, 'business_and_compliance_events');

    const priceHistory = await fetch(`${b}/price-history`).then((r) => r.json());
    assert.equal(priceHistory.status, 'success');
    assert.equal(priceHistory.rules.jumpWindowDays, 7);
    assert.equal(priceHistory.meta.sort.by, 'changed_at');
    assert.equal(priceHistory.pagination.total, 1);
    assert.equal(priceHistory.data[0].source_label, 'Branch price edit');
    assert.equal(Number(priceHistory.data[0].previous_price_minor), 400);
    assert.equal(Number(priceHistory.data[0].new_price_minor), 500);
    assert.equal(Number(priceHistory.data[0].change_pct), 0.25);

    const alerts = await fetch(`${b}/alerts`).then((r) => r.json());
    assert.equal(alerts.status, 'success');
    assert.equal(alerts.data.length, 1);
    assert.equal(typeof alerts.data[0].alert_id, 'string');
    assert.equal(typeof alerts.data[0].id, 'string');
    assert.equal(typeof alerts.data[0].source_id, 'string');
    assert.equal(typeof alerts.data[0].created_at, 'string');
    assert.equal(alerts.meta.sort.by, 'created_at');

    const alertId = alerts.data[0].alert_id;
    const alert = await fetch(`${b}/alerts/${encodeURIComponent(alertId)}`).then((r) => r.json());
    assert.equal(alert.status, 'success');
    assert.equal(alert.data.alert_id, alertId);
    assert.equal(typeof alert.data.alert_uuid, 'string');
    assert.equal(alert.data.source, 'compliance');
  } finally {
    h.restore();
  }
});

test('monitoring highlights overdue sync and hoarding indicators', async () => {
  const h = createAppWithMockDb();
  try {
    const b = base(h.server);

    const overview = await fetch(`${b}/overview?syncOverdueHours=6`).then((r) => r.json());
    assert.equal(overview.status, 'success');
    assert.equal(overview.data.hoarding_count, 1);
    assert.equal(overview.data.unhealthy_pharmacies, 1);

    const sync = await fetch(`${b}/sync-health?status=overdue_sync`).then((r) => r.json());
    assert.equal(sync.status, 'success');
    assert.equal(sync.data[0].health_status, 'overdue_sync');
  } finally {
    h.restore();
  }
});

test('stock endpoint preserves non-computable coverage for positive stock with no demand history', async () => {
  const app = express();
  app.use('/api/web/monitoring', monitoringRoutes);

  const originalQuery = db.query;
  db.query = async (sql) => {
    const text = String(sql).replace(/\s+/g, ' ').toLowerCase();

    if (text.includes('grouped as') && text.includes('from filtered f')) {
      return {
        rows: [
          {
            pharmacy_name: 'Al-Amin',
            barcode: '6250',
            dosage: '500mg',
            stock_units: 10,
            sales_30d: 0,
            purchases_30d: 2,
            days_of_stock: null,
            coverage_basis: 'no_demand_history',
            status: 'unknown',
            status_basis: 'insufficient_demand_and_threshold',
            risk_rank: 4,
            current_price_minor: 1200,
            regulated_price_minor: 2000,
            expiry_at: null,
            total_count: 1,
            active_pharmacies: 1,
          },
        ],
        rowCount: 1,
      };
    }

    throw new Error(`Unhandled SQL in stock semantics test mock: ${text}`);
  };

  const server = app.listen(0);
  try {
    const b = base(server);
    const stock = await fetch(`${b}/stock`).then((r) => r.json());
    assert.equal(stock.status, 'success');
    assert.equal(stock.data.length, 1);
    assert.equal(stock.data[0].stock_units, 10);
    assert.equal(stock.data[0].days_of_stock, null);
    assert.equal(stock.data[0].coverage_basis, 'no_demand_history');
    assert.equal(stock.data[0].status, 'unknown');
    assert.equal(stock.data[0].dosage, '500mg');
  } finally {
    db.query = originalQuery;
    server.close();
  }
});

test('pricing uses latest price-change state instead of stale historical sales', async () => {
  const app = express();
  app.use('/api/web/monitoring', monitoringRoutes);

  const originalQuery = db.query;
  db.query = async (sql) => {
    const text = String(sql).replace(/\s+/g, ' ').toLowerCase();

    if (text.includes('from with_rule')) {
      assert.equal(text.includes("im.movement_type = 'price_change'"), true);
      assert.equal(text.includes('from price_history ph'), true);
      assert.equal(text.includes('from prices pr'), true);
      return {
        rows: [
          {
            pharmacy_name: 'Al-Amin Pharmacy',
            medicine_name: 'Amoxil',
            barcode: '6289201012345',
            regulated_price_minor: 2000,
            avg_selling_price_minor: 4000,
            markup_pct: 1,
            status: 'high_price',
            total_count: 1,
          },
        ],
        rowCount: 1,
      };
    }

    throw new Error(`Unhandled SQL in pricing source test mock: ${text}`);
  };

  const server = app.listen(0);
  try {
    const b = base(server);
    const pricing = await fetch(`${b}/pricing`).then((r) => r.json());
    assert.equal(pricing.status, 'success');
    assert.equal(pricing.data.length, 1);
    assert.equal(pricing.data[0].medicine_name, 'Amoxil');
    assert.equal(Number(pricing.data[0].regulated_price_minor), 2000);
    assert.equal(Number(pricing.data[0].avg_selling_price_minor), 4000);
    assert.equal(Number(pricing.data[0].markup_pct), 1);
    assert.equal(pricing.data[0].status, 'high_price');
  } finally {
    db.query = originalQuery;
    server.close();
  }
});

test('pricing includes high-price rows from latest local branch price even when no sale exists', async () => {
  const app = express();
  app.use('/api/web/monitoring', monitoringRoutes);

  const originalQuery = db.query;
  db.query = async (sql) => {
    const text = String(sql).replace(/\s+/g, ' ').toLowerCase();

    if (text.includes('from with_rule')) {
      assert.equal(text.includes('observed_pairs as'), true);
      assert.equal(text.includes('left join sales_price sp'), true);
      assert.equal(text.includes('coalesce(llp.event_time, sp.last_sale_at)'), true);
      return {
        rows: [
          {
            pharmacy_name: 'Al-Amin Pharmacy',
            medicine_name: 'Amoxil',
            barcode: '6289201012345',
            regulated_price_minor: 2000,
            avg_selling_price_minor: 10000,
            markup_pct: 4,
            status: 'high_price',
            total_count: 1,
          },
        ],
        rowCount: 1,
      };
    }

    throw new Error(`Unhandled SQL in no-sale pricing visibility test mock: ${text}`);
  };

  const server = app.listen(0);
  try {
    const b = base(server);
    const pricing = await fetch(`${b}/pricing?medicine=amoxil`).then((r) => r.json());
    assert.equal(pricing.status, 'success');
    assert.equal(pricing.data.length, 1);
    assert.equal(Number(pricing.data[0].regulated_price_minor), 2000);
    assert.equal(Number(pricing.data[0].avg_selling_price_minor), 10000);
    assert.equal(Number(pricing.data[0].markup_pct), 4);
    assert.equal(pricing.data[0].status, 'high_price');
  } finally {
    db.query = originalQuery;
    server.close();
  }
});

test('alerts high-price derivation uses latest price-change state', async () => {
  const app = express();
  app.use('/api/web/monitoring', monitoringRoutes);

  const originalQuery = db.query;
  db.query = async (sql) => {
    const text = String(sql).replace(/\s+/g, ' ').toLowerCase();

    if (text.includes("'compliance'::text as source")) {
      return { rows: [], rowCount: 0 };
    }

    if (text.includes("concat('high-price-'") && text.includes('from prices pr')) {
      assert.equal(text.includes("im.movement_type = 'price_change'"), true);
      assert.equal(text.includes('from price_history ph'), true);
      return {
        rows: [
          {
            source: 'derived',
            source_id: 'high-price-1-6289201012345',
            pharmacy_id: 1,
            barcode: '6289201012345',
            alert_type: 'high_price',
            severity: 'high',
            title: 'Actual selling price exceeds regulated threshold',
            details: {
              avg_selling_price_minor: 4000,
              regulated_price_minor: 2000,
              markup_pct: 1,
            },
            status: 'open',
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          },
        ],
        rowCount: 1,
      };
    }

    if (text.includes("concat('hoarding-'") || text.includes("concat('price-jump-'")) {
      return { rows: [], rowCount: 0 };
    }

    throw new Error(`Unhandled SQL in alerts source test mock: ${text}`);
  };

  const server = app.listen(0);
  try {
    const b = base(server);
    const alerts = await fetch(`${b}/alerts`).then((r) => r.json());
    assert.equal(alerts.status, 'success');
    assert.equal(alerts.data.length, 1);
    assert.equal(alerts.data[0].alert_type, 'high_price');
    assert.equal(Number(alerts.data[0].details.avg_selling_price_minor), 4000);
    assert.equal(Number(alerts.data[0].details.regulated_price_minor), 2000);
    assert.equal(Number(alerts.data[0].details.markup_pct), 1);
  } finally {
    db.query = originalQuery;
    server.close();
  }
});

test('amoxil regression keeps medicine history timeline but pricing actual uses latest 40.00', async () => {
  const app = express();
  app.use('/api/web/monitoring', monitoringRoutes);

  const originalQuery = db.query;
  db.query = async (sql) => {
    const text = String(sql).replace(/\s+/g, ' ').toLowerCase();

    if (text.includes('from medicine_rows')) {
      return {
        rows: [
          {
            source: 'price_history',
            event_type: 'price_change',
            unit_price_minor: 5000,
            event_time: '2026-04-09T18:37:00.000Z',
            total_count: 2,
          },
          {
            source: 'price_history',
            event_type: 'price_change',
            unit_price_minor: 4000,
            event_time: '2026-04-09T18:23:00.000Z',
            total_count: 2,
          },
        ],
        rowCount: 2,
      };
    }

    if (text.includes('from with_rule')) {
      return {
        rows: [
          {
            pharmacy_name: 'Al-Amin Pharmacy',
            medicine_name: 'Amoxil',
            barcode: '6289201012345',
            regulated_price_minor: 2000,
            // stale historical aggregate could be 7250, but endpoint must use latest active 4000
            avg_selling_price_minor: 4000,
            markup_pct: 1,
            status: 'high_price',
            total_count: 1,
          },
        ],
        rowCount: 1,
      };
    }

    throw new Error(`Unhandled SQL in amoxil regression test mock: ${text}`);
  };

  const server = app.listen(0);
  try {
    const b = base(server);
    const history = await fetch(`${b}/medicine-history?medicine=amoxil`).then((r) => r.json());
    assert.equal(history.status, 'success');
    assert.equal(history.data.length, 2);
    assert.equal(Number(history.data[0].unit_price_minor), 5000);
    assert.equal(Number(history.data[1].unit_price_minor), 4000);

    const pricing = await fetch(`${b}/pricing?medicine=amoxil`).then((r) => r.json());
    assert.equal(pricing.status, 'success');
    assert.equal(pricing.data.length, 1);
    assert.equal(Number(pricing.data[0].regulated_price_minor), 2000);
    assert.equal(Number(pricing.data[0].avg_selling_price_minor), 4000);
    assert.equal(Number(pricing.data[0].markup_pct), 1);
    assert.equal(pricing.data[0].status, 'high_price');
  } finally {
    db.query = originalQuery;
    server.close();
  }
});

test('alert detail rejects invalid or empty alert ids with 400', async () => {
  const h = createAppWithMockDb();
  try {
    const b = base(h.server);

    const invalidLiteral = await fetch(`${b}/alerts/undefined`).then(async (r) => ({ status: r.status, body: await r.json() }));
    assert.equal(invalidLiteral.status, 400);
    assert.equal(invalidLiteral.body.error, 'invalid alert id');

    const malformedComplianceId = Buffer.from(
      JSON.stringify({ source: 'compliance' }),
      'utf8',
    ).toString('base64url');

    const malformedResp = await fetch(`${b}/alerts/${encodeURIComponent(malformedComplianceId)}`).then(async (r) => ({ status: r.status, body: await r.json() }));
    assert.equal(malformedResp.status, 400);
    assert.equal(malformedResp.body.error, 'invalid alert id');
  } finally {
    h.restore();
  }
});

test('alert detail hides raw SQL errors behind friendly backend message', async () => {
  const app = express();
  app.use('/api/web/monitoring', monitoringRoutes);

  const originalQuery = db.query;
  db.query = async (sql) => {
    const text = String(sql).replace(/\s+/g, ' ').toLowerCase();
    if (text.includes('from compliance_alerts')) {
      throw new Error('could not determine data type of parameter $1');
    }
    throw new Error(`Unhandled SQL in alert detail error test mock: ${text}`);
  };

  const server = app.listen(0);
  try {
    const b = base(server);
    const encoded = Buffer.from(
      JSON.stringify({ source: 'compliance', source_id: 'a1' }),
      'utf8',
    ).toString('base64url');

    const resp = await fetch(`${b}/alerts/${encodeURIComponent(encoded)}`);
    const body = await resp.json();

    assert.equal(resp.status, 500);
    assert.equal(body.error, 'failed to fetch alert details');
    assert.equal(String(body.error).toLowerCase().includes('parameter $1'), false);
  } finally {
    db.query = originalQuery;
    server.close();
  }
});

test('alert detail resolves legacy barcode/source-id selections without SQL type errors', async () => {
  const app = express();
  app.use('/api/web/monitoring', monitoringRoutes);

  const originalQuery = db.query;
  db.query = async (sql) => {
    const text = String(sql).replace(/\s+/g, ' ').toLowerCase();

    if (text.includes('from unioned') && text.includes('where source_id = $1::text or ($6::boolean and barcode = $1::text)')) {
      return {
        rows: [
          {
            source: 'derived',
            source_id: 'high-price-1-6289201012347',
            pharmacy_id: 1,
            barcode: '6289201012347',
            alert_type: 'high_price',
            severity: 'high',
            title: 'Actual selling price exceeds regulated threshold',
            details: {
              avg_selling_price_minor: 5000,
              regulated_price_minor: 2000,
            },
            status: 'open',
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          },
        ],
        rowCount: 1,
      };
    }

    throw new Error(`Unhandled SQL in legacy alert-id fallback test mock: ${text}`);
  };

  const server = app.listen(0);
  try {
    const b = base(server);
    const resp = await fetch(`${b}/alerts/6289201012347`);
    const body = await resp.json();

    assert.equal(resp.status, 200);
    assert.equal(body.status, 'success');
    assert.equal(body.data.barcode, '6289201012347');
    assert.equal(body.data.alert_type, 'high_price');
    assert.equal(typeof body.data.alert_id, 'string');
    assert.equal(body.data.alert_id.length > 8, true);
  } finally {
    db.query = originalQuery;
    server.close();
  }
});

test('alert detail accepts direct compliance uuid values from selector', async () => {
  const app = express();
  app.use('/api/web/monitoring', monitoringRoutes);

  const originalQuery = db.query;
  const complianceUuid = '3e3eeeaf-7165-86aa-1707-4a185e0c05d7';
  db.query = async (sql, params = []) => {
    const text = String(sql).replace(/\s+/g, ' ').toLowerCase();

    if (text.includes('from compliance_alerts') && text.includes('where alert_uuid::text = $1::text')) {
      assert.equal(params[0], complianceUuid);
      return {
        rows: [
          {
            alert_uuid: complianceUuid,
            pharmacy_id: 1,
            device_id: 'dev-1',
            barcode: '6289201012345',
            alert_type: 'price_violation',
            severity: 'high',
            title: 'Price violation for barcode 6289201012345',
            details: {},
            status: 'open',
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          },
        ],
        rowCount: 1,
      };
    }

    throw new Error(`Unhandled SQL in compliance uuid detail test mock: ${text} :: ${JSON.stringify(params)}`);
  };

  const server = app.listen(0);
  try {
    const b = base(server);
    const resp = await fetch(`${b}/alerts/${encodeURIComponent(complianceUuid)}`);
    const body = await resp.json();

    assert.equal(resp.status, 200);
    assert.equal(body.status, 'success');
    assert.equal(body.data.source, 'compliance');
    assert.equal(body.data.source_id, complianceUuid);
  } finally {
    db.query = originalQuery;
    server.close();
  }
});
