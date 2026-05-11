import express from 'express';
import { Pool } from 'pg';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { runSchema } from './utils/initDb.js';
import { requireAuth } from './middleware/auth.js';

dotenv.config();

if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) {
  console.warn('⚠️  JWT_SECRET is missing or too short — set a strong secret in .env');
}

const app = express();

// ─────────────────────────────────────────────────────────────
// MIDDLEWARE
// ─────────────────────────────────────────────────────────────

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ─────────────────────────────────────────────────────────────
// DATABASE CONNECTION
// ─────────────────────────────────────────────────────────────

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    rejectUnauthorized: false,
  },
});

pool.on('error', (err) => {
  console.error('❌ Unexpected error on idle client:', err);
});

// Test connection on startup + apply schema
pool.connect(async (err, client, release) => {
  if (err) {
    console.error('❌ Failed to connect to database:', err.stack);
    return;
  }
  console.log('✅ Connected to Neon PostgreSQL database');
  release();
  try {
    await runSchema(pool);
  } catch (e) {
    console.error('❌ Schema init failed:', e.message);
  }
});

// ─────────────────────────────────────────────────────────────
// DATABASE INITIALIZATION
// ─────────────────────────────────────────────────────────────
// Note: Tables are pre-existing in Neon database
// Use the dbInspect.js utility to check database schema

/*
async function initializeTables() {
  try {
    // Create medication_categories table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS medication_categories (
        category_id SERIAL PRIMARY KEY,
        category_name VARCHAR(50) NOT NULL UNIQUE,
        icon_name VARCHAR(50),
        display_order INT DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Create users table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        full_name VARCHAR(100) NOT NULL,
        email VARCHAR(150) NOT NULL UNIQUE,
        phone VARCHAR(20),
        password_hash VARCHAR(255) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        is_active BOOLEAN DEFAULT TRUE
      );
    `);

    // Create medications table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS medications (
        medication_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        brand_name VARCHAR(100) NOT NULL,
        generic_name VARCHAR(150) NOT NULL,
        category_id INT NOT NULL REFERENCES medication_categories(category_id),
        description TEXT,
        ministry_locked_price DECIMAL(10,2) NOT NULL,
        national_availability_score DECIMAL(3,2) NOT NULL CHECK (national_availability_score BETWEEN 0.00 AND 1.00),
        dosage_form VARCHAR(30) NOT NULL,
        strength VARCHAR(30) NOT NULL,
        manufacturer VARCHAR(100) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Create pharmacies table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS pharmacies (
        pharmacy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(150) NOT NULL,
        address VARCHAR(255) NOT NULL,
        latitude DECIMAL(10,7) NOT NULL,
        longitude DECIMAL(10,7) NOT NULL,
        phone VARCHAR(20) NOT NULL,
        rating DECIMAL(2,1) NOT NULL DEFAULT 0.0 CHECK (rating BETWEEN 0.0 AND 5.0),
        review_count INT NOT NULL DEFAULT 0,
        opening_hours VARCHAR(10) NOT NULL,
        closing_hours VARCHAR(10) NOT NULL,
        is_open BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Create pharmacy_stock table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS pharmacy_stock (
        stock_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        pharmacy_id UUID NOT NULL REFERENCES pharmacies(pharmacy_id) ON DELETE CASCADE,
        medication_id UUID NOT NULL REFERENCES medications(medication_id) ON DELETE CASCADE,
        in_stock BOOLEAN NOT NULL DEFAULT FALSE,
        current_price DECIMAL(10,2) NOT NULL,
        last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(pharmacy_id, medication_id)
      );
    `);

    // Create reviews table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS reviews (
        review_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        pharmacy_id UUID NOT NULL REFERENCES pharmacies(pharmacy_id) ON DELETE CASCADE,
        user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
        stock_accuracy_rating DECIMAL(2,1) NOT NULL CHECK (stock_accuracy_rating BETWEEN 0.0 AND 5.0),
        service_quality_rating DECIMAL(2,1) NOT NULL CHECK (service_quality_rating BETWEEN 0.0 AND 5.0),
        comment TEXT,
        has_discrepancy_report BOOLEAN NOT NULL DEFAULT FALSE,
        discrepancy_details TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Create watchlist table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS watchlist (
        watchlist_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
        medication_id UUID NOT NULL REFERENCES medications(medication_id) ON DELETE CASCADE,
        notify_on_available BOOLEAN NOT NULL DEFAULT TRUE,
        added_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(user_id, medication_id)
      );
    `);

    // Create search_history table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS search_history (
        history_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
        query VARCHAR(200) NOT NULL,
        searched_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Create indexes
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_medications_category ON medications(category_id);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_medications_brand ON medications(brand_name);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_medications_generic ON medications(generic_name);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_stock_pharmacy ON pharmacy_stock(pharmacy_id);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_stock_medication ON pharmacy_stock(medication_id);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_stock_in_stock ON pharmacy_stock(in_stock);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_reviews_pharmacy ON reviews(pharmacy_id);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_reviews_user ON reviews(user_id);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_watchlist_user ON watchlist(user_id);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_watchlist_medication ON watchlist(medication_id);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_history_user ON search_history(user_id);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_history_searched_at ON search_history(searched_at DESC);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_pharmacies_location ON pharmacies(latitude, longitude);`);

    console.log('✅ All database tables created successfully');
  } catch (error) {
    console.error('⚠️ Error initializing tables:', error.message);
  }
}
*/

