-- REV-14: Creator referral program
-- referral_codes assumed already present from REV-02

CREATE TABLE IF NOT EXISTS referral_codes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  code TEXT UNIQUE NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'suspended')),
  follower_count INTEGER,
  platform TEXT,
  social_handle TEXT,
  applied_at TIMESTAMPTZ DEFAULT NOW(),
  approved_at TIMESTAMPTZ,
  total_earnings_cents BIGINT DEFAULT 0,
  pending_payout_cents BIGINT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS referral_attributions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  referral_code TEXT NOT NULL REFERENCES referral_codes(code) ON DELETE RESTRICT,
  referred_user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  attributed_at TIMESTAMPTZ DEFAULT NOW(),
  subscription_start TIMESTAMPTZ,
  lifetime_revenue_cents BIGINT DEFAULT 0,
  is_active_subscriber BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS referral_earnings_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  referral_code TEXT NOT NULL,
  referred_user_id UUID NOT NULL,
  event_type TEXT NOT NULL, -- 'subscription_renewed', 'initial_purchase'
  gross_cents BIGINT NOT NULL,
  commission_cents BIGINT NOT NULL,
  recorded_at TIMESTAMPTZ DEFAULT NOW(),
  revenue_cat_event_id TEXT UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_referral_attributions_code ON referral_attributions(referral_code);
CREATE INDEX IF NOT EXISTS idx_referral_attributions_user ON referral_attributions(referred_user_id);
CREATE INDEX IF NOT EXISTS idx_referral_codes_user ON referral_codes(user_id);
CREATE INDEX IF NOT EXISTS idx_referral_codes_status ON referral_codes(status);
