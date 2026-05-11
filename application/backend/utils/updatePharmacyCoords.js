// Updates lat/lng for the 23 real pharmacies with refined coordinates.
// Matches by exact pharmacy name (as inserted by seedRealPharmacies.js).
import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const COORDS = [
  { name: 'Alam Pharmacy (Hamra branch)',   lat: 33.8942,    lng: 35.4823 },
  { name: 'Geahchan Pharmacy',              lat: 33.8847,    lng: 35.4776 },
  // Pharmacy Achrafieh 24/7: N/A — keep existing value
  { name: 'City Pharma',                    lat: 33.9000,    lng: 35.4800 },
  { name: 'Pharmacie du Keserwan',          lat: 33.9811,    lng: 35.6178 },
  { name: 'Ghadir Pharmacy',                lat: 33.9785,    lng: 35.6197 },
  { name: 'Pharmacie St. Therese',          lat: 33.8935,    lng: 35.5445 },
  { name: 'Pharmacie Baabda',               lat: 33.8453,    lng: 35.5440 },
  { name: 'Pharmacie Mazen',                lat: 33.9150,    lng: 35.5920 },
  { name: 'Alam Pharmacy (Tripoli main)',   lat: 34.4384617, lng: 35.8377045 },
  { name: 'Fouad Pharmacy',                 lat: 34.4365,    lng: 35.8340 },
  { name: 'Pharmalife',                     lat: 34.4348,    lng: 35.8325 },
  { name: 'Pharmaco Zahle',                 lat: 33.8257689, lng: 35.8986407 },
  { name: 'Pharmacy A. Obeid',              lat: 33.8325512, lng: 35.9099248 },
  { name: 'Wissam Pharmacy',                lat: 33.8450593, lng: 35.9209767 },
  { name: 'Riham Pharmacy',                 lat: 33.5570,    lng: 35.3731 },
  { name: 'Pharmacy Bachir',                lat: 33.5600,    lng: 35.3715 },
  { name: 'Tyre Central Pharmacy',          lat: 33.2704,    lng: 35.2038 },
  { name: 'Pharma Rona',                    lat: 33.8058,    lng: 35.5973 },
  { name: 'Barja Pharmacy',                 lat: 33.6550,    lng: 35.4270 },
  { name: "Lea's Pharmacy",                 lat: 34.1211,    lng: 35.6483 },
  { name: 'St. Antoine Pharmacy',           lat: 34.1215,    lng: 35.6488 },
  { name: 'Batroun Pharmacy',               lat: 34.2553,    lng: 35.6581 },
];

async function main() {
  let updated = 0;
  let missing = [];
  for (const c of COORDS) {
    const result = await pool.query(
      `UPDATE pharmacies SET latitude = $1, longitude = $2 WHERE name = $3`,
      [c.lat, c.lng, c.name],
    );
    if (result.rowCount > 0) {
      updated += result.rowCount;
      console.log(`  ✓ ${c.name} → ${c.lat}, ${c.lng}`);
    } else {
      missing.push(c.name);
    }
  }
  console.log(`\n✅ Updated ${updated} pharmacies.`);
  if (missing.length) {
    console.log(`⚠️  Not found (name mismatch): ${missing.join(', ')}`);
  }
  await pool.end();
}

main().catch((e) => {
  console.error('❌ Update failed:', e);
  process.exit(1);
});