// ─────────────────────────────────────────────────────────────
// HELPER FUNCTIONS
// ─────────────────────────────────────────────────────────────

function handleError(res, error, statusCode = 500) {
  console.error(`❌ Error (${statusCode}):`, error.message);
  res.status(statusCode).json({
    success: false,
    error: error.message,
    timestamp: new Date(),
  });
}

function handleSuccess(res, data, statusCode = 200) {
  res.status(statusCode).json({
    success: true,
    data,
    timestamp: new Date(),
  });
}

// ─────────────────────────────────────────────────────────────
// HEALTH CHECK
// ─────────────────────────────────────────────────────────────

app.get('/health', (req, res) => {
  handleSuccess(res, {
    status: 'Server is running',
    uptime: process.uptime(),
    environment: process.env.NODE_ENV,
  });
});

// ─────────────────────────────────────────────────────────────
// MEDICATIONS ENDPOINTS
// ─────────────────────────────────────────────────────────────

// Get all medications
// Medications are sourced from moph_registry (the MoPH authoritative list).
// Columns are aliased so the JSON response shape stays compatible with the
// Flutter app's existing Medication.fromJson.
const MOPH_MEDICATION_SELECT = `
  SELECT
    r.medication_id,
    r.trade_name                            AS brand_name,
    r.generic_name,
    r.barcode,
    r.reg_number,
    r.is_blocked,
    r.category_id,
    COALESCE(c.category_name, r.category)   AS category_name,
    r.description,
    r.moph_ceiling                          AS ministry_locked_price,
    r.moph_ceiling,
    r.national_availability_score,
    r.form                                  AS dosage_form,
    r.dosage                                AS strength,
    r.manufacturer,
    r.created_at,
    r.updated_at
  FROM moph_registry r
  LEFT JOIN medication_categories c ON c.category_id = r.category_id
`;

app.get('/api/medications', async (req, res) => {
  try {
    const result = await pool.query(
      `${MOPH_MEDICATION_SELECT} ORDER BY r.trade_name ASC`,
    );
    handleSuccess(res, result.rows);
  } catch (error) {
    handleError(res, error);
  }
});

