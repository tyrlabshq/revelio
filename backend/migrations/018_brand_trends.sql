-- REV-18: Weekly brand trend snapshots.
--
-- Persists one row per (brand_slug, week_start) so the iOS deep-dive can
-- render "this brand's score moved from 52 → 61 over 12 weeks" without
-- re-aggregating the scans table on every request. The daily job at
-- backend/src/jobs/brandTrends.ts writes into this table once per UTC day;
-- ON CONFLICT upserts keep the week's row fresh as more scans land.

CREATE TABLE IF NOT EXISTS brand_trends (
  brand_slug TEXT NOT NULL,
  week_start DATE NOT NULL,
  avg_score NUMERIC(5,2) NOT NULL,
  scan_count INTEGER NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (brand_slug, week_start)
);

CREATE INDEX IF NOT EXISTS idx_brand_trends_slug_week
  ON brand_trends (brand_slug, week_start DESC);
