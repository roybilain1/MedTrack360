// Seeds the pharmacy_stock table: every pharmacy × every medication.
// ~70% of pairs are in-stock; prices jitter ±8% around the ministry price.
// Idempotent: uses ON CONFLICT DO UPDATE, so re-running refreshes stock.
import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

function jitter(base, pct = 0.08) {
  const factor = 1 + (Math.random() * 2 - 1) * pct;
  return Number((base * factor).toFixed(2));
}

async function main() {
  const { rows: pharmacies } = await pool.query('SELECT id FROM pharmacies');
  const { rows: meds } = await pool.query(
    'SELECT medication_id, ministry_locked_price FROM medications',
  );

  if (pharmacies.length === 0 || meds.length === 0) {
    console.log('⚠️  Need pharmacies and medications to seed stock.');
    await pool.end();
    return;
  }

  let inserted = 0;
  for (const ph of pharmacies) {
    const values = [];
    const params = [];
    let idx = 1;
    for (const m of meds) {
      const inStock = Math.random() < 0.7;
      const basePrice = Number(m.ministry_locked_price) || 0;
      const price = jitter(basePrice);
      values.push(`($${idx++}, $${idx++}, $${idx++}, $${idx++})`);
      params.push(ph.id, m.medication_id, inStock, price);
    }

    await pool.query(
      `INSERT INTO pharmacy_stock (pharmacy_id, medication_id, in_stock, current_price)
       VALUES ${values.join(',')}
       ON CONFLICT (pharmacy_id, medication_id)
       DO UPDATE SET in_stock = EXCLUDED.in_stock,
                     current_price = EXCLUDED.current_price,
                     last_updated  = CURRENT_TIMESTAMP`,
      params,
    );
    inserted += meds.length;
  }

  const { rows: counts } = await pool.query(
    `SELECT COUNT(*)::int AS total,
            COUNT(*) FILTER (WHERE in_stock)::int AS in_stock
     FROM pharmacy_stock`,
  );
  console.log(
    `✅ Seeded ${inserted} pharmacy×medication pairs across ` +
      `${pharmacies.length} pharmacies and ${meds.length} medications.`,
  );
  console.log(`   Total rows: ${counts[0].total} | in-stock: ${counts[0].in_stock}`);
  await pool.end();
}

main().catch((e) => {
  console.error('❌ Seed failed:', e);
  process.exit(1);
});