// Search medications (must come before /:id route)
app.get('/api/medications/search', async (req, res) => {
  try {
    const query = req.query.q || '';
    const result = await pool.query(
      `${MOPH_MEDICATION_SELECT}
       WHERE (r.trade_name ILIKE $1 OR r.generic_name ILIKE $1 OR r.barcode ILIKE $1)
       ORDER BY r.trade_name ASC`,
      [`%${query}%`],
    );
    handleSuccess(res, result.rows);
  } catch (error) {
    handleError(res, error);
  }
});

// Get medication by ID (the shared UUID).
app.get('/api/medications/:id', async (req, res) => {
  try {
    const result = await pool.query(
      `${MOPH_MEDICATION_SELECT} WHERE r.medication_id = $1`,
      [req.params.id],
    );

    if (result.rows.length === 0) {
      return handleError(res, new Error('Medication not found'), 404);
    }
    handleSuccess(res, result.rows[0]);
  } catch (error) {
    handleError(res, error);
  }
});

// ─────────────────────────────────────────────────────────────
// MEDICATION CATEGORIES ENDPOINTS
// ─────────────────────────────────────────────────────────────

// Get all categories
app.get('/api/categories', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT * FROM medication_categories ORDER BY display_order ASC
    `);
    handleSuccess(res, result.rows);
  } catch (error) {
    handleError(res, error);
  }
});

// ─────────────────────────────────────────────────────────────
// PHARMACIES ENDPOINTS
// ─────────────────────────────────────────────────────────────

// Get all pharmacies (with per-pharmacy stock array)
app.get('/api/pharmacies', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT p.*,
             COALESCE((
               SELECT json_agg(json_build_object(
                 'medication_id',          ps.medication_id,
                 'medication_name',        m.trade_name,
                 'in_stock',               ps.in_stock,
                 'current_price',          ps.current_price,
                 'ministry_locked_price',  m.moph_ceiling,
                 'last_updated',           ps.last_updated
               ))
               FROM pharmacy_stock ps
               JOIN moph_registry m ON m.medication_id = ps.medication_id
               WHERE ps.pharmacy_id = p.id
             ), '[]'::json) AS stock
      FROM pharmacies p
      ORDER BY p.name ASC
    `);

    const pharmaciesWithNumericCoords = result.rows.map(pharmacy => ({
      ...pharmacy,
      latitude: pharmacy.latitude ? parseFloat(pharmacy.latitude) : 0,
      longitude: pharmacy.longitude ? parseFloat(pharmacy.longitude) : 0,
    }));

    handleSuccess(res, pharmaciesWithNumericCoords);
  } catch (error) {
    handleError(res, error);
  }
});

// Get nearby pharmacies
app.get('/api/pharmacies/nearby', async (req, res) => {
  try {
    const { lat, lng, radius = 10 } = req.query;

    if (!lat || !lng) {
      return handleError(res, new Error('Latitude and longitude required'), 400);
    }

    const result = await pool.query(`
      SELECT *,
        (6371 * acos(cos(radians($1)) * cos(radians(latitude)) * 
        cos(radians(longitude) - radians($2)) + 
        sin(radians($1)) * sin(radians(latitude)))) AS distance
      FROM pharmacies
      HAVING (6371 * acos(cos(radians($1)) * cos(radians(latitude)) * 
       cos(radians(longitude) - radians($2)) + 
       sin(radians($1)) * sin(radians(latitude)))) <= $3
      ORDER BY distance ASC
    `, [lat, lng, radius]);

    handleSuccess(res, result.rows);
  } catch (error) {
    handleError(res, error);
  }
});

