-- MedTrack360 — user auth + per-user data schema
-- Idempotent: safe to run against an existing Neon database.

-- Enable UUID generator (provided by Neon by default).
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─────────────────────────────────────────────────────────────
-- users
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  user_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name     VARCHAR(100) NOT NULL,
  email         VARCHAR(150) NOT NULL UNIQUE,
  phone         VARCHAR(20),
  password_hash VARCHAR(255) NOT NULL,
  is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- ─────────────────────────────────────────────────────────────
-- watchlist (per-user)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS watchlist (
  watchlist_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  medication_id       UUID NOT NULL REFERENCES moph_registry(medication_id) ON DELETE CASCADE,
  notify_on_available BOOLEAN  NOT NULL DEFAULT TRUE,
  added_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(user_id, medication_id)
);

CREATE INDEX IF NOT EXISTS idx_watchlist_user ON watchlist(user_id);
CREATE INDEX IF NOT EXISTS idx_watchlist_medication ON watchlist(medication_id);

-- Friendly view: watchlist rows joined with the user who saved them and the
-- medicine they're watching. Show this in the Neon console instead of the
-- raw watchlist table when you want human-readable names + emails.
CREATE OR REPLACE VIEW watchlist_detailed AS
SELECT
  w.watchlist_id,
  u.full_name        AS user_name,
  u.email            AS user_email,
  m.trade_name       AS medicine_name,
  m.generic_name     AS medicine_generic,
  w.notify_on_available,
  w.added_at,
  w.user_id,
  w.medication_id
FROM watchlist w
JOIN users         u ON u.user_id       = w.user_id
JOIN moph_registry m ON m.medication_id = w.medication_id
ORDER BY w.added_at DESC;

-- ─────────────────────────────────────────────────────────────
-- pharmacy_stock (per-pharmacy inventory of medications)
-- ─────────────────────────────────────────────────────────────
-- pharmacies.id is INTEGER, moph_registry.medication_id is UUID.
CREATE TABLE IF NOT EXISTS pharmacy_stock (
  stock_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id    INTEGER NOT NULL REFERENCES pharmacies(id)                ON DELETE CASCADE,
  medication_id  UUID    NOT NULL REFERENCES moph_registry(medication_id)  ON DELETE CASCADE,
  in_stock       BOOLEAN NOT NULL DEFAULT FALSE,
  current_price  NUMERIC(10,2) NOT NULL,
  last_updated   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(pharmacy_id, medication_id)
);

