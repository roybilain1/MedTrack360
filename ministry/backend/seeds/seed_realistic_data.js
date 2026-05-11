// Idempotent realistic-data seed for the MedTrack dashboard.
//
// Goal: populate pos_sync_state, inventory_movements, price_history,
// product_batches, and a few compliance_alerts so every monitoring tab
// shows non-empty, internally-consistent data.
//
// Run with:
//   cd backend
//   DATABASE_URL='...' node seeds/seed_realistic_data.js
//
// Re-running is safe: it only inserts when the corresponding rows are
// missing for a (pharmacy, medicine) pair.

require('dotenv').config();
const { randomUUID } = require('crypto');
const db = require('../src/db');

// Deterministic pseudo-random in [0,1) so the seed is repeatable.
function rng(seedStr) {
  let h = 2166136261;
  for (let i = 0; i < seedStr.length; i++) {
    h ^= seedStr.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return ((h >>> 0) % 100000) / 100000;
}

function pickInt(seed, min, max) {
  return min + Math.floor(rng(seed) * (max - min + 1));
}

function chance(seed, pct) {
  return rng(seed) < pct / 100;
}

async function main() {
  console.log('[seed] Loading pharmacies and medicines...');
  const pharmacies = (
    await db.query(
      `SELECT id, name, hwid, region FROM pharmacies WHERE hwid IS NOT NULL AND hwid <> '' ORDER BY id`
    )
  ).rows;
  const medicines = (
    await db.query(
      `SELECT barcode, trade_name, dosage, category, moph_ceiling FROM moph_registry ORDER BY barcode`
    )
  ).rows;

  if (!pharmacies.length || !medicines.length) {
    console.error('[seed] No pharmacies or medicines found. Aborting.');
    process.exit(1);
  }
  console.log(`[seed] ${pharmacies.length} pharmacies, ${medicines.length} medicines.`);

  // ────────────────────────────────────────────────────────────────────────
  // 1. pos_sync_state: every pharmacy gets a sync record, varied health.
  // ────────────────────────────────────────────────────────────────────────
  console.log('[seed] Updating pos_sync_state...');
  for (const p of pharmacies) {
    // 70% healthy, 20% overdue (12-48h), 10% stale (5+ days)
    const bucket = (p.id + 3) % 10;
    let hoursAgo;
    if (bucket < 7) hoursAgo = pickInt(`sync-${p.id}-h`, 0, 6); // healthy
    else if (bucket < 9) hoursAgo = pickInt(`sync-${p.id}-o`, 13, 48); // overdue
    else hoursAgo = pickInt(`sync-${p.id}-s`, 120, 240); // stale

    await db.query(
      `INSERT INTO pos_sync_state (hwid, pharmacy_id, last_sync_up, last_sync_down, app_version, pending_updates, updated_at)
       VALUES ($1, $2, NOW() - make_interval(hours => $3), NOW() - make_interval(hours => $3), '2.6.1', false, NOW())
       ON CONFLICT (hwid) DO UPDATE SET
         pharmacy_id = EXCLUDED.pharmacy_id,
         last_sync_up = EXCLUDED.last_sync_up,
         last_sync_down = EXCLUDED.last_sync_down,
         app_version = EXCLUDED.app_version,
         updated_at = NOW()`,
      [p.hwid, p.id, hoursAgo]
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // 2. Each pharmacy stocks ~7 medicines: one purchase event 60–90 days ago.
  // 3. Sales: 6-15 sale events spread across last 30 days for each pair.
  // ────────────────────────────────────────────────────────────────────────
  console.log('[seed] Generating purchases + sales...');
  let movementsInserted = 0;
  let priceHistoryInserted = 0;
  let batchesInserted = 0;

  for (const p of pharmacies) {
    // Pick ~7 medicines deterministically
    const stocked = medicines.filter((m) => chance(`stock-${p.id}-${m.barcode}`, 28));

    for (const m of stocked) {
      // Skip if this pair already has a purchase row
      const existing = await db.query(
        `SELECT 1 FROM inventory_movements WHERE pharmacy_id = $1 AND barcode = $2 AND movement_type = 'purchase' LIMIT 1`,
        [p.id, m.barcode]
      );
      if (existing.rows.length) continue;

      const ceilingMinor = Math.round(Number(m.moph_ceiling) * 100);
      // Most pharmacies price at 80–105% of moph_ceiling.
      // 1 in 8 prices above the ceiling -> price-compliance violation.
      const priceFactor = chance(`overprice-${p.id}-${m.barcode}`, 12)
        ? 1.05 + rng(`op-${p.id}-${m.barcode}`) * 0.25 // 105–130% (violation)
        : 0.8 + rng(`up-${p.id}-${m.barcode}`) * 0.25; // 80–105%
      const unitPriceMinor = Math.max(50, Math.round(ceilingMinor * priceFactor));

      // Initial purchase: 60–90 days ago, 80–250 units
      const purchaseDaysAgo = pickInt(`pdays-${p.id}-${m.barcode}`, 60, 90);
      const purchaseQty = pickInt(`pqty-${p.id}-${m.barcode}`, 80, 250);
      const purchaseUuid = randomUUID();
      await db.query(
        `INSERT INTO inventory_movements
         (event_uuid, pharmacy_id, device_id, barcode, movement_type, quantity_delta, unit_price_minor, currency_code, happened_at, source)
         VALUES ($1, $2, $3, $4, 'purchase', $5, $6, 'USD', NOW() - make_interval(days => $7), 'pos')`,
        [purchaseUuid, p.id, p.hwid, m.barcode, purchaseQty, unitPriceMinor, purchaseDaysAgo]
      );
      movementsInserted++;

      // Initial price-history row (matches the purchase price)
      await db.query(
        `INSERT INTO price_history
         (history_uuid, barcode, pharmacy_id, previous_price_minor, new_price_minor, currency_code, source, changed_by, changed_at)
         VALUES ($1, $2, $3, NULL, $4, 'USD', 'pos', 'pos:initial', NOW() - make_interval(days => $5))`,
        [randomUUID(), m.barcode, p.id, unitPriceMinor, purchaseDaysAgo]
      );
      priceHistoryInserted++;

      // 30% chance of a price change ~20 days ago
      if (chance(`pricechange-${p.id}-${m.barcode}`, 30)) {
        const drift = pickInt(`drift-${p.id}-${m.barcode}`, -150, 250);
        const newPrice = Math.max(50, unitPriceMinor + drift);
        await db.query(
          `INSERT INTO price_history
           (history_uuid, barcode, pharmacy_id, previous_price_minor, new_price_minor, currency_code, source, changed_by, changed_at)
           VALUES ($1, $2, $3, $4, $5, 'USD', 'pos', 'pos:adjustment', NOW() - INTERVAL '20 days')`,
          [randomUUID(), m.barcode, p.id, unitPriceMinor, newPrice]
        );
        priceHistoryInserted++;
      }

      // Sales over last 30 days: 6–15 events, 1–4 units each
      const numSales = pickInt(`nsales-${p.id}-${m.barcode}`, 6, 15);
      // 1 in 10 pairs = "hoarding" pattern: very few sales (1-2 only)
      const isHoarding = chance(`hoard-${p.id}-${m.barcode}`, 10);
      const effectiveSales = isHoarding ? pickInt(`hns-${p.id}-${m.barcode}`, 1, 2) : numSales;

      for (let i = 0; i < effectiveSales; i++) {
        const dayAgo = pickInt(`saleday-${p.id}-${m.barcode}-${i}`, 0, 29);
        const qty = pickInt(`saleqty-${p.id}-${m.barcode}-${i}`, 1, 4);
        const salePriceJitter = pickInt(`salejit-${p.id}-${m.barcode}-${i}`, -50, 100);
        await db.query(
          `INSERT INTO inventory_movements
           (event_uuid, pharmacy_id, device_id, barcode, movement_type, quantity_delta, unit_price_minor, currency_code, happened_at, source)
           VALUES ($1, $2, $3, $4, 'sale', $5, $6, 'USD', NOW() - make_interval(days => $7) - make_interval(mins => $8), 'pos')`,
          [
            randomUUID(),
            p.id,
            p.hwid,
            m.barcode,
            -qty,
            Math.max(50, unitPriceMinor + salePriceJitter),
            dayAgo,
            (i * 47) % 1440,
          ]
        );
        movementsInserted++;
      }

      // product_batches: 1 batch matching the purchase
      // Mix of expiry dates: most healthy, ~10% near-expiry, ~3% expired
      const expirySeed = `exp-${p.id}-${m.barcode}`;
      let expiryClause;
      if (chance(expirySeed, 3)) expiryClause = `NOW() - INTERVAL '15 days'`; // expired
      else if (chance(`${expirySeed}-near`, 12)) expiryClause = `NOW() + INTERVAL '45 days'`; // near
      else
        expiryClause = `NOW() + INTERVAL '${pickInt(`${expirySeed}-far`, 6, 24)} months'`; // healthy

      const supplier =
        ['Mediphar SAL', 'Beirut Pharma Distribution', 'Levant Medical Supply'][p.id % 3];
      await db.query(
        `INSERT INTO product_batches
         (batch_uuid, pharmacy_id, barcode, batch_number, expiry_at, quantity_on_hand, unit_cost_minor, unit_price_minor, currency_code, supplier_name)
         VALUES ($1, $2, $3, $4, ${expiryClause}, $5, $6, $7, 'USD', $8)`,
        [
          randomUUID(),
          p.id,
          m.barcode,
          `BATCH-${p.id}-${m.barcode.slice(-6)}`,
          purchaseQty,
          Math.round(unitPriceMinor * 0.7),
          unitPriceMinor,
          supplier,
        ]
      );
      batchesInserted++;
    }
  }

  console.log(`[seed] Inserted ${movementsInserted} movements, ${priceHistoryInserted} price events, ${batchesInserted} batches.`);

  // ────────────────────────────────────────────────────────────────────────
  // 4. national_stock thresholds: ensure every stocked medicine has a
  //    threshold so the Stock tab can compare against it.
  // ────────────────────────────────────────────────────────────────────────
  console.log('[seed] Ensuring national_stock thresholds...');
  for (const m of medicines) {
    const ceilingMinor = Math.round(Number(m.moph_ceiling) * 100);
    await db.query(
      `INSERT INTO national_stock (barcode, medication_name, category, stock_units, threshold, status, region, last_sync, updated_at)
       VALUES ($1, $2, $3, 0, 200, 'safe', 'National', 'just now', NOW())
       ON CONFLICT DO NOTHING`,
      [m.barcode, `${m.trade_name} ${m.dosage || ''}`.trim(), m.category || 'Other']
    );
    // Also write canonical price into prices table (used as fallback)
    await db.query(
      `INSERT INTO prices (barcode, local_price_minor, currency_code, deleted_at)
       VALUES ($1, $2, 'USD', NULL)
       ON CONFLICT DO NOTHING`,
      [m.barcode, ceilingMinor]
    );
  }

  console.log('[seed] Done.');
  await db.pool.end();
}

main().catch((err) => {
  console.error('[seed] Failed:', err);
  process.exit(1);
});
