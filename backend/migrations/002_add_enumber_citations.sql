-- Migration 002: Add e_number and citations fields to ingredient_flags
-- Also adds unique constraint on ingredient_name for idempotent seeding

ALTER TABLE ingredient_flags
  ADD COLUMN IF NOT EXISTS e_number TEXT,
  ADD COLUMN IF NOT EXISTS citations TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS severity_label TEXT GENERATED ALWAYS AS (
    CASE
      WHEN severity = 0 THEN 'SAFE'
      WHEN severity = 1 THEN 'SAFE'
      WHEN severity = 2 THEN 'CAUTION'
      WHEN severity = 3 THEN 'AVOID'
    END
  ) STORED;

CREATE UNIQUE INDEX IF NOT EXISTS idx_ingredient_flags_name ON ingredient_flags (LOWER(ingredient_name));