CREATE INDEX IF NOT EXISTS idx_pharmacy_stock_pharmacy   ON pharmacy_stock(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_pharmacy_stock_medication ON pharmacy_stock(medication_id);
CREATE INDEX IF NOT EXISTS idx_pharmacy_stock_in_stock   ON pharmacy_stock(in_stock);

-- Readable view for the Neon console.
CREATE OR REPLACE VIEW pharmacy_stock_detailed AS
SELECT
  ps.stock_id,
  p.name               AS pharmacy_name,
  p.region             AS pharmacy_region,
  m.trade_name         AS medicine_name,
  m.generic_name       AS medicine_generic,
  ps.in_stock,
  ps.current_price,
  m.moph_ceiling       AS ministry_locked_price,
  (ps.current_price - m.moph_ceiling) AS price_delta,
  ps.last_updated,
  ps.pharmacy_id,
  ps.medication_id
FROM pharmacy_stock ps
JOIN pharmacies     p ON p.id            = ps.pharmacy_id
JOIN moph_registry  m ON m.medication_id = ps.medication_id
ORDER BY p.name, m.trade_name;

-- ─────────────────────────────────────────────────────────────
-- reviews (per-user, per-pharmacy)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS reviews (
  review_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pharmacy_id            UUID NOT NULL REFERENCES pharmacies(pharmacy_id) ON DELETE CASCADE,
  user_id                UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  stock_accuracy_rating  DECIMAL(2,1) NOT NULL CHECK (stock_accuracy_rating BETWEEN 0.0 AND 5.0),
  service_quality_rating DECIMAL(2,1) NOT NULL CHECK (service_quality_rating BETWEEN 0.0 AND 5.0),
  comment                TEXT,
  has_discrepancy_report BOOLEAN NOT NULL DEFAULT FALSE,
  discrepancy_details    TEXT,
  created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_reviews_pharmacy ON reviews(pharmacy_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user ON reviews(user_id);

-- ─────────────────────────────────────────────────────────────
-- search_history (per-user)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS search_history (
  history_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  query        VARCHAR(200) NOT NULL,
  searched_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_history_user ON search_history(user_id);
CREATE INDEX IF NOT EXISTS idx_history_searched_at ON search_history(searched_at DESC);

-- ─────────────────────────────────────────────────────────────
-- Health news (Ministry of Health announcements). Inserts into
-- this table fan out to every user via notifications below.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS health_news (
  news_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title         VARCHAR(200) NOT NULL,
  body          TEXT NOT NULL,
  source        VARCHAR(120) NOT NULL DEFAULT 'Lebanese Ministry of Public Health',
  url           TEXT,
  published_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_health_news_published_at ON health_news(published_at DESC);

-- ─────────────────────────────────────────────────────────────
-- Notifications: per-user feed populated by triggers when
-- watchlisted medications change price / go out of stock, or
-- when MoH publishes news.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  notification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  type            VARCHAR(30) NOT NULL,  -- 'price_change' | 'out_of_stock' | 'news'
  title           VARCHAR(200) NOT NULL,
  body            TEXT NOT NULL,
  payload         JSONB NOT NULL DEFAULT '{}'::jsonb,
  read_at         TIMESTAMP,
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON notifications(user_id) WHERE read_at IS NULL;

-- Fan-out trigger: when pharmacy_stock changes, notify every
-- user whose watchlist includes that medication.
CREATE OR REPLACE FUNCTION notify_watchlist_on_stock_change()
RETURNS TRIGGER AS $$
DECLARE
  med_name TEXT;
  pharmacy_name TEXT;
BEGIN
  -- Out-of-stock transition: in_stock flipped from true → false.
  IF (OLD.in_stock IS DISTINCT FROM NEW.in_stock) AND NEW.in_stock = false THEN
    SELECT trade_name INTO med_name FROM moph_registry WHERE medication_id = NEW.medication_id;
    SELECT name INTO pharmacy_name FROM pharmacies WHERE id = NEW.pharmacy_id;
    INSERT INTO notifications (user_id, type, title, body, payload)
    SELECT
      w.user_id,
      'out_of_stock',
      med_name || ' is out of stock',
      med_name || ' is no longer available at ' || pharmacy_name || '.',
      jsonb_build_object(
        'medication_id', NEW.medication_id,
        'pharmacy_id',   NEW.pharmacy_id,
        'pharmacy_name', pharmacy_name,
        'medication_name', med_name
      )
    FROM watchlist w
    WHERE w.medication_id = NEW.medication_id
      AND w.notify_on_available = true;
  END IF;

  -- Price change: notify on any change in current_price (rounded to cents).
  IF (OLD.current_price IS DISTINCT FROM NEW.current_price)
     AND OLD.current_price IS NOT NULL
     AND NEW.current_price IS NOT NULL
     AND ROUND(OLD.current_price::numeric, 2) <> ROUND(NEW.current_price::numeric, 2) THEN
    SELECT trade_name INTO med_name FROM moph_registry WHERE medication_id = NEW.medication_id;
    SELECT name INTO pharmacy_name FROM pharmacies WHERE id = NEW.pharmacy_id;
    INSERT INTO notifications (user_id, type, title, body, payload)
    SELECT
      w.user_id,
      'price_change',
      'Price changed: ' || med_name,
      med_name || ' at ' || pharmacy_name || ' is now $'
        || ROUND(NEW.current_price::numeric, 2)::text
        || ' (was $' || ROUND(OLD.current_price::numeric, 2)::text || ').',
      jsonb_build_object(
        'medication_id',   NEW.medication_id,
        'pharmacy_id',     NEW.pharmacy_id,
        'pharmacy_name',   pharmacy_name,
        'medication_name', med_name,
        'old_price',       ROUND(OLD.current_price::numeric, 2),
        'new_price',       ROUND(NEW.current_price::numeric, 2)
      )
    FROM watchlist w
    WHERE w.medication_id = NEW.medication_id
      AND w.notify_on_available = true;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_watchlist_on_stock_change ON pharmacy_stock;
CREATE TRIGGER trg_notify_watchlist_on_stock_change
  AFTER UPDATE ON pharmacy_stock
  FOR EACH ROW
  EXECUTE FUNCTION notify_watchlist_on_stock_change();

-- Fan-out trigger: every health_news insert becomes a notification
-- for every existing user.
CREATE OR REPLACE FUNCTION notify_users_on_health_news()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, payload)
  SELECT
    u.user_id,
    'news',
    NEW.title,
    NEW.body,
    jsonb_build_object(
      'news_id',      NEW.news_id,
      'source',       NEW.source,
      'url',          NEW.url,
      'published_at', NEW.published_at
    )
  FROM users u
  WHERE u.is_active = true;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_users_on_health_news ON health_news;
CREATE TRIGGER trg_notify_users_on_health_news
  AFTER INSERT ON health_news
  FOR EACH ROW
  EXECUTE FUNCTION notify_users_on_health_news();
