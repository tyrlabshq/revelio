-- 007_scoring_extras.sql
-- Adds Nutri-Score, Nova group, and Eco-Score columns to the products cache.
-- Each column is nullable because the OFF/OBF/OPF APIs don't always provide
-- them (OPF especially). The scoring service treats missing values as "unknown"
-- and falls back to the Revelio ingredient-based score.

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS nutri_score_grade VARCHAR(2),
  ADD COLUMN IF NOT EXISTS nutri_score_points INTEGER,
  ADD COLUMN IF NOT EXISTS nova_group SMALLINT,
  ADD COLUMN IF NOT EXISTS ecoscore_grade VARCHAR(2),
  ADD COLUMN IF NOT EXISTS ecoscore_score INTEGER;

-- Useful for "show me all A-graded products" queries later.
CREATE INDEX IF NOT EXISTS idx_products_nutri_grade ON products(nutri_score_grade);
CREATE INDEX IF NOT EXISTS idx_products_nova_group  ON products(nova_group);
CREATE INDEX IF NOT EXISTS idx_products_ecoscore    ON products(ecoscore_grade);
