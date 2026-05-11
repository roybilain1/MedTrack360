// Layer realistic problem scenarios on top of seed_realistic_data.js so every
// monitoring tab has a non-trivial mix of statuses.
//
// Scenarios injected (deterministic, repeatable):
//   - Out-of-stock + low-stock + critical  : drains existing stock to ~0..15
//   - Recent purchase spike (watch)        : fresh purchase > sales*3
//   - Hoarding                              : extra purchase, almost no sales
//   - Price violation                       : current price > moph_ceiling
//   - Open compliance alerts                : a couple of high-price/hoarding alerts
//
// Run: cd backend && node seeds/seed_anomalies.js

require('dotenv').config();
const { randomUUID } = require('crypto');
const db = require('../src/db');

async function ensureMedicine(barcode) {
  const r = await db.query(
    'SELECT barcode, trade_name, dosage, category, moph_ceiling FROM moph_registry WHERE barcode = $1',
    [barcode]
  );
  return r.rows[0];
}

async function getCurrentStock(pharmacyId, barcode) {
  const r = await db.query(
    `SELECT GREATEST(0, COALESCE(SUM(quantity_delta), 0))::int AS stock
     FROM inventory_movements
     WHERE pharmacy_id = $1 AND barcode = $2 AND deleted_at IS NULL`,
    [pharmacyId, barcode]
  );
  return r.rows[0]?.stock ?? 0;
}

async function getPharmacy(id) {
  const r = await db.query('SELECT id, name, hwid FROM pharmacies WHERE id = $1', [id]);
  return r.rows[0];
}

async function insertMovement({ pharmacyId, hwid, barcode, type, qty, priceMinor, hoursAgo }) {
  await db.query(
    `INSERT INTO inventory_movements
     (event_uuid, pharmacy_id, device_id, barcode, movement_type, quantity_delta, unit_price_minor, currency_code, happened_at, source)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'USD', NOW() - make_interval(hours => $8), 'pos')`,
    [randomUUID(), pharmacyId, hwid, barcode, type, qty, priceMinor, hoursAgo]
  );
}

async function insertAlert({ pharmacyId, barcode, alertType, severity, title, details }) {
  await db.query(
    `INSERT INTO compliance_alerts
     (alert_uuid, pharmacy_id, barcode, alert_type, severity, title, details, status, source, version, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, 'open', 'server', 1, NOW(), NOW())`,
    [randomUUID(), pharmacyId, barcode, alertType, severity, title, JSON.stringify(details || {})]
  );
}

