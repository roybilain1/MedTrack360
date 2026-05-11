-- ═══════════════════════════════════════════════════════════════════════════
--  MedTrack 360 — POS Terminal Local Database Schema  (SQLite)
--  Stored at: <getDatabasesPath()>/medtrack_inventory.db
--  Managed by: lib/services/inventory_database.dart  (Flutter / sqflite_ffi)
--  This file is the canonical SQL reference for the POS local schema.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: inventory
--  All medications currently stocked at this pharmacy terminal.
--  barcode is EAN-13; moph_ceiling is pushed from the Command Center.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    barcode       TEXT    NOT NULL UNIQUE,        -- EAN-13 / manufacturer barcode
    name          TEXT    NOT NULL,               -- trade name (generic) e.g. "Amoxil (Amoxicillin)"
    dosage        TEXT    NOT NULL DEFAULT '',    -- e.g. "500 mg"
    category      TEXT    NOT NULL DEFAULT '',    -- e.g. "Antibiotic"
    stock         INTEGER NOT NULL DEFAULT 0,
    expiry        TEXT    NOT NULL DEFAULT '',    -- e.g. "Dec 2026"
    price         REAL    NOT NULL DEFAULT 0.0,   -- pharmacy's selling price (USD)
    moph_ceiling  REAL,                           -- MoPH official ceiling price; NULL = not assigned
    batch_number  TEXT    NOT NULL DEFAULT '',    -- lot number for traceability
    product_uuid  TEXT,                           -- canonical product UUID (sync identity)
    version       INTEGER NOT NULL DEFAULT 1,
    updated_at    INTEGER,
    deleted_at    INTEGER,
    is_blocked    INTEGER NOT NULL DEFAULT 0,     -- server authoritative compliance block flag
    server_updated_at INTEGER                      -- UTC epoch ms from server sync-down
);

CREATE INDEX IF NOT EXISTS idx_inventory_barcode   ON inventory (barcode);
CREATE UNIQUE INDEX IF NOT EXISTS idx_inventory_product_uuid_unique ON inventory (product_uuid) WHERE product_uuid IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_name      ON inventory (name);
CREATE INDEX IF NOT EXISTS idx_inventory_category  ON inventory (category);
CREATE INDEX IF NOT EXISTS idx_inventory_stock     ON inventory (stock);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: unmapped_barcodes
--  Barcodes scanned at checkout that are NOT in the inventory table.
--  Reported to the MoPH Command Center Audit Trails for resolution.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS unmapped_barcodes (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    barcode    TEXT    NOT NULL UNIQUE,
    scan_count INTEGER NOT NULL DEFAULT 1,
    first_seen INTEGER NOT NULL               -- epoch milliseconds
);

CREATE INDEX IF NOT EXISTS idx_unmapped_barcode ON unmapped_barcodes (barcode);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: offline_sale_queue
--  Sales captured while the POS has no network connection.
--  sale_data is a JSON blob containing the full sale payload.
--  On reconnect, unsynced rows are uploaded to the Command Center and
--  marked synced = 1, then purged by clearAcknowledged().
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS offline_sale_queue (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    receipt_id  TEXT    NOT NULL UNIQUE,         -- e.g. RX-20260224-001
    sale_uuid   TEXT,                            -- idempotency UUID for safe retry
    sale_data   TEXT    NOT NULL,                -- JSON: { items, total, method, customer, ... }
    pharmacy_id INTEGER,
    device_id   TEXT,
    version     INTEGER NOT NULL DEFAULT 1,
    created_at  INTEGER NOT NULL,                -- epoch milliseconds (POS local time)
    updated_at  INTEGER,
    deleted_at  INTEGER,
    sync_status TEXT    NOT NULL DEFAULT 'pending',
    synced      INTEGER NOT NULL DEFAULT 0       -- 0 = pending, 1 = accepted by Command Center
);

