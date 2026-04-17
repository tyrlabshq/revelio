-- REV-SEC: indexes, constraints, and tables needed for the security hardening pass.

-- Scans: add a plain user_id index (existing indexes are composite (user_id, category/grade/scanned_at)).
-- Useful for general per-user lookups and the DELETE authorization check.
CREATE INDEX IF NOT EXISTS idx_scans_user_id ON scans(user_id);

-- referral_attributions: one attribution per referred user. Makes the
-- check-then-insert in POST /referrals/apply race-free. Using CREATE UNIQUE
-- INDEX IF NOT EXISTS so the migration is idempotent; if pre-existing
-- duplicates are present this will fail and must be deduplicated first.
CREATE UNIQUE INDEX IF NOT EXISTS referral_attributions_referred_user_id_unique
  ON referral_attributions (referred_user_id);

-- OTP brute-force / throttling table used by /auth/request-otp and /auth/verify-otp.
CREATE TABLE IF NOT EXISTS otp_attempts (
  phone         VARCHAR(20) PRIMARY KEY,
  request_count INTEGER DEFAULT 0,
  verify_count  INTEGER DEFAULT 0,
  window_start  TIMESTAMPTZ DEFAULT NOW()
);

-- AI usage per-user per-day (moved out of in-memory Map so it survives restarts
-- and works across replicas).
CREATE TABLE IF NOT EXISTS ai_usage (
  user_id UUID NOT NULL,
  date    DATE NOT NULL,
  count   INTEGER DEFAULT 0,
  PRIMARY KEY (user_id, date)
);
