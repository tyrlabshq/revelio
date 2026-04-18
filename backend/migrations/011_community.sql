-- ─── 011_community.sql ───────────────────────────────────────────────────────
-- Track 3.7: Community layer — lightweight reviews + "Hall of Shame" votes.
-- Writes are gated behind phone-verified accounts (see requireAuth middleware).

CREATE TABLE IF NOT EXISTS product_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  barcode VARCHAR(20) NOT NULL,
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, barcode)
);
CREATE INDEX IF NOT EXISTS idx_reviews_barcode ON product_reviews(barcode);

CREATE TABLE IF NOT EXISTS hall_of_shame_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  barcode VARCHAR(20) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, barcode)
);
CREATE INDEX IF NOT EXISTS idx_hos_barcode ON hall_of_shame_votes(barcode);
