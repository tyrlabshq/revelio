-- REV-11: Add category + image_url to scans for history/insights
ALTER TABLE scans ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'food';
ALTER TABLE scans ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE scans ADD COLUMN IF NOT EXISTS brand TEXT;

CREATE INDEX IF NOT EXISTS idx_scans_user_category ON scans(user_id, category);
CREATE INDEX IF NOT EXISTS idx_scans_user_grade    ON scans(user_id, grade);