// Get pharmacy by ID
app.get('/api/pharmacies/:id', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT * FROM pharmacies WHERE id = $1
    `, [req.params.id]);

    if (result.rows.length === 0) {
      return handleError(res, new Error('Pharmacy not found'), 404);
    }
    
    const pharmacy = result.rows[0];
    // Convert latitude and longitude from strings to numbers
    const pharmacyWithNumericCoords = {
      ...pharmacy,
      latitude: pharmacy.latitude ? parseFloat(pharmacy.latitude) : 0,
      longitude: pharmacy.longitude ? parseFloat(pharmacy.longitude) : 0,
    };
    
    handleSuccess(res, pharmacyWithNumericCoords);
  } catch (error) {
    handleError(res, error);
  }
});

// ─────────────────────────────────────────────────────────────
// PHARMACY STOCK ENDPOINTS
// ─────────────────────────────────────────────────────────────

// Get pharmacies that stock a given medication
app.get('/api/pharmacy-stock/medication/:medicationId', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT ps.stock_id, ps.in_stock, ps.current_price, ps.last_updated,
             p.id AS pharmacy_id, p.name, p.location, p.region,
             p.latitude, p.longitude,
             m.trade_name AS brand_name, m.moph_ceiling AS ministry_locked_price
      FROM pharmacy_stock ps
      JOIN pharmacies    p ON p.id            = ps.pharmacy_id
      JOIN moph_registry m ON m.medication_id = ps.medication_id
      WHERE ps.medication_id = $1 AND ps.in_stock = TRUE
      ORDER BY p.name ASC
    `, [req.params.medicationId]);
    handleSuccess(res, result.rows);
  } catch (error) {
    handleError(res, error);
  }
});

// ─────────────────────────────────────────────────────────────
// REVIEWS ENDPOINTS
// ─────────────────────────────────────────────────────────────

// Get reviews for pharmacy
app.get('/api/reviews/pharmacy/:pharmacyId', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT r.*, u.full_name 
      FROM reviews r
      JOIN users u ON r.user_id = u.user_id
      WHERE r.pharmacy_id = $1
      ORDER BY r.created_at DESC
    `, [req.params.pharmacyId]);
    handleSuccess(res, result.rows);
  } catch (error) {
    handleError(res, error);
  }
});

// Submit review (authenticated — user_id taken from token)
app.post('/api/reviews', requireAuth, async (req, res) => {
  try {
    const {
      pharmacy_id,
      stock_accuracy_rating,
      service_quality_rating,
      comment,
      has_discrepancy_report,
      discrepancy_details,
    } = req.body;

    const result = await pool.query(`
      INSERT INTO reviews
      (pharmacy_id, user_id, stock_accuracy_rating, service_quality_rating,
       comment, has_discrepancy_report, discrepancy_details)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING *
    `, [
      pharmacy_id,
      req.user.user_id,
      stock_accuracy_rating,
      service_quality_rating,
      comment,
      has_discrepancy_report,
      discrepancy_details,
    ]);

    handleSuccess(res, result.rows[0], 201);
  } catch (error) {
    handleError(res, error);
  }
});

// ─────────────────────────────────────────────────────────────
// WATCHLIST ENDPOINTS
// ─────────────────────────────────────────────────────────────

// Get current user's watchlist (authenticated)
app.get('/api/watchlist', requireAuth, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT w.*,
             m.trade_name AS brand_name,
             m.generic_name,
             m.national_availability_score
      FROM watchlist w
      JOIN moph_registry m ON w.medication_id = m.medication_id
      WHERE w.user_id = $1
      ORDER BY w.added_at DESC
    `, [req.user.user_id]);
    handleSuccess(res, result.rows);
  } catch (error) {
    handleError(res, error);
  }
});

// Add to current user's watchlist (authenticated)
app.post('/api/watchlist', requireAuth, async (req, res) => {
  try {
    const { medication_id, notify_on_available = true } = req.body;

    const result = await pool.query(`
      INSERT INTO watchlist (user_id, medication_id, notify_on_available)
      VALUES ($1, $2, $3)
      ON CONFLICT (user_id, medication_id) DO NOTHING
      RETURNING *
    `, [req.user.user_id, medication_id, notify_on_available]);

    handleSuccess(res, result.rows[0] || { message: 'Already in watchlist' }, 201);
  } catch (error) {
    handleError(res, error);
  }
});

