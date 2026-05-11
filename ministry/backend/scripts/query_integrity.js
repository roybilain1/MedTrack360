const { Pool } = require('pg');
require('dotenv').config();

async function query() {
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });
  
  try {
    const pharmacies = await pool.query("SELECT id, name, license_number, hwid FROM pharmacies WHERE license_number = 'LIC-BEY-0041' OR hwid = 'HW-00423'");
    const syncState = await pool.query("SELECT * FROM pos_sync_state WHERE hwid = 'HW-00423'");
    
    console.log(JSON.stringify({
      pharmacies: pharmacies.rows,
      pos_sync_state: syncState.rows
    }, null, 2));
  } catch (err) {
    console.error(err);
  } finally {
    await pool.end();
  }
}

query();
