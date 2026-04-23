-- REV-21: Admin role + job run audit log.
--
-- is_admin flips an operator-only bit on user_profiles. The admin dashboard
-- and moderation endpoints gate on this. We intentionally do NOT overload
-- the `tier` column (which is product-plan state: free/pro/family) — mixing
-- billing state with authorization state has a habit of breaking in subtle
-- ways when someone downgrades a paid plan.
--
-- job_runs is a lightweight audit trail for the in-process scheduler. Each
-- invocation inserts a row on start and updates finished_at + status on
-- completion, so /status can answer "when did this job last finish?" without
-- us reaching into a real observability stack. Indexed on (name, started_at
-- DESC) so the latest-per-job lookup is cheap.

ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_user_profiles_admin ON user_profiles(is_admin) WHERE is_admin = TRUE;

CREATE TABLE IF NOT EXISTS job_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_name VARCHAR(64) NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMPTZ,
  status VARCHAR(16) NOT NULL DEFAULT 'running',
  error TEXT
);
CREATE INDEX IF NOT EXISTS idx_job_runs_name_started ON job_runs(job_name, started_at DESC);
