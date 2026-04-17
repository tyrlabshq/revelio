-- REV-T3.4: Enable pgvector + product description embeddings for Dupe Finder
-- (Migrations 006/007/008 are owned by other agents; this is 009.)

CREATE EXTENSION IF NOT EXISTS vector;

-- text-embedding-3-small returns 1536-dim vectors.
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS description_embedding vector(1536);

-- IVFFLAT index for approximate nearest-neighbor (cosine distance).
-- Lists = 100 is a reasonable default for <1M products; tune later.
CREATE INDEX IF NOT EXISTS idx_products_description_embedding
  ON products
  USING ivfflat (description_embedding vector_cosine_ops)
  WITH (lists = 100);

-- Helper index: category filter feeds the ANN query path.
CREATE INDEX IF NOT EXISTS idx_products_category
  ON products(category);
