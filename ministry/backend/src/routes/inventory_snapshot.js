/**
 * Backend route for inventory snapshot sync
 * Allows POS or admin to backfill opening inventory
 * 
 * This solves the issue where POS local inventory was never synced to central DB
 * causing web to show 0 units when POS shows real stock
 */

const express = require('express');
const db = require('../db');

const router = express.Router();

function normalized(v) {
  return String(v || '').trim();
}

function toIntOrNull(value) {
  if (value == null || value === '') return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.trunc(n);
}

function stableUuid(seed) {
  const crypto = require('crypto');
  const hash = crypto.createHash('sha1').update(String(seed)).digest('hex').slice(0, 32);
  return `${hash.slice(0, 8)}-${hash.slice(8, 12)}-${hash.slice(12, 16)}-${hash.slice(16, 20)}-${hash.slice(20, 32)}`;
}

/**
 * POST /sync/inventory-snapshot
 * 
 * Accepts inventory snapshot from POS to backfill opening inventory
 * 
 * Request body:
 * {
 *   "request_id": "REQ-SNAPSHOT-2026-04-30",
 *   "pharmacy_id": 25,
 *   "license_number": "LIC-BEY-0041",
 *   "device_id": "HW-00423",
 *   "timestamp": "2026-04-30T12:00:00Z",
 *   "inventory": [
 *     {
 *       "barcode": "6289201012345",
 *       "quantity": 132,
 *       "trade_name": "Amoxil"
 *     },
 *     {
 *       "barcode": "6009705182174",
 *       "quantity": 12,
 *       "trade_name": "Augmentin"
 *     }
 *   ]
 * }
 */
router.post('/inventory-snapshot', async (req, res) => {
  const client = await db.pool.connect();
  
  try {
    await client.query('BEGIN');
    
    const requestId = normalized(req.body.request_id);
    const pharmacyId = toIntOrNull(req.body.pharmacy_id);
    const licenseNumber = normalized(req.body.license_number);
    const deviceId = normalized(req.body.device_id);
    const timestamp = new Date(req.body.timestamp || Date.now());
    const inventory = Array.isArray(req.body.inventory) ? req.body.inventory : [];
    
    if (!requestId) {
      return res.status(400).json({ error: 'request_id is required' });
    }
    
    if (!pharmacyId && !licenseNumber) {
      return res.status(400).json({ error: 'pharmacy_id or license_number is required' });
    }
    
    if (inventory.length === 0) {
      return res.status(400).json({ error: 'inventory array is required and must be non-empty' });
    }
    
    // Resolve pharmacy
    let pharmacyResult;
    if (pharmacyId) {
      pharmacyResult = await client.query(
        `SELECT id, name, license_number FROM pharmacies WHERE id = $1 LIMIT 1`,
        [pharmacyId]
      );
    } else {
      pharmacyResult = await client.query(
        `SELECT id, name, license_number FROM pharmacies WHERE license_number = $1 LIMIT 1`,
        [licenseNumber]
      );
    }
    
    if (pharmacyResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'pharmacy not found' });
    }
    
    const pharmacy = pharmacyResult.rows[0];
    const resultPharmacyId = pharmacy.id;
    
    let processedCount = 0;
    const processedItems = [];
    const skippedItems = [];
    const errors = [];
    
    for (const item of inventory) {
      const barcode = normalized(item.barcode);
      const quantity = toIntOrNull(item.quantity);
      const tradeName = normalized(item.trade_name);
      
      if (!barcode || quantity === null) {
        errors.push({
          barcode,
          error: 'barcode and quantity are required'
        });
        continue;
      }
      
      if (quantity <= 0) {
        // Skip zero or negative quantities
        skippedItems.push({
          barcode,
          quantity,
          reason: 'quantity must be positive'
        });
        continue;
      }
      
      // Generate idempotent UUID
      const eventUuid = stableUuid(`inventory-snapshot:${resultPharmacyId}:${barcode}:${timestamp.toISOString()}`);
      
      // Check if this opening inventory movement already exists
      const existingMovement = await client.query(
        `SELECT id FROM inventory_movements WHERE event_uuid = $1 LIMIT 1`,
        [eventUuid]
      );
      
      if (existingMovement.rows.length > 0) {
        skippedItems.push({
          barcode,
          quantity,
          reason: 'already backfilled'
        });
        continue;
      }
      
      // Insert opening inventory movement
      await client.query(`
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
      `, [
        eventUuid,
        resultPharmacyId,
        deviceId || 'inventory-snapshot-api',
        'inventory-snapshot',
        barcode,
        'opening_inventory',
        quantity,
        null,
        'USD',
        'snapshot-sync',
        requestId,
        JSON.stringify({
          snapshot: true,
          trade_name: tradeName,
          snapshot_timestamp: timestamp.toISOString()
        }),
        timestamp,
        1,
        'synced'
      ]);
      
      processedCount++;
      processedItems.push({
        barcode,
        quantity,
        trade_name: tradeName
      });
    }
    
    // Record the request
    await client.query(`
      INSERT INTO sync_requests (
        request_id,
        pharmacy_id,
        device_id,
        endpoint,
        payload,
        request_status,
        response_payload,
        created_at,
        updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, NOW(), NOW())
      ON CONFLICT (request_id) DO NOTHING
    `, [
      requestId,
      resultPharmacyId,
      deviceId || 'inventory-snapshot-api',
      '/api/sync/inventory-snapshot',
      JSON.stringify(req.body),
      'completed',
      JSON.stringify({
        processed: processedCount,
        skipped: skippedItems.length,
        errors: errors.length,
        items: processedItems
      })
    ]);
    
    await client.query('COMMIT');
    
    res.json({
      status: 'success',
      message: `Inventory snapshot processed for pharmacy: ${pharmacy.name}`,
      pharmacy: {
        id: resultPharmacyId,
        name: pharmacy.name,
        license_number: pharmacy.license_number
      },
      summary: {
        processed: processedCount,
        skipped: skippedItems.length,
        errors: errors.length
      },
      processed_items: processedItems,
      skipped_items: skippedItems,
      errors: errors
    });
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error processing inventory snapshot:', error);
    res.status(500).json({
      error: error.message || 'Internal server error',
      request_id: req.body.request_id
    });
  } finally {
    client.release();
  }
});

module.exports = router;
