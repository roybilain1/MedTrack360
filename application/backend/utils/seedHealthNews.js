// Seeds the health_news table with a few starter Ministry of Public Health
// items. The trigger in schema.sql fans each insert out to every active user.
// Idempotent: TRUNCATEs notifications of type 'news' first so we don't create
// duplicates on re-runs.
import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const NEWS = [
  {
    title: 'New ministry-locked prices effective this week',
    body:
      'The Ministry of Public Health has issued an updated price list for ' +
      'subsidised medications. Pharmacies must apply the new ceilings ' +
      'immediately. Patients can verify pricing inside the app under each ' +
      'medication.',
  },
  {
    title: 'Free flu vaccination campaign starts Monday',
    body:
      'Public hospitals and accredited primary-care centres begin offering ' +
      'free seasonal influenza vaccines to residents over 65 and to all ' +
      'children under 5 starting next Monday.',
  },
  {
    title: 'Reminder: report counterfeit medications via hotline 1214',
    body:
      'If you suspect a medication is counterfeit, contact the MoPH hotline ' +
      'on 1214. Keep packaging and the receipt for inspection.',
  },
  {
    title: 'Cardiology drug shortage update',
    body:
      'The ministry confirms restocking of several cardiology medications ' +
      'is underway. Expected normal availability across all Lebanese ' +
      'pharmacies within two weeks.',
  },
];

async function main() {
  // Wipe prior news + the notifications spawned by them so re-runs stay clean.
  await pool.query(`DELETE FROM notifications WHERE type = 'news'`);
  await pool.query(`DELETE FROM health_news`);

  for (const n of NEWS) {
    await pool.query(
      `INSERT INTO health_news (title, body) VALUES ($1, $2)`,
      [n.title, n.body],
    );
  }

  const { rows: nc } = await pool.query(
    `SELECT COUNT(*)::int AS n FROM notifications WHERE type = 'news'`,
  );
  console.log(`✅ Inserted ${NEWS.length} news items.`);
  console.log(`✅ Trigger fanned out ${nc[0].n} news notifications to users.`);
  await pool.end();
}

main().catch((e) => {
  console.error('❌ Seed failed:', e);
  process.exit(1);
});
