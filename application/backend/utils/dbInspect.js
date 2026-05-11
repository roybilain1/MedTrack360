import { Pool } from 'pg';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, '..', '.env') });

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

async function main() {
  try {
    const users = await pool.query(`
      SELECT user_id, full_name, email, phone, is_active, created_at
      FROM users
      ORDER BY created_at DESC
    `);

    console.log(`\n📋 users (${users.rowCount} row${users.rowCount === 1 ? '' : 's'}):`);
    console.table(
      users.rows.map((u) => ({
        user_id: u.user_id,
        full_name: u.full_name,
        email: u.email,
        phone: u.phone || '—',
        active: u.is_active,
        created_at: u.created_at.toISOString(),
      }))
    );

    const counts = await pool.query(`
      SELECT
        (SELECT COUNT(*) FROM watchlist)       AS watchlist,
        (SELECT COUNT(*) FROM reviews)         AS reviews,
        (SELECT COUNT(*) FROM search_history)  AS search_history
    `);
    console.log('\n📊 per-user row totals:');
    console.table(counts.rows[0]);

    if (users.rowCount > 0) {
      const breakdown = await pool.query(`
        SELECT u.email,
               COALESCE(w.n, 0) AS watchlist,
               COALESCE(r.n, 0) AS reviews,
               COALESCE(h.n, 0) AS search_history
        FROM users u
        LEFT JOIN (SELECT user_id, COUNT(*) n FROM watchlist      GROUP BY user_id) w ON w.user_id = u.user_id
        LEFT JOIN (SELECT user_id, COUNT(*) n FROM reviews        GROUP BY user_id) r ON r.user_id = u.user_id
        LEFT JOIN (SELECT user_id, COUNT(*) n FROM search_history GROUP BY user_id) h ON h.user_id = u.user_id
        ORDER BY u.created_at DESC
      `);
      console.log('\n📦 per-user data:');
      console.table(breakdown.rows);
    }
  } catch (err) {
    console.error('❌ Inspect failed:', err.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
}

main();