CREATE INDEX IF NOT EXISTS idx_osq_synced     ON offline_sale_queue (synced);
CREATE INDEX IF NOT EXISTS idx_osq_sync_status ON offline_sale_queue (sync_status);
CREATE INDEX IF NOT EXISTS idx_osq_created_at ON offline_sale_queue (created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_osq_sale_uuid_unique ON offline_sale_queue (sale_uuid) WHERE sale_uuid IS NOT NULL;


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: inventory_movement_queue
--  Append-only local movement events used to synchronize inventory reliably.
--  quantity_delta uses signed integers (+in, -out); price is sent in minor units.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory_movement_queue (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    movement_uuid    TEXT    NOT NULL UNIQUE,
    pharmacy_id      INTEGER,
    device_id        TEXT    NOT NULL,
    version          INTEGER NOT NULL DEFAULT 1,
    barcode          TEXT    NOT NULL,
    movement_type    TEXT    NOT NULL,
    quantity_delta   INTEGER NOT NULL,
    unit_price_minor INTEGER,
    currency_code    TEXT    NOT NULL DEFAULT 'USD',
    reference_type   TEXT    NOT NULL DEFAULT '',
    reference_id     TEXT    NOT NULL DEFAULT '',
    metadata         TEXT    NOT NULL DEFAULT '{}',
    happened_at      INTEGER NOT NULL,
    updated_at       INTEGER NOT NULL,
    deleted_at       INTEGER,
    sync_status      TEXT    NOT NULL DEFAULT 'pending',
    synced_at        INTEGER
);

CREATE INDEX IF NOT EXISTS idx_imq_sync_status        ON inventory_movement_queue (sync_status);
CREATE INDEX IF NOT EXISTS idx_imq_barcode_happened_at ON inventory_movement_queue (barcode, happened_at);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: sync_outbox
--  Local queue ledger for outbound sync events and retry state.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sync_outbox (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    event_uuid  TEXT    NOT NULL UNIQUE,
    stream      TEXT    NOT NULL,
    payload     TEXT    NOT NULL,
    sync_status TEXT    NOT NULL DEFAULT 'pending',
    retry_count INTEGER NOT NULL DEFAULT 0,
    last_error  TEXT,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER
);

CREATE INDEX IF NOT EXISTS idx_sync_outbox_status ON sync_outbox (sync_status, created_at);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: sync_checkpoint
--  Tracks last acknowledged checkpoints for `pos_to_server` and `server_to_pos`.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sync_checkpoint (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    stream           TEXT    NOT NULL UNIQUE,
    checkpoint_token TEXT    NOT NULL,
    checkpoint_time  INTEGER NOT NULL,
    updated_at       INTEGER NOT NULL
);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: purchases
--  Purchase order headers — one row per stock receipt from a supplier.
--  receipt_id format: PO-YYYYMMDD-NNNN (generated at POS).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS purchases (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    purchase_uuid  TEXT,
    receipt_id     TEXT    NOT NULL UNIQUE,      -- e.g. PO-20260224-0012
    supplier_name  TEXT    NOT NULL DEFAULT '',
    invoice_number TEXT    NOT NULL DEFAULT '',
    pharmacy_id    INTEGER,
    device_id      TEXT,
    version        INTEGER NOT NULL DEFAULT 1,
    created_at     INTEGER NOT NULL              -- epoch milliseconds
    ,updated_at    INTEGER
    ,deleted_at    INTEGER
    ,sync_status   TEXT    NOT NULL DEFAULT 'pending'
);

CREATE INDEX IF NOT EXISTS idx_purchases_created_at ON purchases (created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_purchases_uuid_unique ON purchases (purchase_uuid) WHERE purchase_uuid IS NOT NULL;


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: purchase_items
--  Line items for each purchase order.
--  FK: purchase_id → purchases(id) — cascades on delete.
--  barcode is a soft reference to inventory(barcode); stock is auto-incremented
--  in inventory when the purchase is recorded (see recordPurchase() in Dart).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS purchase_items (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    line_uuid   TEXT,
    purchase_id INTEGER NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
    barcode     TEXT    NOT NULL,                -- soft FK → inventory(barcode)
    name        TEXT    NOT NULL,
    dosage      TEXT    NOT NULL DEFAULT '',
    qty         INTEGER NOT NULL CHECK (qty > 0),
    cost_price  REAL    NOT NULL DEFAULT 0.0,    -- supplier cost per unit (USD)
    updated_at  INTEGER,
    deleted_at  INTEGER
);

CREATE INDEX IF NOT EXISTS idx_pi_purchase_id ON purchase_items (purchase_id);
CREATE INDEX IF NOT EXISTS idx_pi_barcode     ON purchase_items (barcode);
CREATE UNIQUE INDEX IF NOT EXISTS idx_purchase_items_line_uuid_unique ON purchase_items (line_uuid) WHERE line_uuid IS NOT NULL;


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: sale_items_cache (compatibility adapter for canonical sale_items)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sale_items_cache (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    line_uuid        TEXT    NOT NULL UNIQUE,
    sale_uuid        TEXT    NOT NULL,
    receipt_id       TEXT    NOT NULL,
    barcode          TEXT    NOT NULL,
    product_name     TEXT    NOT NULL,
    dosage           TEXT    NOT NULL DEFAULT '',
    qty              INTEGER NOT NULL,
    unit_price_minor INTEGER NOT NULL,
    line_total_minor INTEGER NOT NULL,
    batch_number     TEXT,
    version          INTEGER NOT NULL DEFAULT 1,
    updated_at       INTEGER NOT NULL,
    deleted_at       INTEGER
);

CREATE INDEX IF NOT EXISTS idx_sale_items_sale_uuid ON sale_items_cache (sale_uuid);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: product_batches
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS product_batches (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_uuid       TEXT    NOT NULL UNIQUE,
    barcode          TEXT    NOT NULL,
    batch_number     TEXT    NOT NULL,
    expiry           TEXT    NOT NULL DEFAULT '',
    qty_on_hand      INTEGER NOT NULL DEFAULT 0,
    unit_cost_minor  INTEGER,
    unit_price_minor INTEGER,
    currency_code    TEXT    NOT NULL DEFAULT 'USD',
    supplier_name    TEXT,
    reference_id     TEXT,
    version          INTEGER NOT NULL DEFAULT 1,
    updated_at       INTEGER NOT NULL,
    deleted_at       INTEGER
);

CREATE INDEX IF NOT EXISTS idx_product_batches_barcode ON product_batches (barcode);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: returns
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS returns (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    return_uuid      TEXT    NOT NULL UNIQUE,
    barcode          TEXT    NOT NULL,
    return_type      TEXT    NOT NULL,
    qty              INTEGER NOT NULL,
    unit_price_minor INTEGER,
    reason           TEXT,
    reference_id     TEXT,
    version          INTEGER NOT NULL DEFAULT 1,
    updated_at       INTEGER NOT NULL,
    deleted_at       INTEGER,
    sync_status      TEXT    NOT NULL DEFAULT 'pending'
);

CREATE INDEX IF NOT EXISTS idx_returns_sync_status ON returns (sync_status, updated_at);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: stock_adjustments
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS stock_adjustments (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    adjustment_uuid  TEXT    NOT NULL UNIQUE,
    barcode          TEXT    NOT NULL,
    quantity_delta   INTEGER NOT NULL,
    reason           TEXT    NOT NULL DEFAULT '',
    reference_id     TEXT,
    version          INTEGER NOT NULL DEFAULT 1,
    updated_at       INTEGER NOT NULL,
    deleted_at       INTEGER,
    sync_status      TEXT    NOT NULL DEFAULT 'pending'
);

CREATE INDEX IF NOT EXISTS idx_stock_adjustments_sync_status ON stock_adjustments (sync_status, updated_at);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: prices
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS prices (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    price_uuid           TEXT    NOT NULL UNIQUE,
    barcode              TEXT    NOT NULL UNIQUE,
    regulated_price_minor INTEGER,
    local_price_minor    INTEGER,
    currency_code        TEXT    NOT NULL DEFAULT 'USD',
    source               TEXT    NOT NULL DEFAULT 'server',
    version              INTEGER NOT NULL DEFAULT 1,
    updated_at           INTEGER NOT NULL,
    deleted_at           INTEGER
);

CREATE INDEX IF NOT EXISTS idx_prices_barcode ON prices (barcode);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: price_history
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS price_history (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    history_uuid         TEXT    NOT NULL UNIQUE,
    barcode              TEXT    NOT NULL,
    previous_price_minor INTEGER,
    new_price_minor      INTEGER,
    currency_code        TEXT    NOT NULL DEFAULT 'USD',
    source               TEXT    NOT NULL,
    changed_by           TEXT,
    changed_at           INTEGER NOT NULL,
    metadata             TEXT    NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_price_history_barcode_changed_at ON price_history (barcode, changed_at);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE: compliance_alerts
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS compliance_alerts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    alert_uuid      TEXT    NOT NULL UNIQUE,
    alert_type      TEXT    NOT NULL,
    severity        TEXT    NOT NULL DEFAULT 'medium',
    title           TEXT    NOT NULL,
    details         TEXT    NOT NULL DEFAULT '{}',
    status          TEXT    NOT NULL DEFAULT 'open',
    created_at      INTEGER NOT NULL,
    acknowledged_at INTEGER,
    resolved_at     INTEGER,
    updated_at      INTEGER NOT NULL,
    deleted_at      INTEGER
);

CREATE INDEX IF NOT EXISTS idx_compliance_alerts_status_created_at ON compliance_alerts (status, created_at);


-- ─────────────────────────────────────────────────────────────────────────────
--  COMPATIBILITY VIEWS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE VIEW IF NOT EXISTS sales AS
SELECT sale_uuid, receipt_id, sale_data, created_at, updated_at, deleted_at, version, sync_status
FROM offline_sale_queue;

CREATE VIEW IF NOT EXISTS sale_items AS
SELECT line_uuid, sale_uuid, receipt_id, barcode, product_name, dosage, qty, unit_price_minor, line_total_minor, batch_number, version, updated_at, deleted_at
FROM sale_items_cache;

CREATE VIEW IF NOT EXISTS medicines AS
SELECT product_uuid AS medicine_uuid, barcode, name AS trade_name, dosage, category, moph_ceiling, is_blocked, version, updated_at, deleted_at
FROM inventory;


-- ─────────────────────────────────────────────────────────────────────────────
--  SEED DATA  (matches _seedInventory in inventory_database.dart)
--  Remove or modify before deploying to a new pharmacy terminal.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT OR IGNORE INTO inventory (barcode, name, dosage, category, stock, expiry, price, moph_ceiling, batch_number) VALUES
('6289201012345', 'Amoxil (Amoxicillin)',               '500 mg',     'Antibiotic',         120, 'Dec 2026', 18.00, 14.50, 'AMX-2025-01'),
('6289201012350', 'Brufen (Ibuprofen)',                  '400 mg',     'Anti-inflammatory',   85, 'Mar 2027',  8.50,  7.00, 'IBU-2025-03'),
('6289201012346', 'Glucophage (Metformin HCl)',          '850 mg',     'Antidiabetic',        60, 'Sep 2026',  6.00,  5.50, 'MET-2025-07'),
('6289201012349', 'Losec (Omeprazole)',                  '20 mg',      'Antacid / PPI',        5, 'Nov 2026', 11.00, 10.00, 'OMP-2025-02'),
('6289201012351', 'Zyrtec (Cetirizine HCl)',             '10 mg',      'Antihistamine',      140, 'May 2027',  7.00,  6.00, 'CET-2025-04'),
('6289201012347', 'Zestril (Lisinopril)',                '10 mg',      'Antihypertensive',   200, 'Jun 2026',  8.00,  7.50, 'LIS-2025-06'),
('6289201012348', 'Lipitor (Atorvastatin)',              '20 mg',      'Lipid-Lowering',       9, 'Jan 2027', 22.00, 18.00, 'ATV-2025-09'),
('6289201012353', 'Zithromax (Azithromycin)',            '500 mg',     'Antibiotic',          42, 'Aug 2026', 26.00, 22.00, 'AZI-2025-11'),
('6009705182174', 'Augmentin (Amoxicillin/Clavulanate)', '875/125 mg', 'Antibiotic',          55, 'Oct 2026', 32.00, 28.00, 'AUG-2025-05'),
('6289201012357', 'Panadol (Paracetamol)',               '500 mg',     'Analgesic',          310, 'Feb 2028',  3.50,  3.50, 'PAR-2025-12'),
('6289201012359', 'Cozaar (Losartan Potassium)',         '50 mg',      'Antihypertensive',    75, 'Apr 2027', 14.00, 13.00, 'LOS-2025-08'),
('6009705182204', 'Crestor (Rosuvastatin)',              '10 mg',      'Lipid-Lowering',      38, 'Jul 2027', 19.00, 18.00, 'ROS-2025-10'),
('6289201012361', 'Ventolin (Salbutamol)',               '100 mcg/puff','Bronchodilator',     22, 'Mar 2027', 12.00, 11.50, 'SAL-2025-03'),
('6009705182228', 'Xarelto (Rivaroxaban)',               '20 mg',      'Anticoagulant',       17, 'Dec 2026', 88.00, 85.00, 'RIV-2025-01'),
('6009705182235', 'Concor (Bisoprolol Fumarate)',        '5 mg',       'Beta-Blocker',        48, 'Sep 2027',  9.50,  9.00, 'BIS-2025-06');
