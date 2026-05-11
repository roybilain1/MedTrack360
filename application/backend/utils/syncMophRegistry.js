// Two-way sync between `medications` (the FK-bearing core) and
// `moph_registry` (the Ministry of Public Health authoritative list).
//
// After this runs:
//   • Every row in either table has a counterpart in the other.
//   • Both rows share the same `medication_id` UUID, so the existing
//     foreign keys in pharmacy_stock / watchlist / notifications keep
//     working when we serve listings from `moph_registry`.
//   • pharmacy_stock has rows for every (pharmacy × medication) pair so
//     newly-introduced branded items aren't orphaned in the UI.
//
// Idempotent: re-running adds only what's missing.
import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

async function ensureSchema() {
  await pool.query(`
    ALTER TABLE moph_registry
      ADD COLUMN IF NOT EXISTS medication_id              UUID,
      ADD COLUMN IF NOT EXISTS category_id                INT REFERENCES medication_categories(category_id),
      ADD COLUMN IF NOT EXISTS national_availability_score NUMERIC,
      ADD COLUMN IF NOT EXISTS description                TEXT;
  `);
  // medication_id should be unique once populated, but allow nulls during the
  // intermediate state.
  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS uniq_moph_registry_medication_id
      ON moph_registry (medication_id) WHERE medication_id IS NOT NULL;
  `);
  await pool.query(`
    CREATE INDEX IF NOT EXISTS idx_moph_registry_trade_name
      ON moph_registry (LOWER(trade_name));
  `);
  console.log('✅ moph_registry schema extended');
}

// Pick a sensible category_id for a free-text MoPH category. Falls back to
// the first available category if no match.
async function defaultCategoryId() {
  const r = await pool.query(
    `SELECT category_id FROM medication_categories ORDER BY display_order ASC LIMIT 1`,
  );
  return r.rows[0]?.category_id ?? null;
}

async function categoryIdForText(text) {
  if (!text) return null;
  const r = await pool.query(
    `SELECT category_id FROM medication_categories
      WHERE LOWER(category_name) = LOWER($1) LIMIT 1`,
    [text],
  );
  return r.rows[0]?.category_id ?? null;
}

// 1. For each row in medications, ensure a moph_registry row exists with the
//    same medication_id UUID.
async function syncMedicationsToRegistry() {
  const meds = await pool.query(`
    SELECT m.*, c.category_name
      FROM medications m
      LEFT JOIN medication_categories c ON c.category_id = m.category_id
  `);

  let inserted = 0;
  let linked = 0;

  for (const m of meds.rows) {
    // Try to find a registry row with the same UUID.
    const existing = await pool.query(
      `SELECT id FROM moph_registry WHERE medication_id = $1`,
      [m.medication_id],
    );
    if (existing.rowCount > 0) continue;

    // Or by name match (case-insensitive trade_name / generic_name).
    const byName = await pool.query(
      `SELECT id, medication_id FROM moph_registry
        WHERE LOWER(trade_name)   = LOWER($1)
          AND LOWER(generic_name) = LOWER($2)
        LIMIT 1`,
      [m.brand_name, m.generic_name],
    );

    if (byName.rowCount > 0) {
      // Already in registry but unlinked — copy the UUID over.
      if (byName.rows[0].medication_id == null) {
        await pool.query(
          `UPDATE moph_registry
              SET medication_id              = $1,
                  category_id                = COALESCE(category_id, $2),
                  national_availability_score = COALESCE(national_availability_score, $3),
                  description                = COALESCE(description, $4)
            WHERE id = $5`,
          [
            m.medication_id,
            m.category_id,
            m.national_availability_score,
            m.description,
            byName.rows[0].id,
          ],
        );
        linked++;
      }
      continue;
    }

    // Not in registry at all — insert with synthesized barcode.
    const synthBarcode = 'APP-' + String(m.medication_id).replace(/-/g, '').slice(0, 12);
    await pool.query(
      `INSERT INTO moph_registry
         (barcode, trade_name, generic_name, dosage, form, manufacturer,
          category, moph_ceiling, medication_id, category_id,
          national_availability_score, description, is_blocked)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,false)`,
      [
        synthBarcode,
        m.brand_name,
        m.generic_name,
        m.strength,
        m.dosage_form,
        m.manufacturer,
        m.category_name,
        m.ministry_locked_price,
        m.medication_id,
        m.category_id,
        m.national_availability_score,
        m.description,
      ],
    );
    inserted++;
  }
  console.log(`✅ medications → moph_registry: linked ${linked}, inserted ${inserted}`);
}

// 2. For each row in moph_registry without a medication_id, create a matching
//    medications row so pharmacy_stock / watchlist FKs can hold for it.
async function syncRegistryToMedications() {
  const fallbackCategory = await defaultCategoryId();
  const orphans = await pool.query(
    `SELECT * FROM moph_registry WHERE medication_id IS NULL`,
  );

  let createdMedRows = 0;
  for (const r of orphans.rows) {
    // Try to match an existing medications row by name first.
    const byName = await pool.query(
      `SELECT medication_id FROM medications
        WHERE LOWER(brand_name)   = LOWER($1)
          AND LOWER(generic_name) = LOWER($2)
        LIMIT 1`,
      [r.trade_name, r.generic_name],
    );

    let medicationId;
    if (byName.rowCount > 0) {
      medicationId = byName.rows[0].medication_id;
    } else {
      // Insert a new medications row using moph_registry data.
      const categoryId = r.category_id
        ?? (await categoryIdForText(r.category))
        ?? fallbackCategory;
      const insert = await pool.query(
        `INSERT INTO medications
           (brand_name, generic_name, category_id, description,
            ministry_locked_price, national_availability_score,
            dosage_form, strength, manufacturer)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         RETURNING medication_id`,
        [
          r.trade_name,
          r.generic_name,
          categoryId,
          r.description ?? null,
          r.moph_ceiling ?? 0,
          r.national_availability_score ?? 0,
          r.form ?? 'tablet',
          r.dosage ?? '—',
          r.manufacturer ?? '—',
        ],
      );
      medicationId = insert.rows[0].medication_id;
      createdMedRows++;
    }

    await pool.query(
      `UPDATE moph_registry
          SET medication_id = $1,
              category_id   = COALESCE(category_id, (SELECT category_id FROM medications WHERE medication_id = $1))
        WHERE id = $2`,
      [medicationId, r.id],
    );
  }
  console.log(`✅ moph_registry → medications: linked ${orphans.rowCount} rows (${createdMedRows} new medications created)`);
}

// 3. Make sure every (pharmacy × medication) pair has a stock row so the
//    branded medicines that just landed in `medications` aren't orphaned.
async function fillStockGaps() {
  const result = await pool.query(`
    INSERT INTO pharmacy_stock (pharmacy_id, medication_id, in_stock, current_price)
    SELECT p.id,
           m.medication_id,
           random() < 0.6                                                       AS in_stock,
           ROUND((COALESCE(m.ministry_locked_price, 0) * (0.92 + random()*0.16))::numeric, 2) AS current_price
      FROM pharmacies p
      CROSS JOIN medications m
     WHERE NOT EXISTS (
       SELECT 1 FROM pharmacy_stock s
        WHERE s.pharmacy_id = p.id AND s.medication_id = m.medication_id
     )
    RETURNING stock_id
  `);
  console.log(`✅ pharmacy_stock filled: ${result.rowCount} new rows`);
}

async function summary() {
  const m = await pool.query(`SELECT COUNT(*)::int AS n FROM medications`);
  const r = await pool.query(`SELECT COUNT(*)::int AS n FROM moph_registry`);
  const linked = await pool.query(
    `SELECT COUNT(*)::int AS n FROM moph_registry WHERE medication_id IS NOT NULL`,
  );
  const stock = await pool.query(`SELECT COUNT(*)::int AS n FROM pharmacy_stock`);
  console.log('\nFinal state:');
  console.log(`  medications:            ${m.rows[0].n}`);
  console.log(`  moph_registry:          ${r.rows[0].n}`);
  console.log(`  moph_registry linked:   ${linked.rows[0].n}`);
  console.log(`  pharmacy_stock rows:    ${stock.rows[0].n}`);
}

async function main() {
  await ensureSchema();
  await syncMedicationsToRegistry();
  await syncRegistryToMedications();
  await fillStockGaps();
  await summary();
  await pool.end();
}

main().catch((e) => {
  console.error('❌ Sync failed:', e);
  process.exit(1);
});
