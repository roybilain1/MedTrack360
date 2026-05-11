const test = require('node:test');
const db = require('../db');

/**
 * DIAGNOSTIC TEST: Why does /monitoring/stock show 0 units for Amoxil/Augmentin?
 * This test traces the exact data path from pharmacy setup to monitoring query.
 */

test('DIAGNOSTIC: Trace zero stock issue for Amoxil', async () => {
  const client = await db.pool.connect();
  
  try {
    await client.query('BEGIN');
    
    // Step 1: Check if pharmacy exists
    console.log('\n=== STEP 1: Check pharmacy setup ===');
    const pharmacyResult = await client.query(
      `SELECT id, name, license_number, hwid FROM pharmacies 
       WHERE license_number = 'LIC-BEY-0041' LIMIT 1`
    );
    
    if (pharmacyResult.rows.length === 0) {
      console.log('❌ PHARMACY NOT FOUND: LIC-BEY-0041 does not exist in database');
      console.log('   This means Al-Amin Pharmacy has never been registered!');
      return;
    }
    
    const pharmacy = pharmacyResult.rows[0];
    console.log(`✓ Found pharmacy: ${pharmacy.name} (ID: ${pharmacy.id})`);
    console.log(`  License: ${pharmacy.license_number}, HWID: ${pharmacy.hwid}`);
    
    // Step 2: Check if Amoxil/Augmentin exist in registry
    console.log('\n=== STEP 2: Check medicine registry ===');
    const medsResult = await client.query(
      `SELECT barcode, trade_name, dosage, category FROM moph_registry 
       WHERE trade_name ILIKE '%Amoxil%' OR trade_name ILIKE '%Augmentin%'`
    );
    
    if (medsResult.rows.length === 0) {
      console.log('❌ MEDICINES NOT IN REGISTRY');
      console.log('   Amoxil/Augmentin not found in moph_registry');
      return;
    }
    
    console.log(`✓ Found ${medsResult.rows.length} medicines:`);
    medsResult.rows.forEach(med => {
      console.log(`  - ${med.trade_name} (${med.dosage}) [${med.barcode}]`);
    });
    
    const amoxilBarcode = medsResult.rows.find(m => m.trade_name.includes('Amoxil'))?.barcode;
    
    // Step 3: Check inventory movements for this pharmacy/barcode
    console.log('\n=== STEP 3: Check inventory movements ===');
    const movementsResult = await client.query(
      `SELECT event_uuid, quantity_delta, movement_type, happened_at, deleted_at
       FROM inventory_movements
       WHERE pharmacy_id = $1 AND barcode = $2
       ORDER BY happened_at DESC
       LIMIT 10`,
      [pharmacy.id, amoxilBarcode]
    );
    
    if (movementsResult.rows.length === 0) {
      console.log(`❌ NO MOVEMENTS FOUND for ${amoxilBarcode} at pharmacy ${pharmacy.id}`);
      console.log('   → POS has NOT synced any movements for this medicine');
      console.log('   → Stock = 0 because no purchase/sale events recorded');
      return;
    }
    
    console.log(`✓ Found ${movementsResult.rows.length} movements:`);
    let totalStock = 0;
    movementsResult.rows.forEach(m => {
      totalStock += m.quantity_delta;
      console.log(`  ${m.movement_type}: ${m.quantity_delta > 0 ? '+' : ''}${m.quantity_delta} ` +
                  `(${m.happened_at}) ${m.deleted_at ? '❌ DELETED' : ''}`);
    });
    console.log(`  → Net stock: ${totalStock} units`);
    
    // Step 4: Run actual monitoring query
    console.log('\n=== STEP 4: Run monitoring stock query ===');
    const monitoringResult = await client.query(
      `WITH latest_price_events AS (
        SELECT pharmacy_id, barcode, new_price_minor::numeric AS local_price_minor, changed_at AS event_time
        FROM price_history WHERE new_price_minor IS NOT NULL
        UNION ALL
        SELECT pharmacy_id, barcode, unit_price_minor::numeric AS local_price_minor, happened_at AS event_time
        FROM inventory_movements WHERE deleted_at IS NULL AND movement_type = 'price_change'
      ), latest_local_price AS (
        SELECT DISTINCT ON (pharmacy_id, barcode) pharmacy_id, barcode, local_price_minor
        FROM latest_price_events ORDER BY pharmacy_id, barcode, event_time DESC
      ), grouped AS (
        SELECT
          p.id AS pharmacy_id,
          p.name AS pharmacy_name,
          im.barcode,
          mr.trade_name AS medicine_name,
          mr.dosage,
          GREATEST(0, SUM(im.quantity_delta))::int AS stock_units
        FROM inventory_movements im
        JOIN pharmacies p ON p.id = im.pharmacy_id
        LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
        WHERE im.deleted_at IS NULL
          AND p.id = $1 AND im.barcode = $2
        GROUP BY p.id, p.name, im.barcode, mr.trade_name, mr.dosage
      )
      SELECT * FROM grouped`,
      [pharmacy.id, amoxilBarcode]
    );
    
    if (monitoringResult.rows.length === 0) {
      console.log('❌ QUERY RETURNED NO ROWS');
      return;
    }
    
    const row = monitoringResult.rows[0];
    console.log(`✓ Query result:`);
    console.log(`  Pharmacy: ${row.pharmacy_name}`);
    console.log(`  Medicine: ${row.medicine_name} (${row.dosage})`);
    console.log(`  Stock units: ${row.stock_units}`);
    
    if (row.stock_units === 0) {
      console.log('\n❌ PROBLEM CONFIRMED: Stock = 0 even though movements should exist');
      console.log('   Possible causes:');
      console.log('   1. Movements don\'t exist → POS hasn\'t synced');
      console.log('   2. Movements marked as deleted');
      console.log('   3. Pharmacy ID mismatch in sync');
    }
    
    // Step 5: Check ALL pharmacies to see which ones have movements
    console.log('\n=== STEP 5: Summary of all pharmacies ===');
    const summaryResult = await client.query(
      `SELECT 
        p.id,
        p.name,
        p.license_number,
        COUNT(DISTINCT im.barcode) as medicine_count,
        COUNT(*) as total_movements,
        COALESCE(SUM(im.quantity_delta), 0)::int as total_stock
      FROM pharmacies p
      LEFT JOIN inventory_movements im ON im.pharmacy_id = p.id AND im.deleted_at IS NULL
      GROUP BY p.id, p.name, p.license_number
      ORDER BY p.id`
    );
    
    console.log(`Found ${summaryResult.rows.length} pharmacies in database:`);
    summaryResult.rows.forEach(row => {
      console.log(`  [${row.id}] ${row.name} (${row.license_number}): ` +
                  `${row.medicine_count} medicines, ${row.total_movements} movements, ${row.total_stock} units`);
    });
    
  } finally {
    await client.query('ROLLBACK');
    client.release();
  }
});
