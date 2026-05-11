#!/usr/bin/env node

require('dotenv').config();

const db = require('../src/db');

function envOrDefault(name, fallback) {
  const value = String(process.env[name] || '').trim();
  return value || fallback;
}

function parseArgs() {
  const args = new Set(process.argv.slice(2));
  return {
    apply: args.has('--apply'),
  };
}

async function run() {
  const { apply } = parseArgs();

  const target = {
    name: envOrDefault('MEDTRACK_POS_BRANCH_NAME', 'Al-Amin Pharmacy'),
    license: envOrDefault('MEDTRACK_POS_LICENSE_NUMBER', 'LIC-BEY-0041'),
    hwid: envOrDefault('MEDTRACK_POS_HWID', 'HW-00423'),
    region: envOrDefault('MEDTRACK_POS_REGION', 'Beirut'),
  };

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');

    const byLicense = await client.query(
      `SELECT id, name, license_number, hwid, region
       FROM pharmacies
       WHERE license_number = $1
       LIMIT 1`,
      [target.license]
    );

    const byHwid = await client.query(
      `SELECT id, name, license_number, hwid, region
       FROM pharmacies
       WHERE hwid = $1
       LIMIT 1`,
      [target.hwid]
    );

    let pharmacy = byLicense.rows[0] || byHwid.rows[0] || null;
    const licenseExists = Boolean(byLicense.rows[0]);
    const hwidExists = Boolean(byHwid.rows[0]);

    const diagnostics = {
      target,
      found_by_license: byLicense.rows,
      found_by_hwid: byHwid.rows,
      action: 'none',
    };

    if (!pharmacy) {
      diagnostics.action = apply ? 'insert_pharmacy' : 'would_insert_pharmacy';
      if (apply) {
        const inserted = await client.query(
          `INSERT INTO pharmacies (name, license_number, hwid, region, status, last_seen)
           VALUES ($1, $2, $3, $4, 'online', 'just now')
           RETURNING id, name, license_number, hwid, region`,
          [target.name, target.license, target.hwid, target.region]
        );
        pharmacy = inserted.rows[0] || null;
      }
    } else if (licenseExists && !hwidExists && byLicense.rows[0].hwid !== target.hwid) {
      diagnostics.action = apply ? 'update_hwid_for_license' : 'would_update_hwid_for_license';
      if (apply) {
        const updated = await client.query(
          `UPDATE pharmacies
           SET hwid = $1,
               name = COALESCE(NULLIF($2, ''), name),
               region = COALESCE(NULLIF($3, ''), region),
               status = 'online',
               last_seen = 'just now'
           WHERE id = $4
           RETURNING id, name, license_number, hwid, region`,
          [target.hwid, target.name, target.region, byLicense.rows[0].id]
        );
        pharmacy = updated.rows[0] || pharmacy;
      }
    }

    let syncStateBefore = [];
    let syncStateAfter = [];

    if (pharmacy) {
      syncStateBefore = (
        await client.query(
          `SELECT hwid, pharmacy_id, last_sync_up, last_sync_down
           FROM pos_sync_state
           WHERE hwid = $1
           ORDER BY updated_at DESC`,
          [target.hwid]
        )
      ).rows;

      if (apply) {
        await client.query(
          `INSERT INTO pos_sync_state (hwid, pharmacy_id, last_sync_up, last_sync_down, pending_updates, app_version)
           VALUES ($1, $2, NOW(), NOW(), false, '')
           ON CONFLICT (hwid) DO UPDATE SET
             pharmacy_id = EXCLUDED.pharmacy_id,
             updated_at = NOW()`,
          [target.hwid, pharmacy.id]
        );
      }

      syncStateAfter = (
        await client.query(
          `SELECT hwid, pharmacy_id, last_sync_up, last_sync_down
           FROM pos_sync_state
           WHERE hwid = $1
           ORDER BY updated_at DESC`,
          [target.hwid]
        )
      ).rows;
    }

    diagnostics.pharmacy_after = pharmacy;
    diagnostics.sync_state_before = syncStateBefore;
    diagnostics.sync_state_after = syncStateAfter;

    if (!apply) {
      await client.query('ROLLBACK');
      console.log(JSON.stringify({ dry_run: true, diagnostics }, null, 2));
      return;
    }

    await client.query('COMMIT');
    console.log(JSON.stringify({ applied: true, diagnostics }, null, 2));
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('repair failed:', error.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await db.pool.end();
  }
}

run();
