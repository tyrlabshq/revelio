-- REV-12: FDA recall feed + push-notification feature
--
-- Stores FDA recalls ingested from the openFDA enforcement endpoints
-- (food / drug / cosmetic). When a recall's UPC list overlaps a user's
-- scans.barcode or pantry_items.barcode, we insert a recall_notification
-- row and drop a push payload in push_outbox.

CREATE TABLE IF NOT EXISTS recalls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recall_number VARCHAR(64) UNIQUE NOT NULL,
  classification VARCHAR(16) NOT NULL,           -- "Class I" | "Class II" | "Class III"
  product_description TEXT NOT NULL,
  reason_for_recall TEXT NOT NULL,
  recalling_firm VARCHAR(255),
  product_type VARCHAR(16) NOT NULL,             -- "food" | "drug" | "device" | "cosmetic"
  upc_codes TEXT[],                              -- parsed from openFDA code_info
  recall_initiation_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_recalls_upc ON recalls USING GIN (upc_codes);
CREATE INDEX IF NOT EXISTS idx_recalls_created ON recalls(created_at DESC);

CREATE TABLE IF NOT EXISTS recall_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  recall_id UUID NOT NULL REFERENCES recalls(id) ON DELETE CASCADE,
  barcode VARCHAR(20) NOT NULL,
  notified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  opened_at TIMESTAMPTZ,
  UNIQUE (user_id, recall_id, barcode)
);
CREATE INDEX IF NOT EXISTS idx_recall_notif_user ON recall_notifications(user_id, notified_at DESC);

CREATE TABLE IF NOT EXISTS device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  platform VARCHAR(8) NOT NULL,                  -- "ios" | "android"
  token TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, platform, token)
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);

-- Durable outbox for push payloads. Real APNs/FCM workers drain this table
-- (see backend/src/services/push.ts). Keeping it in Postgres avoids making
-- APNs/FCM creds a hard dependency for CI and local dev.
CREATE TABLE IF NOT EXISTS push_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  platform VARCHAR(8) NOT NULL,                  -- "ios" | "android"
  token TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ,
  error TEXT
);
CREATE INDEX IF NOT EXISTS idx_push_outbox_pending ON push_outbox(created_at) WHERE sent_at IS NULL;
