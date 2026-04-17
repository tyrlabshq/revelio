CREATE TABLE IF NOT EXISTS product_contributions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  barcode VARCHAR(20) NOT NULL,
  name VARCHAR(255),
  brand VARCHAR(255),
  category VARCHAR(50),
  image_url TEXT,
  ingredients_text TEXT,
  submitted_by UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_contributions_status ON product_contributions(status);