// Remove from current user's watchlist (authenticated, scoped)
app.delete('/api/watchlist/:watchlistId', requireAuth, async (req, res) => {
  try {
    const result = await pool.query(`
      DELETE FROM watchlist
      WHERE watchlist_id = $1 AND user_id = $2
      RETURNING watchlist_id
    `, [req.params.watchlistId, req.user.user_id]);

    if (result.rowCount === 0) {
      return handleError(res, new Error('Watchlist item not found'), 404);
    }
    handleSuccess(res, { message: 'Removed from watchlist' });
  } catch (error) {
    handleError(res, error);
  }
});

// ─────────────────────────────────────────────────────────────
// AUTHENTICATION ENDPOINTS
// ─────────────────────────────────────────────────────────────

// Register user — returns user + JWT so the client can sign in immediately
app.post('/api/auth/register', async (req, res) => {
  try {
    const { full_name, email, password, phone } = req.body;

    if (!full_name || !email || !password) {
      return handleError(res, new Error('full_name, email, and password are required'), 400);
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return handleError(res, new Error('Invalid email format'), 400);
    }
    if (password.length < 6) {
      return handleError(res, new Error('Password must be at least 6 characters'), 400);
    }

    const hashedPassword = await bcrypt.hash(password, 10);

    const result = await pool.query(`
      INSERT INTO users (full_name, email, phone, password_hash)
      VALUES ($1, $2, $3, $4)
      RETURNING user_id, full_name, email, phone, created_at
    `, [full_name.trim(), email.trim().toLowerCase(), phone || null, hashedPassword]);

    const user = result.rows[0];
    const token = jwt.sign(
      { user_id: user.user_id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRY || '7d' }
    );

    handleSuccess(res, { ...user, token }, 201);
  } catch (error) {
    if (error.code === '23505') {
      return handleError(res, new Error('Email already registered'), 409);
    }
    handleError(res, error);
  }
});

// Login user
app.post('/api/auth/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return handleError(res, new Error('Email and password required'), 400);
    }

    const result = await pool.query(`
      SELECT * FROM users WHERE email = $1 AND is_active = true
    `, [email.trim().toLowerCase()]);

    if (result.rows.length === 0) {
      return handleError(res, new Error('Invalid credentials'), 401);
    }

    const user = result.rows[0];
    const passwordMatch = await bcrypt.compare(password, user.password_hash);

    if (!passwordMatch) {
      return handleError(res, new Error('Invalid credentials'), 401);
    }

    const token = jwt.sign(
      { user_id: user.user_id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRY || '7d' }
    );

    handleSuccess(res, {
      user_id: user.user_id,
      full_name: user.full_name,
      email: user.email,
      phone: user.phone,
      token,
    });
  } catch (error) {
    handleError(res, error);
  }
});

// Get current user from token
app.get('/api/auth/me', requireAuth, async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT user_id, full_name, email, phone, created_at FROM users WHERE user_id = $1 AND is_active = true',
      [req.user.user_id]
    );
    if (result.rows.length === 0) {
      return handleError(res, new Error('User not found'), 404);
    }
    handleSuccess(res, result.rows[0]);
  } catch (error) {
    handleError(res, error);
  }
});

// ─────────────────────────────────────────────────────────────
// SEARCH HISTORY ENDPOINTS
// ─────────────────────────────────────────────────────────────

// Save search query (authenticated)
app.post('/api/search-history', requireAuth, async (req, res) => {
  try {
    const { query } = req.body;
    if (!query || !query.trim()) {
      return handleError(res, new Error('query required'), 400);
    }

    const result = await pool.query(`
      INSERT INTO search_history (user_id, query)
      VALUES ($1, $2)
      RETURNING *
    `, [req.user.user_id, query.trim()]);

    handleSuccess(res, result.rows[0], 201);
  } catch (error) {
    handleError(res, error);
  }
});

