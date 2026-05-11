#!/bin/bash

# MedTrack360 Backend Setup Script
# This script sets up the Node.js/Express backend for PostgreSQL Neon connection

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         MedTrack360 Backend Setup Script                      ║"
echo "║         PostgreSQL Neon + Node.js/Express                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js first."
    echo "   Visit: https://nodejs.org/"
    exit 1
fi

echo "✅ Node.js version: $(node --version)"
echo "✅ npm version: $(npm --version)"
echo ""

# Create backend directory
BACKEND_DIR="../medtrack360-backend"
if [ ! -d "$BACKEND_DIR" ]; then
    echo "📁 Creating backend directory: $BACKEND_DIR"
    mkdir -p "$BACKEND_DIR"
else
    echo "⚠️  Backend directory already exists"
fi

cd "$BACKEND_DIR"
echo "📂 Working directory: $(pwd)"
echo ""

# Initialize npm project
if [ ! -f "package.json" ]; then
    echo "📦 Initializing npm project..."
    npm init -y
else
    echo "✅ package.json already exists"
fi

echo ""
echo "📥 Installing dependencies..."
npm install express pg dotenv cors helmet bcryptjs jsonwebtoken

echo ""
echo "✅ Creating server.js..."

cat > server.js << 'EOF'
const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const helmet = require('helmet');
require('dotenv').config();

const app = express();

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Database Connection Pool
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    rejectUnauthorized: false,
  },
});

// Test database connection
pool.on('error', (err) => {
  console.error('❌ Unexpected error on idle client', err);
});

pool.connect((err, client, release) => {
  if (err) {
    console.error('❌ Failed to connect to database:', err);
  } else {
    console.log('✅ Connected to Neon PostgreSQL database');
    release();
  }
});

// ─────────────────────────────────────────────────────────────
// MEDICATIONS
// ─────────────────────────────────────────────────────────────

app.get('/api/medications', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM medications ORDER BY brand_name');
    res.json({ success: true, data: result.rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/medications/:id', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM medications WHERE medication_id = $1', [req.params.id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Not found' });
    }
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/medications/search', async (req, res) => {
  try {
    const query = req.query.q || '';
    const result = await pool.query(
      'SELECT * FROM medications WHERE brand_name ILIKE $1 OR generic_name ILIKE $1 ORDER BY brand_name',
      [`%${query}%`]
    );
    res.json({ success: true, data: result.rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────
// PHARMACIES
// ─────────────────────────────────────────────────────────────

app.get('/api/pharmacies', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM pharmacies ORDER BY name');
    res.json({ success: true, data: result.rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/pharmacies/nearby', async (req, res) => {
  try {
    const { lat, lng, radius = 10 } = req.query;
    const result = await pool.query(
      `SELECT *, (6371 * acos(cos(radians($1)) * cos(radians(latitude)) * 
       cos(radians(longitude) - radians($2)) + 
       sin(radians($1)) * sin(radians(latitude)))) AS distance
       FROM pharmacies
       HAVING (6371 * acos(cos(radians($1)) * cos(radians(latitude)) * 
       cos(radians(longitude) - radians($2)) + 
       sin(radians($1)) * sin(radians(latitude)))) <= $3
       ORDER BY distance`,
      [lat, lng, radius]
    );
    res.json({ success: true, data: result.rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/pharmacies/:id', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM pharmacies WHERE pharmacy_id = $1', [req.params.id]);
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Not found' });
    }
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────
// REVIEWS
// ─────────────────────────────────────────────────────────────

app.get('/api/reviews/pharmacy/:pharmacyId', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT r.*, u.full_name FROM reviews r
       JOIN users u ON r.user_id = u.user_id
       WHERE r.pharmacy_id = $1
       ORDER BY r.created_at DESC`,
      [req.params.pharmacyId]
    );
    res.json({ success: true, data: result.rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/reviews', async (req, res) => {
  try {
    const { pharmacy_id, user_id, stock_accuracy_rating, service_quality_rating, comment, has_discrepancy_report, discrepancy_details } = req.body;
    const result = await pool.query(
      `INSERT INTO reviews (pharmacy_id, user_id, stock_accuracy_rating, service_quality_rating, comment, has_discrepancy_report, discrepancy_details)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
      [pharmacy_id, user_id, stock_accuracy_rating, service_quality_rating, comment, has_discrepancy_report, discrepancy_details]
    );
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────
// WATCHLIST
// ─────────────────────────────────────────────────────────────

app.get('/api/watchlist/user/:userId', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT w.*, m.brand_name, m.generic_name FROM watchlist w
       JOIN medications m ON w.medication_id = m.medication_id
       WHERE w.user_id = $1 ORDER BY w.added_at DESC`,
      [req.params.userId]
    );
    res.json({ success: true, data: result.rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/watchlist', async (req, res) => {
  try {
    const { user_id, medication_id, notify_on_available = true } = req.body;
    const result = await pool.query(
      `INSERT INTO watchlist (user_id, medication_id, notify_on_available)
       VALUES ($1, $2, $3) RETURNING *`,
      [user_id, medication_id, notify_on_available]
    );
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.delete('/api/watchlist/:watchlistId', async (req, res) => {
  try {
    await pool.query('DELETE FROM watchlist WHERE watchlist_id = $1', [req.params.watchlistId]);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────
// AUTH
// ─────────────────────────────────────────────────────────────

app.post('/api/auth/register', async (req, res) => {
  try {
    const { full_name, email, password, phone } = req.body;
    const result = await pool.query(
      `INSERT INTO users (full_name, email, phone, password_hash)
       VALUES ($1, $2, $3, $4) RETURNING user_id, full_name, email, phone`,
      [full_name, email, phone, password]
    );
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/auth/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const result = await pool.query(
      'SELECT user_id, full_name, email FROM users WHERE email = $1 AND password_hash = $2 AND is_active = true',
      [email, password]
    );
    if (result.rows.length === 0) {
      return res.status(401).json({ success: false, error: 'Invalid credentials' });
    }
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ─────────────────────────────────────────────────────────────
// HEALTH CHECK
// ─────────────────────────────────────────────────────────────

app.get('/health', (req, res) => {
  res.json({ status: 'Server is running', timestamp: new Date() });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 MedTrack360 API Server running on http://localhost:${PORT}`);
});
EOF

echo "✅ server.js created"
echo ""

echo "✅ Creating .env file..."
cat > .env << 'EOF'
DATABASE_URL=postgresql://neondb_owner:npg_9KkIVN0gRDCw@ep-dry-river-am4quc62-pooler.c-5.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require
PORT=3000
NODE_ENV=development
EOF

echo "✅ .env created"
echo ""

echo "✅ Updating package.json scripts..."
npm set-script start "node server.js"
npm set-script dev "nodemon server.js"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete! ✅                          ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  To start the backend server, run:                             ║"
echo "║                                                                 ║"
echo "║  Development (with auto-reload):                              ║"
echo "║  npm run dev                                                   ║"
echo "║                                                                 ║"
echo "║  Production:                                                   ║"
echo "║  npm start                                                     ║"
echo "║                                                                 ║"
echo "║  Server will run on: http://localhost:3000                    ║"
echo "║                                                                 ║"
echo "║  Database: Neon PostgreSQL                                     ║"
echo "║  Status: Ready to connect                                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