async function main() {
  // Pre-existing pharmacies and a few well-known barcodes from the registry
  const PANADOL = '6289201012357';
  const ZITHRO = '6289201012353';
  const VENTOLIN = '6289201012361';
  const COZAAR = '6289201012359';
  const AUGMENTIN = '6009705182174';
  const CRESTOR = '6009705182204';
  const XARELTO = '6009705182228';
  const ZYRTEC = '6289201012351';
  const BRUFEN = '6289201012350';

  // Pick a handful of pharmacies for each scenario
  const SCENARIOS = [
    // === Critical / Out-of-stock ===
    // Drain Panadol at Geahchan to 5 units
    { kind: 'drain_to', pharmacyId: 2, barcode: PANADOL, target: 5 },
    // Out-of-stock Augmentin at Pharmacie Baabda
    { kind: 'drain_to', pharmacyId: 8, barcode: AUGMENTIN, target: 0 },
    // Critical Ventolin at Tyre Central
    { kind: 'drain_to', pharmacyId: 18, barcode: VENTOLIN, target: 3 },

    // === Low (between threshold*0.25 and threshold) ===
    // Zithromax at Alam Hamra: 18 units (threshold 30, so low)
    { kind: 'drain_to', pharmacyId: 1, barcode: ZITHRO, target: 18 },
    // Crestor at Wissam: 22 units
    { kind: 'drain_to', pharmacyId: 15, barcode: CRESTOR, target: 22 },

    // === Watch: recent purchase > sales*3 ===
    // Ghadir Pharmacy bought 200 Brufen 2 days ago, but sales are minimal
    { kind: 'recent_purchase', pharmacyId: 6, barcode: BRUFEN, qty: 200, hoursAgo: 48 },
    // Pharma Rona bought 150 Cozaar 3 days ago
    { kind: 'recent_purchase', pharmacyId: 19, barcode: COZAAR, qty: 150, hoursAgo: 72 },

    // === Hoarding ===
    // City Pharma sits on 250 Xarelto with almost no sales
    { kind: 'hoard', pharmacyId: 4, barcode: XARELTO, qty: 250 },
    // Riham Pharmacy: hoards Zyrtec
    { kind: 'hoard', pharmacyId: 16, barcode: ZYRTEC, qty: 180 },

    // === Price violation: current price way above moph_ceiling ===
    // Barja Pharmacy charges 150% of ceiling for Crestor
    { kind: 'overprice', pharmacyId: 20, barcode: CRESTOR, factor: 1.5 },
    // Pharmacy A. Obeid charges 130% for Augmentin
    { kind: 'overprice', pharmacyId: 14, barcode: AUGMENTIN, factor: 1.3 },
  ];

  console.log('[anomalies] applying scenarios...');
  for (const s of SCENARIOS) {
    const med = await ensureMedicine(s.barcode);
    const pharm = await getPharmacy(s.pharmacyId);
    if (!med || !pharm) {
      console.log(`  skipped: missing pharmacy=${s.pharmacyId} or barcode=${s.barcode}`);
      continue;
    }
    const ceilingMinor = Math.round(Number(med.moph_ceiling) * 100);

    if (s.kind === 'drain_to') {
      const current = await getCurrentStock(s.pharmacyId, s.barcode);
      // If no stock at all yet for this pair, give it some first.
      if (current === 0) {
        await insertMovement({
          pharmacyId: s.pharmacyId,
          hwid: pharm.hwid,
          barcode: s.barcode,
          type: 'purchase',
          qty: 100,
          priceMinor: Math.round(ceilingMinor * 0.9),
          hoursAgo: 24 * 60,
        });
      }
      const newCurrent = await getCurrentStock(s.pharmacyId, s.barcode);
      const drainBy = Math.max(0, newCurrent - s.target);
      if (drainBy > 0) {
        await insertMovement({
          pharmacyId: s.pharmacyId,
          hwid: pharm.hwid,
          barcode: s.barcode,
          type: 'sale',
          qty: -drainBy,
          priceMinor: Math.round(ceilingMinor * 0.95),
          hoursAgo: 6,
        });
      }
      console.log(`  ${pharm.name} / ${med.trade_name}: stock -> ${s.target}`);
    } else if (s.kind === 'recent_purchase') {
      await insertMovement({
        pharmacyId: s.pharmacyId,
        hwid: pharm.hwid,
        barcode: s.barcode,
        type: 'purchase',
        qty: s.qty,
        priceMinor: Math.round(ceilingMinor * 0.85),
        hoursAgo: s.hoursAgo,
      });
      console.log(`  ${pharm.name} / ${med.trade_name}: +${s.qty} purchase ${s.hoursAgo}h ago (watch)`);
    } else if (s.kind === 'hoard') {
      // Big purchase ~30 days ago + only 1-2 sales since
      await insertMovement({
        pharmacyId: s.pharmacyId,
        hwid: pharm.hwid,
        barcode: s.barcode,
        type: 'purchase',
        qty: s.qty,
        priceMinor: Math.round(ceilingMinor * 0.85),
        hoursAgo: 24 * 35,
      });
      // 2 small sales
      await insertMovement({
        pharmacyId: s.pharmacyId,
        hwid: pharm.hwid,
        barcode: s.barcode,
        type: 'sale',
        qty: -1,
        priceMinor: Math.round(ceilingMinor * 0.9),
        hoursAgo: 24 * 14,
      });
      await insertMovement({
        pharmacyId: s.pharmacyId,
        hwid: pharm.hwid,
        barcode: s.barcode,
        type: 'sale',
        qty: -1,
        priceMinor: Math.round(ceilingMinor * 0.9),
        hoursAgo: 24 * 5,
      });
      console.log(`  ${pharm.name} / ${med.trade_name}: hoarding pattern (+${s.qty}, only 2 sales)`);
      await insertAlert({
        pharmacyId: s.pharmacyId,
        barcode: s.barcode,
        alertType: 'hoarding_risk',
        severity: 'high',
        title: `Stock accumulation pattern on ${med.trade_name}`,
        details: { stock_units: s.qty, sales_30d: 2, days_of_stock: 'very high' },
      });
    } else if (s.kind === 'overprice') {
      const newPriceMinor = Math.round(ceilingMinor * s.factor);
      // Insert a price-change event so price_history reflects it
      const last = await db.query(
        `SELECT new_price_minor FROM price_history
         WHERE pharmacy_id = $1 AND barcode = $2
         ORDER BY changed_at DESC LIMIT 1`,
        [s.pharmacyId, s.barcode]
      );
      const previous = last.rows[0]?.new_price_minor || ceilingMinor;
      await db.query(
        `INSERT INTO price_history (history_uuid, barcode, pharmacy_id, previous_price_minor, new_price_minor, currency_code, source, changed_by, changed_at)
         VALUES ($1, $2, $3, $4, $5, 'USD', 'pos', 'pos:overprice', NOW() - INTERVAL '2 days')`,
        [randomUUID(), s.barcode, s.pharmacyId, previous, newPriceMinor]
      );
      // Reflect the new price on the latest sale too (so /pricing avg picks it up)
      await insertMovement({
        pharmacyId: s.pharmacyId,
        hwid: pharm.hwid,
        barcode: s.barcode,
        type: 'sale',
        qty: -1,
        priceMinor: newPriceMinor,
        hoursAgo: 12,
      });
      await insertAlert({
        pharmacyId: s.pharmacyId,
        barcode: s.barcode,
        alertType: 'high_price',
        severity: 'high',
        title: `${med.trade_name} priced above MoPH ceiling at ${pharm.name}`,
        details: {
          regulated_price_minor: ceilingMinor,
          observed_price_minor: newPriceMinor,
          markup_pct: Math.round((s.factor - 1) * 100),
        },
      });
      console.log(`  ${pharm.name} / ${med.trade_name}: priced at ${s.factor}x ceiling (violation)`);
    }
  }

  console.log('[anomalies] done.');
  await db.pool.end();
}

main().catch((e) => {
  console.error('[anomalies] failed:', e);
  process.exit(1);
});