// Get current user's search history (authenticated)
app.get('/api/search-history', requireAuth, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT * FROM search_history
      WHERE user_id = $1
      ORDER BY searched_at DESC
      LIMIT 20
    `, [req.user.user_id]);
    handleSuccess(res, result.rows);
  } catch (error) {
    handleError(res, error);
  }
});

// ─────────────────────────────────────────────────────────────
// NOTIFICATIONS
// ─────────────────────────────────────────────────────────────

// List the signed-in user's notifications, newest first.
app.get('/api/notifications', requireAuth, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT notification_id, type, title, body, payload, read_at, created_at
         FROM notifications
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT 100`,
      [req.user.user_id],
    );
    handleSuccess(res, result.rows);
  } catch (error) {
    handleError(res, error);
  }
});

// Unread count for the bell badge.
app.get('/api/notifications/unread-count', requireAuth, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT COUNT(*)::int AS count
         FROM notifications
        WHERE user_id = $1 AND read_at IS NULL`,
      [req.user.user_id],
    );
    handleSuccess(res, { count: result.rows[0].count });
  } catch (error) {
    handleError(res, error);
  }
});

// Mark one notification as read.
app.post('/api/notifications/:id/read', requireAuth, async (req, res) => {
  try {
    const result = await pool.query(
      `UPDATE notifications
          SET read_at = CURRENT_TIMESTAMP
        WHERE notification_id = $1 AND user_id = $2 AND read_at IS NULL
        RETURNING notification_id`,
      [req.params.id, req.user.user_id],
    );
    handleSuccess(res, { updated: result.rowCount });
  } catch (error) {
    handleError(res, error);
  }
});

// Mark every notification for the user as read.
app.post('/api/notifications/read-all', requireAuth, async (req, res) => {
  try {
    const result = await pool.query(
      `UPDATE notifications
          SET read_at = CURRENT_TIMESTAMP
        WHERE user_id = $1 AND read_at IS NULL`,
      [req.user.user_id],
    );
    handleSuccess(res, { updated: result.rowCount });
  } catch (error) {
    handleError(res, error);
  }
});

// ─────────────────────────────────────────────────────────────
// ERROR HANDLING
// ─────────────────────────────────────────────────────────────

app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'Route not found',
    path: req.path,
  });
});

// ─────────────────────────────────────────────────────────────
// START SERVER
// ─────────────────────────────────────────────────────────────

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log('╔════════════════════════════════════════════════╗');
  console.log('║  🚀 MedTrack360 API Server Started             ║');
  console.log(`║  📡 Server running on http://localhost:${PORT}       ║`);
  console.log('║  🗄️  Connected to Neon PostgreSQL              ║');
  console.log('║  📊 Database: medtrack360                       ║');
  console.log('╚════════════════════════════════════════════════╝');
  console.log('');
  console.log('Available endpoints:');
  console.log('  GET    /health');
  console.log('  GET    /api/medications');
  console.log('  GET    /api/medications/search?q=query');
  console.log('  GET    /api/pharmacies');
  console.log('  GET    /api/pharmacies/nearby?lat=X&lng=Y&radius=Z');
  console.log('  GET    /api/reviews/pharmacy/:id');
  console.log('  POST   /api/reviews                (auth)');
  console.log('  GET    /api/watchlist              (auth)');
  console.log('  POST   /api/watchlist              (auth)');
  console.log('  DELETE /api/watchlist/:id          (auth)');
  console.log('  GET    /api/search-history        (auth)');
  console.log('  POST   /api/search-history        (auth)');
  console.log('  POST   /api/auth/register');
  console.log('  POST   /api/auth/login');
  console.log('  GET    /api/auth/me                (auth)');
  console.log('  GET    /api/notifications          (auth)');
  console.log('  GET    /api/notifications/unread-count (auth)');
  console.log('  POST   /api/notifications/:id/read (auth)');
  console.log('  POST   /api/notifications/read-all (auth)');
  console.log('');
});

export default app;
