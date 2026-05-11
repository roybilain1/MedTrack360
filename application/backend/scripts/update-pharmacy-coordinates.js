import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    rejectUnauthorized: false,
  },
});

// Updated pharmacy coordinates with each pharmacy at its specific city location
const pharmacyCoordinates = [
  { id: 1, name: 'Al-Amin Pharmacy', latitude: 33.3157, longitude: 35.5264 },
  { id: 2, name: 'Pharma Plus — Hamra', latitude: 33.3141, longitude: 35.5042 },
  { id: 3, name: 'Zahrawi Medical', latitude: 34.4386, longitude: 35.8428 },
  { id: 4, name: 'Bekaa Central Pharmacy', latitude: 33.8421, longitude: 35.8934 },
  { id: 5, name: 'Nour Al-Hayat Pharmacy', latitude: 33.3847, longitude: 35.3728 },
  { id: 6, name: 'Akkar Health Supplies', latitude: 34.5478, longitude: 35.9078 },
  { id: 7, name: 'South Gate Pharmacy', latitude: 33.5611, longitude: 35.3691 },
  { id: 8, name: 'Al-Nour Pharmacy', latitude: 34.4325, longitude: 35.8350 },
  { id: 9, name: 'Mansour Medical', latitude: 33.3256, longitude: 35.5450 },
  { id: 10, name: 'Baalbek Plus', latitude: 33.8612, longitude: 35.9108 },
  { id: 11, name: 'Jdeideh Care', latitude: 33.6372, longitude: 35.5854 },
  { id: 12, name: 'Hamra Health Center', latitude: 33.3341, longitude: 35.5501 },
  { id: 13, name: 'Raouche HealthMart', latitude: 33.3410, longitude: 35.5098 },
  { id: 14, name: 'Choueifat Medical', latitude: 33.6145, longitude: 35.5623 },
  { id: 15, name: 'Sidon Central Pharmacy', latitude: 33.5611, longitude: 35.3691 },
  { id: 16, name: 'Hermel Medical Supply', latitude: 33.8547, longitude: 35.9047 },
  { id: 17, name: 'Baalbek Dispensary', latitude: 33.8547, longitude: 35.9047 },
  { id: 18, name: 'Batroun Pharmacy', latitude: 34.2615, longitude: 35.6627 },
  { id: 19, name: 'Byblos Pharma Hub', latitude: 34.1240, longitude: 35.6428 },
  { id: 20, name: 'Jounieh Health Center', latitude: 33.9717, longitude: 35.5987 },
  { id: 21, name: 'Ashrafieh MedPlus', latitude: 33.3293, longitude: 35.5412 },
  { id: 22, name: 'Cola Pharmacy', latitude: 33.3410, longitude: 35.5098 },
  { id: 23, name: 'Nabatieh City Pharmacy', latitude: 33.3847, longitude: 35.3728 },
  { id: 24, name: 'Tyre Medical Depot', latitude: 33.2711, longitude: 35.2042 },
  { id: 25, name: 'Halba Health Supplies', latitude: 34.5620, longitude: 35.9234 },
  { id: 26, name: 'Bikfaya Pharmacy', latitude: 33.6892, longitude: 35.6142 },
  { id: 27, name: 'Zghorta Medical', latitude: 33.9425, longitude: 35.6428 },
  { id: 28, name: 'Deir el Ahmar Pharmacy', latitude: 33.8600, longitude: 35.9100 },
  { id: 29, name: 'Marjayoun Dispensary', latitude: 33.3900, longitude: 35.3800 },
  { id: 30, name: 'Jbeil Community Pharmacy', latitude: 34.1350, longitude: 35.6500 },
];

async function updatePharmacyCoordinates() {
  try {
    console.log('🔄 Setting up pharmacy coordinates in Neon database...\n');

    // Step 1: Check if latitude and longitude columns exist
    console.log('📋 Checking database schema...');
    const columnsResult = await pool.query(`
      SELECT column_name 
      FROM information_schema.columns 
      WHERE table_name = 'pharmacies' 
      AND column_name IN ('latitude', 'longitude')
    `);

    const hasLatLng = columnsResult.rows.length === 2;

    if (!hasLatLng) {
      console.log('➕ Adding latitude and longitude columns...');
      
      // Add latitude column
      try {
        await pool.query(`ALTER TABLE pharmacies ADD COLUMN latitude DECIMAL(10, 6)`);
        console.log('✅ Added latitude column');
      } catch (e) {
        if (!e.message.includes('already exists')) throw e;
        console.log('⚠️  latitude column already exists');
      }

      // Add longitude column
      try {
        await pool.query(`ALTER TABLE pharmacies ADD COLUMN longitude DECIMAL(10, 6)`);
        console.log('✅ Added longitude column');
      } catch (e) {
        if (!e.message.includes('already exists')) throw e;
        console.log('⚠️  longitude column already exists');
      }
    }

    console.log('\n🔄 Updating pharmacy coordinates...\n');

    for (const pharmacy of pharmacyCoordinates) {
      await pool.query(
        `UPDATE pharmacies 
         SET latitude = $1, longitude = $2 
         WHERE id = $3 OR name = $4`,
        [pharmacy.latitude, pharmacy.longitude, pharmacy.id, pharmacy.name]
      );
      console.log(`✅ Updated: ${pharmacy.name} (${pharmacy.latitude}, ${pharmacy.longitude})`);
    }

    console.log('\n✅ All pharmacy coordinates updated successfully!');
    
    // Verify the updates
    console.log('\n📋 Verifying updated pharmacies...\n');
    const result = await pool.query('SELECT id, name, latitude, longitude FROM pharmacies ORDER BY id ASC');
    
    result.rows.forEach(row => {
      console.log(`${row.id}. ${row.name} → (${row.latitude}, ${row.longitude})`);
    });
    
    console.log('\n✅ Verification complete!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error updating pharmacy coordinates:', error);
    process.exit(1);
  }
}

updatePharmacyCoordinates();
