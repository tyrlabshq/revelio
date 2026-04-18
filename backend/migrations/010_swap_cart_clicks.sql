-- REV-T3.2: Swap Cart affiliate attribution analytics
CREATE TABLE IF NOT EXISTS swap_cart_clicks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  source_barcode VARCHAR(20) NOT NULL,
  dupe_barcode VARCHAR(20),
  affiliate_network VARCHAR(32) NOT NULL,
  clicked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_swap_clicks_user ON swap_cart_clicks(user_id);
