import { Pool } from 'pg';
import dotenv from 'dotenv';
dotenv.config();
export const db = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  idleTimeoutMillis: 30000
});

// ─── Schema bootstrap ─────────────────────────────────────────────────────────

export async function ensureAlternativesTable(): Promise<void> {
  await db.query(`
    CREATE TABLE IF NOT EXISTS alternatives (
      id SERIAL PRIMARY KEY,
      barcode VARCHAR NOT NULL,
      alternative_barcode VARCHAR NOT NULL,
      name VARCHAR,
      brand VARCHAR,
      score INTEGER DEFAULT 85,
      grade VARCHAR DEFAULT 'A',
      image_url TEXT,
      affiliate_url TEXT,
      affiliate_network TEXT,
      price_cents INTEGER,
      verified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_alternatives_barcode ON alternatives(barcode)
  `);
}
