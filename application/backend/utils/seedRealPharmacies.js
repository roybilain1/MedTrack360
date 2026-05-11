// Replace the pharmacies table with 23 real Lebanese pharmacies and
// re-seed pharmacy_stock for every pharmacy×medication pair.
// Idempotent: re-running wipes the old rows (including stock + reviews,
// via ON DELETE CASCADE) and repopulates fresh.
import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const PHARMACIES = [
  // ─── Beirut ───────────────────────────────────────────────
  { name: 'Alam Pharmacy (Hamra branch)', location: 'Hamra',      region: 'Beirut',        phone: '+961 1 744 600', opening: '00:00', closing: '23:59', rating: 4.4, lat: 33.8942,    lng: 35.4823,    maps: 'https://maps.google.com/?q=Alam+Pharmacy+Hamra' },
  { name: 'Geahchan Pharmacy',             location: 'Verdun',     region: 'Beirut',        phone: '+961 1 801 188', opening: '08:00', closing: '22:00', rating: 4.5, lat: 33.8847,    lng: 35.4776,    maps: 'https://maps.google.com/?q=Geahchan+Pharmacy+Verdun' },
  { name: 'Pharmacy Achrafieh 24/7',       location: 'Achrafieh',  region: 'Beirut',        phone: '+961 1 200 848', opening: '00:00', closing: '23:59', rating: 4.3, lat: 33.8886,    lng: 35.5170,    maps: 'https://maps.google.com/?q=pharmacy+achrafieh+beirut' },
  { name: 'City Pharma',                   location: 'Ras Beirut', region: 'Beirut',        phone: '+961 1 365 650', opening: '08:00', closing: '22:00', rating: 4.2, lat: 33.9000,    lng: 35.4800,    maps: 'https://maps.google.com/?q=City+Pharma+Beirut' },

  // ─── Mount Lebanon ────────────────────────────────────────
  { name: 'Pharmacie du Keserwan',         location: 'Jounieh',    region: 'Mount Lebanon', phone: '+961 9 635 500', opening: '08:00', closing: '22:00', rating: 4.4, lat: 33.9811,    lng: 35.6178,    maps: 'https://maps.google.com/?q=Pharmacie+du+Keserwan' },
  { name: 'Ghadir Pharmacy',               location: 'Jounieh',    region: 'Mount Lebanon', phone: '+961 9 936 448', opening: '08:00', closing: '22:00', rating: 4.5, lat: 33.9785,    lng: 35.6197,    maps: 'https://maps.google.com/?q=Ghadir+Pharmacy+Jounieh' },
  { name: 'Pharmacie St. Therese',         location: 'Dekwaneh',   region: 'Mount Lebanon', phone: '+961 1 499 130', opening: '08:00', closing: '21:00', rating: 4.3, lat: 33.8935,    lng: 35.5445,    maps: 'https://maps.google.com/?q=Pharmacie+St+Therese+Dekwaneh' },
  { name: 'Pharmacie Baabda',              location: 'Baabda',     region: 'Mount Lebanon', phone: '+961 5 922 211', opening: '08:00', closing: '21:00', rating: 4.2, lat: 33.8453,    lng: 35.5440,    maps: 'https://maps.google.com/?q=pharmacy+baabda' },
  { name: 'Pharmacie Mazen',               location: 'Antelias',   region: 'Mount Lebanon', phone: '+961 4 414 004', opening: '08:00', closing: '22:00', rating: 4.4, lat: 33.9150,    lng: 35.5920,    maps: 'https://maps.google.com/?q=Pharmacie+Mazen+Antelias' },

  // ─── North (Tripoli) ──────────────────────────────────────
  { name: 'Alam Pharmacy (Tripoli main)',  location: 'Tripoli',    region: 'North',         phone: '+961 6 626 000', opening: '00:00', closing: '23:59', rating: 4.5, lat: 34.4384617, lng: 35.8377045, maps: 'https://maps.google.com/?q=Alam+Pharmacy+Tripoli' },
  { name: 'Fouad Pharmacy',                location: 'Tripoli',    region: 'North',         phone: '+961 6 433 364', opening: '08:00', closing: '22:00', rating: 4.3, lat: 34.4365,    lng: 35.8340,    maps: 'https://maps.google.com/?q=Fouad+Pharmacy+Tripoli' },
  { name: 'Pharmalife',                    location: 'Tripoli',    region: 'North',         phone: '+961 3 807 059', opening: '08:00', closing: '22:00', rating: 4.2, lat: 34.4348,    lng: 35.8325,    maps: 'https://maps.google.com/?q=Pharmalife+Tripoli' },

  // ─── Bekaa (Zahlé) ────────────────────────────────────────
  { name: 'Pharmaco Zahle',                location: 'Zahlé',      region: 'Bekaa',         phone: '+961 71 046 447', opening: '09:00', closing: '22:00', rating: 5.0, lat: 33.8257689, lng: 35.8986407, maps: 'https://maps.google.com/?q=Pharmaco+Zahle' },
  { name: 'Pharmacy A. Obeid',             location: 'Zahlé',      region: 'Bekaa',         phone: '+961 8 804 839',  opening: '08:30', closing: '20:00', rating: 4.8, lat: 33.8325512, lng: 35.9099248, maps: 'https://maps.google.com/?q=Pharmacy+A+Obeid+Zahle' },
  { name: 'Wissam Pharmacy',               location: 'Maalaqah',   region: 'Bekaa',         phone: '+961 8 930 926',  opening: '00:00', closing: '23:59', rating: 4.0, lat: 33.8450593, lng: 35.9209767, maps: 'https://maps.google.com/?q=Wissam+Pharmacy+Zahle' },

  // ─── South (Saida / Tyre) ─────────────────────────────────
  { name: 'Riham Pharmacy',                location: 'Saida',      region: 'South',         phone: '+961 7 752 200', opening: '08:00', closing: '22:00', rating: 4.4, lat: 33.5570,    lng: 35.3731,    maps: 'https://maps.google.com/?q=Riham+Pharmacy+Saida' },
  { name: 'Pharmacy Bachir',               location: 'Saida',      region: 'South',         phone: '+961 7 723 111', opening: '08:00', closing: '21:00', rating: 4.2, lat: 33.5600,    lng: 35.3715,    maps: 'https://maps.google.com/?q=Pharmacy+Bachir+Saida' },
  { name: 'Tyre Central Pharmacy',         location: 'Tyre',       region: 'South',         phone: '+961 7 343 210', opening: '08:00', closing: '22:00', rating: 4.3, lat: 33.2704,    lng: 35.2038,    maps: 'https://maps.google.com/?q=Pharmacy+Tyre+Lebanon' },

  // ─── Chouf / Aley ─────────────────────────────────────────
  { name: 'Pharma Rona',                   location: 'Aley',       region: 'Chouf/Aley',    phone: '+961 71 594 846', opening: '08:00', closing: '22:00', rating: 4.4, lat: 33.8058,    lng: 35.5973,    maps: 'https://maps.google.com/?q=Pharma+Rona+Aley' },
  { name: 'Barja Pharmacy',                location: 'Barja',      region: 'Chouf/Aley',    phone: '+961 7 602 211',  opening: '08:00', closing: '21:00', rating: 4.2, lat: 33.6550,    lng: 35.4270,    maps: 'https://maps.google.com/?q=Pharmacy+Barja' },

  // ─── Byblos / Batroun ─────────────────────────────────────
  { name: "Lea's Pharmacy",                location: 'Byblos',     region: 'North Coast',   phone: '+961 9 550 010', opening: '08:00', closing: '21:00', rating: 4.3, lat: 34.1211,    lng: 35.6483,    maps: 'https://maps.google.com/?q=Leas+Pharmacy+Byblos' },
  { name: 'St. Antoine Pharmacy',          location: 'Jbeil',      region: 'North Coast',   phone: '+961 9 943 773', opening: '08:00', closing: '20:00', rating: 4.2, lat: 34.1215,    lng: 35.6488,    maps: 'https://maps.google.com/?q=Pharmacy+St+Antoine+Jbeil' },
  { name: 'Batroun Pharmacy',              location: 'Batroun',    region: 'North Coast',   phone: '+961 6 741 200', opening: '08:00', closing: '22:00', rating: 4.3, lat: 34.2553,    lng: 35.6581,    maps: 'https://maps.google.com/?q=Pharmacy+Batroun' },
];

