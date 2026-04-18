-- Enable trigram fuzzy matching for receipt line → product lookup.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_products_name_trgm ON products USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_products_brand_trgm ON products USING GIN (brand gin_trgm_ops);
