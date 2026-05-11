import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    rejectUnauthorized: false,
  },
});

// New accurate pharmacy coordinates
const pharmacyCoordinates = [
  { name: "Akkar Health Supplies", lat: 34.5445, lng: 36.0780 },
  { name: "Halba Health Supplies", lat: 34.5455, lng: 36.0800 },
  
  { name: "Al-Amin Pharmacy", lat: 33.8935, lng: 35.5015 },
  { name: "Ashrafieh MedPlus", lat: 33.8889, lng: 35.5210 },
  { name: "Cola Pharmacy", lat: 33.8745, lng: 35.4955 },
  { name: "Hamra Health Center", lat: 33.8958, lng: 35.4823 },
  { name: "Mansour Medical", lat: 33.8920, lng: 35.5150 },
  { name: "Pharma Plus — Hamra", lat: 33.8965, lng: 35.4805 },
  { name: "Raouche HealthMart", lat: 33.8890, lng: 35.4630 },
  
  { name: "Baalbek Dispensary", lat: 34.0065, lng: 36.2180 },
  { name: "Baalbek Plus", lat: 34.0045, lng: 36.2200 },
  { name: "Bekaa Central Pharmacy", lat: 33.8460, lng: 35.9020 },
  { name: "Deir el Ahmar Pharmacy", lat: 34.0580, lng: 36.1900 },
  { name: "Hermel Medical Supply", lat: 34.3950, lng: 36.3850 },
  
  { name: "Bikfaya Pharmacy", lat: 33.8240, lng: 35.6850 },
  { name: "Choueifat Medical", lat: 33.8305, lng: 35.5335 },
  { name: "Jdeideh Care", lat: 33.8950, lng: 35.5440 },
  { name: "Jounieh Health Center", lat: 33.9815, lng: 35.6180 },
  
  { name: "Marjayoun Dispensary", lat: 33.3605, lng: 35.5915 },
  { name: "Nabatieh City Pharmacy", lat: 33.3795, lng: 35.4840 },
  { name: "Nour Al-Hayat Pharmacy", lat: 33.3780, lng: 35.4820 },
  
  { name: "Batroun Pharmacy", lat: 34.2555, lng: 35.6585 },
  { name: "Byblos Pharma Hub", lat: 34.1220, lng: 35.6485 },
  { name: "Jbeil Community Pharmacy", lat: 34.1245, lng: 35.6505 },
  { name: "Zghorta Medical", lat: 34.3970, lng: 35.8970 },
  
  { name: "Sidon Central Pharmacy", lat: 33.5615, lng: 35.3760 },
  { name: "South Gate Pharmacy", lat: 33.5595, lng: 35.3735 },
  { name: "Tyre Medical Depot", lat: 33.2710, lng: 35.2040 },
  
  { name: "Al-Nour Pharmacy", lat: 34.4360, lng: 35.8440 },
  { name: "Zahrawi Medical", lat: 34.4380, lng: 35.8500 },
];

async function updatePharmacyCoordinates() {
  try {
    console.log('🔄 Updating pharmacy coordinates in Neon database with new accurate data...\n');

    for (const pharmacy of pharmacyCoordinates) {
      await pool.query(
        `UPDATE pharmacies 
         SET latitude = $1, longitude = $2 
         WHERE name = $3`,
        [pharmacy.lat, pharmacy.lng, pharmacy.name]
      );
      console.log(`✅ Updated: ${pharmacy.name.padEnd(35)} → (${pharmacy.lat}, ${pharmacy.lng})`);
    }

    console.log('\n✅ All pharmacy coordinates updated successfully!');
    
    // Verify the updates
    console.log('\n📋 Verifying updated pharmacies...\n');
    const result = await pool.query('SELECT id, name, latitude, longitude, location FROM pharmacies ORDER BY location, name ASC');
    
    let currentLocation = '';
    result.rows.forEach(row => {
      if (row.location !== currentLocation) {
        currentLocation = row.location;
        console.log(`\n📍 ${currentLocation.toUpperCase()}`);
      }
      console.log(`   ${row.name.padEnd(35)} (${row.latitude}, ${row.longitude})`);
    });
    
    console.log('\n✅ Verification complete!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error updating pharmacy coordinates:', error);
    process.exit(1);
  }
}

updatePharmacyCoordinates();
