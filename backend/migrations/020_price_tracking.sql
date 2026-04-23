-- REV-20: Price-drop alert system.
--
-- price_history: time series of affiliate-network prices per barcode. We
-- append-only insert a row every time the price-check job observes a price.
-- Reads happen via the (barcode, recorded_at DESC) index for "latest price"
-- lookups.
--
-- price_alerts: per-user subscription to a barcode. At least one of
-- threshold_cents (absolute target) / threshold_pct (percent drop vs. last
-- seen price) must be set by the route handler; the schema allows both NULL
-- so a future "any drop" mode can reuse the table without a migration.
-- `last_notified_at` backs the 24h dedup in priceCheck.ts so a single
-- multi-day slide doesn't spam the user.

CREATE TABLE IF NOT EXISTS price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barcode VARCHAR(20) NOT NULL,
  affiliate_network VARCHAR(32) NOT NULL,
  price_cents INTEGER NOT NULL,
  currency VARCHAR(8) NOT NULL DEFAULT 'usd',
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_price_history_barcode ON price_history(barcode, recorded_at DESC);

CREATE TABLE IF NOT EXISTS price_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  barcode VARCHAR(20) NOT NULL,
  threshold_cents INTEGER,
  threshold_pct INTEGER,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_notified_at TIMESTAMPTZ,
  UNIQUE (user_id, barcode)
);
