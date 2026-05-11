require('dotenv').config();
const { Pool } = require('pg');

const connectionString =
  process.env.DATABASE_URL ||
  process.env.POSTGRES_URL ||
  process.env.POSTGRES_URI ||
  'postgresql://postgres:postgres@localhost:5432/medtrack';

const shouldUseSsl = /sslmode=require/i.test(connectionString) || process.env.PGSSL === 'true';

const pool = new Pool({
  connectionString,
  ssl: shouldUseSsl ? { rejectUnauthorized: false } : undefined,
});

async function initializeSchema() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(`
      CREATE TABLE IF NOT EXISTS pharmacies (
        id              SERIAL PRIMARY KEY,
        name            VARCHAR(255) NOT NULL,
        location        VARCHAR(255),
        license_number  VARCHAR(50)  UNIQUE NOT NULL,
        hwid            VARCHAR(50)  UNIQUE,
        region          VARCHAR(100),
        status          VARCHAR(20)  DEFAULT 'online',
        last_seen       VARCHAR(50)  DEFAULT 'just now',
        latency_ms      INTEGER,
        sync_version    VARCHAR(20)  DEFAULT '2.6.1',
        sync_pct        INTEGER      DEFAULT 100,
        created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS registration_requests (
        id             SERIAL PRIMARY KEY,
        reg_id         VARCHAR(20)  UNIQUE NOT NULL,
        name           VARCHAR(255) NOT NULL,
        owner          VARCHAR(255),
        region         VARCHAR(100),
        submitted_date DATE,
        status         VARCHAR(30)  DEFAULT 'pending_review',
        docs_count     INTEGER      DEFAULT 0,
        missing_count  INTEGER      DEFAULT 0,
        created_at     TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS medicine_registration_requests (
        id                  SERIAL PRIMARY KEY,
        request_uuid        UUID NOT NULL UNIQUE,
        pharmacy_id         INT REFERENCES pharmacies(id),
        device_id           VARCHAR(64),
        barcode             VARCHAR(50) NOT NULL,
        requested_name      VARCHAR(255) NOT NULL DEFAULT '',
        generic_name        VARCHAR(255) NOT NULL DEFAULT '',
        dosage              VARCHAR(100) NOT NULL DEFAULT '',
        category            VARCHAR(100) NOT NULL DEFAULT '',
        proposed_price_minor BIGINT,
        stock_units         INTEGER NOT NULL DEFAULT 0,
        expiry              VARCHAR(80) NOT NULL DEFAULT '',
        request_status      VARCHAR(30) NOT NULL DEFAULT 'pending_review',
        official_medicine_id INT,
        review_notes        TEXT NOT NULL DEFAULT '',
        metadata            JSONB NOT NULL DEFAULT '{}'::jsonb,
        reviewed_at         TIMESTAMP,
        created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        deleted_at          TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS moph_registry (
        id            SERIAL PRIMARY KEY,
        barcode       VARCHAR(50)   UNIQUE NOT NULL,
        reg_number    VARCHAR(50),
        trade_name    VARCHAR(255)  NOT NULL,
        generic_name  VARCHAR(255)  NOT NULL,
        dosage        VARCHAR(100),
        form          VARCHAR(100),
        manufacturer  VARCHAR(255),
        category      VARCHAR(100),
        moph_ceiling  NUMERIC(10,2),
        is_blocked    BOOLEAN       DEFAULT false,
        created_at    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
        updated_at    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS medicines (
        id                    BIGSERIAL PRIMARY KEY,
        medicine_uuid         UUID NOT NULL UNIQUE,
        barcode               VARCHAR(50) NOT NULL UNIQUE,
        reg_number            VARCHAR(50),
        trade_name            VARCHAR(255) NOT NULL,
        generic_name          VARCHAR(255) NOT NULL DEFAULT '',
        dosage                VARCHAR(100) NOT NULL DEFAULT '',
        form                  VARCHAR(100) NOT NULL DEFAULT '',
        manufacturer          VARCHAR(255) NOT NULL DEFAULT '',
        category              VARCHAR(100) NOT NULL DEFAULT '',
        regulated_price_minor BIGINT,
        currency_code         VARCHAR(3) NOT NULL DEFAULT 'USD',
        is_blocked            BOOLEAN NOT NULL DEFAULT false,
        compliance_flags      JSONB NOT NULL DEFAULT '[]'::jsonb,
        version               INTEGER NOT NULL DEFAULT 1,
        updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at            TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS product_batches (
        id                  BIGSERIAL PRIMARY KEY,
        batch_uuid          UUID NOT NULL UNIQUE,
        pharmacy_id         INT NOT NULL REFERENCES pharmacies(id),
        barcode             VARCHAR(50) NOT NULL,
        batch_number        VARCHAR(120) NOT NULL,
        expiry_at           TIMESTAMPTZ,
        quantity_on_hand    INTEGER NOT NULL DEFAULT 0,
        unit_cost_minor     BIGINT,
        unit_price_minor    BIGINT,
        currency_code       VARCHAR(3) NOT NULL DEFAULT 'USD',
        supplier_name       VARCHAR(255),
        source_reference_id VARCHAR(120),
        version             INTEGER NOT NULL DEFAULT 1,
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at          TIMESTAMPTZ
      );
    `);

    await client.query(`ALTER TABLE moph_registry ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT false`);

    await client.query(`
      CREATE TABLE IF NOT EXISTS national_stock (
        id              SERIAL PRIMARY KEY,
        barcode         VARCHAR(50),
        medication_name VARCHAR(255) NOT NULL,
        category        VARCHAR(100),
        pharmacy_name   VARCHAR(255),
        license_number  VARCHAR(50),
        hwid            VARCHAR(50),
        stock_units     INTEGER      DEFAULT 0,
        threshold       INTEGER      DEFAULT 1000,
        status          VARCHAR(20)  DEFAULT 'safe',
        region          VARCHAR(100),
        last_sync       VARCHAR(50)  DEFAULT 'just now',
        updated_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS hoarding_alerts (
        id              SERIAL PRIMARY KEY,
        pharmacy_name   VARCHAR(255),
        license_number  VARCHAR(50),
        hwid            VARCHAR(50),
        region          VARCHAR(100),
        incoming_units  INTEGER      DEFAULT 0,
        outgoing_units  INTEGER      DEFAULT 0,
        ratio           NUMERIC(5,1) DEFAULT 0,
        score           INTEGER      DEFAULT 0,
        flag            VARCHAR(20)  DEFAULT 'watch',
        flagged_items   JSONB        DEFAULT '[]',
        dismissed       BOOLEAN      DEFAULT false,
        created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS sales_log (
        id            SERIAL PRIMARY KEY,
        receipt_id    VARCHAR(100) UNIQUE NOT NULL,
        pharmacy_id   INT REFERENCES pharmacies(id),
        device_id     VARCHAR(64),
        version       INTEGER      DEFAULT 1,
        sale_data     JSONB        NOT NULL,
        sync_status   VARCHAR(20)  DEFAULT 'synced',
        updated_at    TIMESTAMPTZ  DEFAULT NOW(),
        deleted_at    TIMESTAMPTZ,
        created_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
        pos_created_at TIMESTAMP
      );
    `);

    await client.query(`ALTER TABLE sales_log ADD COLUMN IF NOT EXISTS device_id VARCHAR(64)`);
    await client.query(`ALTER TABLE sales_log ADD COLUMN IF NOT EXISTS version INTEGER DEFAULT 1`);
    await client.query(`ALTER TABLE sales_log ADD COLUMN IF NOT EXISTS sync_status VARCHAR(20) DEFAULT 'synced'`);
    await client.query(`ALTER TABLE sales_log ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW()`);
    await client.query(`ALTER TABLE sales_log ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ`);

    await client.query(`
      CREATE TABLE IF NOT EXISTS pos_inventory_movements (
        id                BIGSERIAL PRIMARY KEY,
        movement_uuid     UUID NOT NULL UNIQUE,
        pharmacy_id       INT NOT NULL REFERENCES pharmacies(id),
        device_id         VARCHAR(64) NOT NULL,
        version           INTEGER NOT NULL DEFAULT 1,
        barcode           VARCHAR(50) NOT NULL,
        movement_type     VARCHAR(40) NOT NULL,
        quantity_delta    INTEGER NOT NULL DEFAULT 0,
        unit_price_minor  BIGINT,
        currency_code     VARCHAR(3) NOT NULL DEFAULT 'USD',
        reference_type    VARCHAR(40) NOT NULL DEFAULT '',
        reference_id      VARCHAR(120) NOT NULL DEFAULT '',
        metadata          JSONB NOT NULL DEFAULT '{}'::jsonb,
        happened_at       TIMESTAMPTZ NOT NULL,
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at        TIMESTAMPTZ,
        sync_status       VARCHAR(20) NOT NULL DEFAULT 'synced',
        created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS inventory_movements (
        id                BIGSERIAL PRIMARY KEY,
        event_uuid        UUID NOT NULL UNIQUE,
        pharmacy_id       INT NOT NULL REFERENCES pharmacies(id),
        device_id         VARCHAR(64) NOT NULL,
        source            VARCHAR(30) NOT NULL DEFAULT 'pos',
        barcode           VARCHAR(50) NOT NULL,
        movement_type     VARCHAR(40) NOT NULL,
        quantity_delta    INTEGER NOT NULL DEFAULT 0,
        unit_price_minor  BIGINT,
        currency_code     VARCHAR(3) NOT NULL DEFAULT 'USD',
        reference_type    VARCHAR(40) NOT NULL DEFAULT '',
        reference_id      VARCHAR(120) NOT NULL DEFAULT '',
        metadata          JSONB NOT NULL DEFAULT '{}'::jsonb,
        happened_at       TIMESTAMPTZ NOT NULL,
        version           INTEGER NOT NULL DEFAULT 1,
        sync_status       VARCHAR(20) NOT NULL DEFAULT 'synced',
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at        TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS sales (
        id                 BIGSERIAL PRIMARY KEY,
        sale_uuid          UUID NOT NULL UNIQUE,
        pharmacy_id        INT NOT NULL REFERENCES pharmacies(id),
        device_id          VARCHAR(64) NOT NULL,
        receipt_id         VARCHAR(100) NOT NULL,
        sold_at            TIMESTAMPTZ NOT NULL,
        customer_name      VARCHAR(255),
        payment_method     VARCHAR(30) NOT NULL DEFAULT 'CASH',
        subtotal_minor     BIGINT NOT NULL DEFAULT 0,
        moph_tax_minor     BIGINT NOT NULL DEFAULT 0,
        vat_minor          BIGINT NOT NULL DEFAULT 0,
        grand_total_minor  BIGINT NOT NULL DEFAULT 0,
        currency_code      VARCHAR(3) NOT NULL DEFAULT 'USD',
        version            INTEGER NOT NULL DEFAULT 1,
        sync_status        VARCHAR(20) NOT NULL DEFAULT 'synced',
        payload            JSONB NOT NULL DEFAULT '{}'::jsonb,
        updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at         TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS sale_items (
        id                BIGSERIAL PRIMARY KEY,
        sale_id           BIGINT NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
        line_uuid         UUID NOT NULL UNIQUE,
        barcode           VARCHAR(50) NOT NULL,
        product_name      VARCHAR(255) NOT NULL,
        dosage            VARCHAR(100) NOT NULL DEFAULT '',
        quantity          INTEGER NOT NULL,
        unit_price_minor  BIGINT NOT NULL,
        line_total_minor  BIGINT NOT NULL,
        batch_number      VARCHAR(120),
        version           INTEGER NOT NULL DEFAULT 1,
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at        TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS purchases (
        id                  BIGSERIAL PRIMARY KEY,
        purchase_uuid       UUID NOT NULL UNIQUE,
        pharmacy_id         INT NOT NULL REFERENCES pharmacies(id),
        device_id           VARCHAR(64) NOT NULL,
        receipt_id          VARCHAR(120) NOT NULL,
        supplier_name       VARCHAR(255),
        invoice_number      VARCHAR(120),
        purchased_at        TIMESTAMPTZ NOT NULL,
        total_cost_minor    BIGINT NOT NULL DEFAULT 0,
        currency_code       VARCHAR(3) NOT NULL DEFAULT 'USD',
        version             INTEGER NOT NULL DEFAULT 1,
        sync_status         VARCHAR(20) NOT NULL DEFAULT 'synced',
        payload             JSONB NOT NULL DEFAULT '{}'::jsonb,
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at          TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS purchase_items (
        id                BIGSERIAL PRIMARY KEY,
        purchase_id       BIGINT NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
        line_uuid         UUID NOT NULL UNIQUE,
        barcode           VARCHAR(50) NOT NULL,
        product_name      VARCHAR(255) NOT NULL,
        dosage            VARCHAR(100) NOT NULL DEFAULT '',
        quantity          INTEGER NOT NULL,
        unit_cost_minor   BIGINT NOT NULL,
        line_total_minor  BIGINT NOT NULL,
        batch_number      VARCHAR(120),
        version           INTEGER NOT NULL DEFAULT 1,
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at        TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS returns (
        id                  BIGSERIAL PRIMARY KEY,
        return_uuid         UUID NOT NULL UNIQUE,
        pharmacy_id         INT NOT NULL REFERENCES pharmacies(id),
        device_id           VARCHAR(64) NOT NULL,
        barcode             VARCHAR(50) NOT NULL,
        return_type         VARCHAR(30) NOT NULL,
        quantity            INTEGER NOT NULL,
        unit_price_minor    BIGINT,
        reason              VARCHAR(255),
        reference_id        VARCHAR(120),
        happened_at         TIMESTAMPTZ NOT NULL,
        version             INTEGER NOT NULL DEFAULT 1,
        sync_status         VARCHAR(20) NOT NULL DEFAULT 'synced',
        metadata            JSONB NOT NULL DEFAULT '{}'::jsonb,
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at          TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS stock_adjustments (
        id                  BIGSERIAL PRIMARY KEY,
        adjustment_uuid     UUID NOT NULL UNIQUE,
        pharmacy_id         INT NOT NULL REFERENCES pharmacies(id),
        device_id           VARCHAR(64) NOT NULL,
        barcode             VARCHAR(50) NOT NULL,
        quantity_delta      INTEGER NOT NULL,
        reason              VARCHAR(255) NOT NULL DEFAULT '',
        reference_id        VARCHAR(120),
        happened_at         TIMESTAMPTZ NOT NULL,
        version             INTEGER NOT NULL DEFAULT 1,
        sync_status         VARCHAR(20) NOT NULL DEFAULT 'synced',
        metadata            JSONB NOT NULL DEFAULT '{}'::jsonb,
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at          TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS prices (
        id                    BIGSERIAL PRIMARY KEY,
        barcode               VARCHAR(50) NOT NULL UNIQUE,
        regulated_price_minor BIGINT,
        local_price_minor     BIGINT,
        currency_code         VARCHAR(3) NOT NULL DEFAULT 'USD',
        source                VARCHAR(30) NOT NULL DEFAULT 'moph',
        version               INTEGER NOT NULL DEFAULT 1,
        updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at            TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS price_history (
        id                    BIGSERIAL PRIMARY KEY,
        history_uuid          UUID NOT NULL UNIQUE,
        barcode               VARCHAR(50) NOT NULL,
        pharmacy_id           INT REFERENCES pharmacies(id),
        previous_price_minor  BIGINT,
        new_price_minor       BIGINT,
        currency_code         VARCHAR(3) NOT NULL DEFAULT 'USD',
        source                VARCHAR(30) NOT NULL,
        changed_by            VARCHAR(255),
        changed_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        metadata              JSONB NOT NULL DEFAULT '{}'::jsonb
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS compliance_alerts (
        id                  BIGSERIAL PRIMARY KEY,
        alert_uuid          UUID NOT NULL UNIQUE,
        pharmacy_id         INT REFERENCES pharmacies(id),
        device_id           VARCHAR(64),
        barcode             VARCHAR(50),
        alert_type          VARCHAR(40) NOT NULL,
        severity            VARCHAR(20) NOT NULL DEFAULT 'medium',
        title               VARCHAR(255) NOT NULL,
        details             JSONB NOT NULL DEFAULT '{}'::jsonb,
        status              VARCHAR(20) NOT NULL DEFAULT 'open',
        source              VARCHAR(30) NOT NULL DEFAULT 'server',
        version             INTEGER NOT NULL DEFAULT 1,
        created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        acknowledged_at     TIMESTAMPTZ,
        resolved_at         TIMESTAMPTZ,
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at          TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS sync_conflict_log (
        id                BIGSERIAL PRIMARY KEY,
        conflict_uuid     UUID NOT NULL UNIQUE,
        pharmacy_id       INT NOT NULL REFERENCES pharmacies(id),
        device_id         VARCHAR(64),
        entity_type       VARCHAR(50) NOT NULL,
        entity_id         VARCHAR(120) NOT NULL,
        field             VARCHAR(80) NOT NULL,
        conflict_code     VARCHAR(80) NOT NULL,
        local_value       JSONB,
        server_value      JSONB,
        resolution        VARCHAR(40) NOT NULL DEFAULT 'server_override',
        note              TEXT NOT NULL DEFAULT '',
        source            VARCHAR(30) NOT NULL DEFAULT 'server',
        created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at        TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS audit_change_log (
        id                BIGSERIAL PRIMARY KEY,
        change_uuid       UUID NOT NULL UNIQUE,
        pharmacy_id       INT REFERENCES pharmacies(id),
        entity_type       VARCHAR(50) NOT NULL,
        entity_id         VARCHAR(120) NOT NULL,
        change_type       VARCHAR(50) NOT NULL,
        old_value         JSONB,
        new_value         JSONB,
        actor_identity    VARCHAR(120),
        actor_role        VARCHAR(40),
        device_id         VARCHAR(64),
        source_ip         VARCHAR(80),
        source            VARCHAR(30) NOT NULL DEFAULT 'api',
        request_id        VARCHAR(120),
        created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at        TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS sync_outbox (
        id                  BIGSERIAL PRIMARY KEY,
        event_uuid          UUID NOT NULL UNIQUE,
        pharmacy_id         INT REFERENCES pharmacies(id),
        device_id           VARCHAR(64),
        direction           VARCHAR(10) NOT NULL,
        stream              VARCHAR(50) NOT NULL,
        payload             JSONB NOT NULL,
        sync_status         VARCHAR(20) NOT NULL DEFAULT 'pending',
        retry_count         INTEGER NOT NULL DEFAULT 0,
        next_retry_at       TIMESTAMPTZ,
        last_error          TEXT,
        created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        deleted_at          TIMESTAMPTZ
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS sync_checkpoint (
        id                  BIGSERIAL PRIMARY KEY,
        pharmacy_id         INT REFERENCES pharmacies(id),
        device_id           VARCHAR(64) NOT NULL,
        stream              VARCHAR(50) NOT NULL,
        checkpoint_token    VARCHAR(255) NOT NULL,
        checkpoint_time     TIMESTAMPTZ NOT NULL,
        updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (device_id, stream)
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS sync_requests (
        id                BIGSERIAL PRIMARY KEY,
        request_id        VARCHAR(120) NOT NULL UNIQUE,
        pharmacy_id       INT NOT NULL REFERENCES pharmacies(id),
        device_id         VARCHAR(64) NOT NULL,
        endpoint          VARCHAR(120) NOT NULL,
        payload           JSONB NOT NULL DEFAULT '{}'::jsonb,
        response_payload  JSONB,
        request_status    VARCHAR(20) NOT NULL DEFAULT 'processing',
        created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS audit_logs (
        id              SERIAL PRIMARY KEY,
        event_id        VARCHAR(30),
        pharmacy_name   VARCHAR(255),
        hwid            VARCHAR(50),
        license_number  VARCHAR(50),
        region          VARCHAR(100),
        event_type      VARCHAR(50)  NOT NULL,
        item_name       VARCHAR(255),
        registry_price  NUMERIC(10,2),
        charged_price   NUMERIC(10,2),
        unit_count      INTEGER,
        metadata        JSONB,
        resolved        BOOLEAN      DEFAULT false,
        created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS distributors (
        id                SERIAL PRIMARY KEY,
        dist_id           VARCHAR(30) UNIQUE NOT NULL,
        name              VARCHAR(255) NOT NULL,
        iqr               VARCHAR(50) UNIQUE,
        status            VARCHAR(20) DEFAULT 'verified',
        registered_since  DATE,
        created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS admin_users (
        id            SERIAL PRIMARY KEY,
        name          VARCHAR(255) NOT NULL,
        email         VARCHAR(255) UNIQUE NOT NULL,
        role          VARCHAR(100) NOT NULL,
        twofa         BOOLEAN DEFAULT true,
        last_login    TIMESTAMP,
        created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS stock_thresholds (
        id          SERIAL PRIMARY KEY,
        category    VARCHAR(120) UNIQUE NOT NULL,
        units       INTEGER NOT NULL,
        created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS adjustment_reasons (
        id          SERIAL PRIMARY KEY,
        reason      VARCHAR(255) UNIQUE NOT NULL,
        created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS system_settings (
        key         VARCHAR(120) PRIMARY KEY,
        value       JSONB NOT NULL,
        updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS pos_sync_state (
        id SERIAL PRIMARY KEY,
        hwid VARCHAR(50) UNIQUE,
        pharmacy_id INT,
        last_sync_up TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_sync_down TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        pending_updates BOOLEAN DEFAULT true,
        app_version VARCHAR(20),
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS change_log (
        id SERIAL PRIMARY KEY,
        change_type VARCHAR(50) NOT NULL,
        entity_id INT,
        entity_type VARCHAR(50),
        old_value JSONB,
        new_value JSONB,
        changed_by VARCHAR(255),
        synced_to_pos BOOLEAN DEFAULT false,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    await client.query(`
      CREATE OR REPLACE VIEW audit_log AS
      SELECT
        id,
        event_id,
        pharmacy_name,
        hwid,
        license_number,
        region,
        event_type,
        item_name,
        registry_price,
        charged_price,
        unit_count,
        metadata,
        resolved,
        created_at
      FROM audit_logs;
    `);

    // Create database indexes for fast queries
    await client.query(`ALTER TABLE national_stock ADD COLUMN IF NOT EXISTS pharmacy_name VARCHAR(255)`);
    await client.query(`ALTER TABLE national_stock ADD COLUMN IF NOT EXISTS license_number VARCHAR(50)`);
    await client.query(`ALTER TABLE national_stock ADD COLUMN IF NOT EXISTS hwid VARCHAR(50)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_moph_barcode ON moph_registry(barcode)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_moph_blocked ON moph_registry(is_blocked)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_moph_category ON moph_registry(category)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_medicines_barcode ON medicines(barcode)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_national_stock_barcode ON national_stock(barcode)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_national_stock_license ON national_stock(license_number)`);
    await client.query(`CREATE UNIQUE INDEX IF NOT EXISTS idx_national_stock_barcode_license_unique ON national_stock(barcode, license_number) WHERE license_number IS NOT NULL`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sales_log_pharmacy_id ON sales_log(pharmacy_id)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sales_log_created_at ON sales_log(created_at)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_audit_logs_pharmacy_name ON audit_logs(pharmacy_name)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_pos_sync_state_hwid ON pos_sync_state(hwid)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sales_log_device ON sales_log(device_id)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sales_log_updated_at ON sales_log(updated_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_pim_pharmacy_happened_at ON pos_inventory_movements(pharmacy_id, happened_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_pim_barcode ON pos_inventory_movements(barcode)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_im_barcode_happened ON inventory_movements(barcode, happened_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sales_pharmacy_sold_at ON sales(pharmacy_id, sold_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sale_items_barcode ON sale_items(barcode)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_purchases_pharmacy ON purchases(pharmacy_id, purchased_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_returns_pharmacy ON returns(pharmacy_id, happened_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_stock_adjustments_pharmacy ON stock_adjustments(pharmacy_id, happened_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_prices_barcode ON prices(barcode)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_price_history_barcode_changed_at ON price_history(barcode, changed_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_compliance_alerts_open ON compliance_alerts(status, created_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sync_outbox_status ON sync_outbox(sync_status, created_at ASC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sync_checkpoint_stream ON sync_checkpoint(device_id, stream)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sync_requests_pharmacy_endpoint ON sync_requests(pharmacy_id, endpoint, created_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sync_requests_device_created ON sync_requests(device_id, created_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_inventory_movements_pharmacy_cursor ON inventory_movements(pharmacy_id, updated_at ASC, event_uuid ASC) WHERE deleted_at IS NULL`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_compliance_alerts_pharmacy_open ON compliance_alerts(pharmacy_id, status, created_at DESC) WHERE deleted_at IS NULL`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_prices_updated ON prices(updated_at DESC) WHERE deleted_at IS NULL`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sync_conflict_log_pharmacy_created ON sync_conflict_log(pharmacy_id, created_at DESC) WHERE deleted_at IS NULL`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sync_conflict_log_entity ON sync_conflict_log(entity_type, entity_id, created_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_audit_change_log_pharmacy_created ON audit_change_log(pharmacy_id, created_at DESC) WHERE deleted_at IS NULL`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_audit_change_log_entity ON audit_change_log(entity_type, entity_id, created_at DESC)`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_audit_change_log_request ON audit_change_log(request_id, created_at DESC)`);

    await client.query(`ALTER TABLE inventory_movements ADD COLUMN IF NOT EXISTS source VARCHAR(30) NOT NULL DEFAULT 'pos'`);
    await client.query(`ALTER TABLE compliance_alerts ADD COLUMN IF NOT EXISTS source VARCHAR(30) NOT NULL DEFAULT 'server'`);
    await client.query(`ALTER TABLE compliance_alerts ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1`);
    await client.query(`ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP`);

    // health_news table is created elsewhere (pharmacy app schema).
    // Add an is_active flag so the dashboard can soft-deactivate broadcasts.
    await client.query(`ALTER TABLE health_news ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_health_news_active_published ON health_news(is_active, published_at DESC)`);
    
    console.log('[DB] Schema ready with indexes.');
    await client.query('COMMIT');
    await seedData();
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[DB] Schema init failed:', err.message);
    throw err;
  } finally {
    client.release();
  }
}

async function seedData() {
  // Real-data-only mode: do not inject any demo pharmacies, medications, or events.
  // All records must come from actual POS sync and operational workflows.
  console.log('[DB] Seed skipped (real-data-only mode).');
}

async function checkDatabaseConnection() {
  const result = await pool.query('SELECT 1 AS ok');
  return result.rows[0]?.ok === 1;
}

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool,
  initializeSchema,
  checkDatabaseConnection,
};