function jitter(base, pct = 0.08) {
  const factor = 1 + (Math.random() * 2 - 1) * pct;
  return Number((base * factor).toFixed(2));
}

async function main() {
  // 1. Make sure the richer columns exist.
  await pool.query(`
    ALTER TABLE pharmacies
      ADD COLUMN IF NOT EXISTS phone         VARCHAR(30),
      ADD COLUMN IF NOT EXISTS rating        NUMERIC(2,1),
      ADD COLUMN IF NOT EXISTS opening_hours VARCHAR(10),
      ADD COLUMN IF NOT EXISTS closing_hours VARCHAR(10),
      ADD COLUMN IF NOT EXISTS is_open       BOOLEAN DEFAULT TRUE,
      ADD COLUMN IF NOT EXISTS maps_url      TEXT
  `);

  // 2. Wipe pharmacies and anything pointing to them (stock + reviews).
  await pool.query(`TRUNCATE pharmacies RESTART IDENTITY CASCADE`);

  // 3. Insert the 23 real pharmacies. We synthesize legacy NOT-NULL fields
  //    (license_number, hwid) since these weren't part of the real-data list.
  const values = [];
  const params = [];
  let i = 1;
  PHARMACIES.forEach((p, idx) => {
    const seq = String(idx + 1).padStart(3, '0');
    const regionCode = (p.region.match(/[A-Z]/g) || [p.region[0]]).join('').slice(0, 3).toUpperCase();
    const license = `LIC-${regionCode}-${seq}`;
    const hwid    = `HW-R${seq}`;
    values.push(
      `($${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++}, $${i++})`
    );
    params.push(
      p.name, p.location, p.region, p.phone, p.rating,
      p.opening, p.closing, true, p.lat, p.lng, p.maps,
      'online', license, hwid,
    );
  });
  await pool.query(
    `INSERT INTO pharmacies
       (name, location, region, phone, rating,
        opening_hours, closing_hours, is_open,
        latitude, longitude, maps_url, status,
        license_number, hwid)
     VALUES ${values.join(',')}`,
    params,
  );
  console.log(`✅ Inserted ${PHARMACIES.length} pharmacies.`);

  // 4. Re-seed stock for every pharmacy × medication pair.
  const { rows: newPharmacies } = await pool.query('SELECT id FROM pharmacies');
  const { rows: meds } = await pool.query(
    'SELECT medication_id, ministry_locked_price FROM medications',
  );

  for (const ph of newPharmacies) {
    const sv = [];
    const sp = [];
    let j = 1;
    for (const m of meds) {
      const inStock = Math.random() < 0.7;
      const price = jitter(Number(m.ministry_locked_price) || 0);
      sv.push(`($${j++}, $${j++}, $${j++}, $${j++})`);
      sp.push(ph.id, m.medication_id, inStock, price);
    }
    await pool.query(
      `INSERT INTO pharmacy_stock (pharmacy_id, medication_id, in_stock, current_price)
       VALUES ${sv.join(',')}
       ON CONFLICT (pharmacy_id, medication_id)
       DO UPDATE SET in_stock = EXCLUDED.in_stock,
                     current_price = EXCLUDED.current_price,
                     last_updated  = CURRENT_TIMESTAMP`,
      sp,
    );
  }

  const { rows: counts } = await pool.query(
    `SELECT COUNT(*)::int AS total,
            COUNT(*) FILTER (WHERE in_stock)::int AS in_stock
     FROM pharmacy_stock`,
  );
  console.log(
    `✅ Re-seeded ${counts[0].total} stock rows ` +
      `(${counts[0].in_stock} in-stock) across ${newPharmacies.length} pharmacies × ${meds.length} medications.`,
  );

  await pool.end();
}

main().catch((e) => {
  console.error('❌ Seed failed:', e);
  process.exit(1);
});
