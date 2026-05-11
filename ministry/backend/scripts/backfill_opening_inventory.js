/**
 * Backfill: Correct Negative Stock from Initial Inventory
 *
 * Problem: POS local inventory was never synced as opening balance
 * When POS sells inventory, central DB shows negative stock
 * 
 * Solution: Create retroactive "opening_inventory" movements
 * This establishes the correct starting inventory state
 *
 * Usage: node backend/scripts/backfill_opening_inventory.js
 */

require('dotenv').config();
const { Pool } = require('pg');
const crypto = require('crypto');

const connectionString =
  process.env.DATABASE_URL ||
  process.env.POSTGRES_URL ||
  process.env.POSTGRES_URI ||
  'postgresql://postgres:postgres@localhost:5432/medtrack';

const pool = new Pool({ connectionString });

function stableUuid(seed) {
  const hash = crypto.createHash('sha1').update(String(seed)).digest('hex').slice(0, 32);
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-${hash.slice(12, 16)}-${hash.slice(16, 20)}-${hash.slice(20, 32)}`;
}

async function backfillOpeningInventory() {
  const client = await pool.connect();
  
  try {
    console.log('Starting backfill of opening inventory...\n');
    
    // Find pharmacies with negative or zero stock but with existing movements
    const negativeStockResult = await client.query(`
      WITH pharmacy_stock AS (
        SELECT
          p.id as pharmacy_id,
          p.name,
          p.license_number,
          im.barcode,
          mr.trade_name,
          GREATEST(0, SUM(im.quantity_delta))::int as current_stock,
          COALESCE(SUM(im.quantity_delta), 0)::int as net_movements,
          COUNT(*) as movement_count,
          MIN(im.happened_at) as first_movement_at
        FROM pharmacies p
        LEFT JOIN inventory_movements im ON im.pharmacy_id = p.id AND im.deleted_at IS NULL
        LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
        WHERE im.barcode IS NOT NULL
        GROUP BY p.id, p.name, p.license_number, im.barcode, mr.trade_name
        HAVING COALESCE(SUM(im.quantity_delta), 0)::int < 0
      )
      SELECT * FROM pharmacy_stock ORDER BY pharmacy_id, barcode
    `);
    
    console.log(`Found ${negativeStockResult.rows.length} medicines with negative stock\n`);
    
    if (negativeStockResult.rows.length === 0) {
      console.log('No negative stock items found. Backfill not needed.');
      client.release();
      return;
    }
    
    let fixedCount = 0;
    
    for (const row of negativeStockResult.rows) {
      // Calculate required opening balance
      // If net movements are -1, we need opening balance of at least 1
      const requiredOpening = Math.abs(row.net_movements);
      const openingBalanceQuantity = requiredOpening;
      
      // Generate stable UUID for idempotency
      const eventUuid = stableUuid(`opening-inventory:${row.pharmacy_id}:${row.barcode}:backfill-2026-04-30`);
      
      console.log(`\nPharmacy: ${row.name} (${row.license_number})`);
      console.log(`Medicine: ${row.trade_name} (${row.barcode})`);
      console.log(`Current net movements: ${row.net_movements} units`);
      console.log(`Adding opening balance: ${openingBalanceQuantity} units`);
      console.log(`Event UUID: ${eventUuid}`);
      
      // Insert opening inventory movement
      const insertResult = await client.query(`
        INSERT INTO inventory_movements (
          event_uuid,
          pharmacy_id,
          device_id,
          source,
          barcode,
          movement_type,
          quantity_delta,
          unit_price_minor,
          currency_code,
          reference_type,
          reference_id,
          metadata,
          happened_at,
          version,
          sync_status,
          updated_at,
          deleted_at
        )
        VALUES (
          $1::uuid,
          $2,
          $3,
          $4,
          $5,
          $6,
          $7,
          $8,
          $9,
          $10,
          $11,
          $12::jsonb,
          $13::timestamptz,
          $14,
          $15,
          NOW(),
          NULL
        )
        ON CONFLICT (event_uuid) DO NOTHING
        RETURNING id
      `, [
        eventUuid,                          // event_uuid
        row.pharmacy_id,                    // pharmacy_id
        'backfill-system',                  // device_id
        'opening-inventory-backfill',       // source
        row.barcode,                        // barcode
        'opening_inventory',                // movement_type
        openingBalanceQuantity,             // quantity_delta (positive)
        null,                               // unit_price_minor
        'USD',                              // currency_code
        'initial-inventory',                // reference_type
        'BACKFILL-20260430',                // reference_id
        JSON.stringify({
          backfill: true,
          reason: 'Correcting opening inventory from local POS snapshot',
          correcting_negative_stock: true,
          previous_net: row.net_movements
        }),                                 // metadata
        row.first_movement_at,              // happened_at (before first actual movement)
        1,                                  // version
        'synced'                            // sync_status
      ]);
      
      if (insertResult.rowCount > 0) {
        fixedCount++;
        console.log(`✓ Opening inventory recorded`);
      } else {
        console.log(`ℹ Event already exists (idempotent)`);
      }
    }
    
    console.log(`\n=== Backfill Complete ===`);
    console.log(`✓ Fixed ${fixedCount} medicines`);
    console.log(`\nVerifying corrections...`);
    
    // Verify the fix
    const verifyResult = await client.query(`
      WITH pharmacy_stock AS (
        SELECT
          p.id,
          p.name,
          p.license_number,
          im.barcode,
          mr.trade_name,
          GREATEST(0, SUM(im.quantity_delta))::int as corrected_stock,
          COUNT(*) as movement_count
        FROM pharmacies p
        LEFT JOIN inventory_movements im ON im.pharmacy_id = p.id AND im.deleted_at IS NULL
        LEFT JOIN moph_registry mr ON mr.barcode = im.barcode
        WHERE p.license_number IN (
          SELECT DISTINCT license_number FROM pharmacies WHERE id IN (
            SELECT DISTINCT pharmacy_id FROM inventory_movements WHERE movement_type = 'opening_inventory'
          )
        )
        GROUP BY p.id, p.name, p.license_number, im.barcode, mr.trade_name
      )
      SELECT * FROM pharmacy_stock WHERE corrected_stock > 0 ORDER BY id, barcode LIMIT 20
    `);
    
    console.log(`\nCorrected inventory (sample):`);
    verifyResult.rows.forEach(row => {
      console.log(`[${row.id}] ${row.name}: ${row.trade_name} = ${row.corrected_stock} units`);
    });
    
  } catch (error) {
    console.error('Error during backfill:', error.message);
    console.error(error);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

backfillOpeningInventory().then(() => {
  console.log('\nBackfill process completed successfully');
  process.exit(0);
});
