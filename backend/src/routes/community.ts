// ─── backend/src/routes/community.ts ─────────────────────────────────────────
// Track 3.7 — community layer.
//  - POST   /community/reviews                     (auth) upsert review
//  - GET    /community/reviews/:barcode            (public) list reviews
//  - POST   /community/hall-of-shame/:barcode      (auth) upsert vote
//  - GET    /community/hall-of-shame               (public) most voted-against
//
// Writes require a phone-verified account (requireAuth). Reads are public so
// the UI can show community signal to anonymous / pre-signup users.

import { Router } from 'express';
import { db } from '../db';
import { requireAuth, AuthRequest } from './auth';

export const communityRouter = Router();

// ─── Helpers ─────────────────────────────────────────────────────────────────

const BARCODE_RE = /^[0-9]{6,20}$/;
function validBarcode(bc: string | undefined): bc is string {
  return !!bc && BARCODE_RE.test(bc);
}

async function ensureCommunityTables(): Promise<void> {
  // Defensive: mirrors migrations/011_community.sql so the router works even
  // if the migration has not been run yet (e.g., dev / ephemeral test DB).
  await db.query(`
    CREATE TABLE IF NOT EXISTS product_reviews (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
      barcode VARCHAR(20) NOT NULL,
      rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
      body TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE(user_id, barcode)
    )
  `);
  await db.query(`CREATE INDEX IF NOT EXISTS idx_reviews_barcode ON product_reviews(barcode)`);
  await db.query(`
    CREATE TABLE IF NOT EXISTS hall_of_shame_votes (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
      barcode VARCHAR(20) NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE(user_id, barcode)
    )
  `);
  await db.query(`CREATE INDEX IF NOT EXISTS idx_hos_barcode ON hall_of_shame_votes(barcode)`);
}

ensureCommunityTables().catch(err => console.error('[community] table setup error:', err));

// ─── POST /community/reviews — upsert review for current user ────────────────

communityRouter.post('/reviews', requireAuth, async (req: AuthRequest, res) => {
  const userId = req.user!.userId;
  const { barcode, rating, body } = req.body as { barcode?: string; rating?: number; body?: string };

  if (!validBarcode(barcode)) {
    return res.status(400).json({ error: 'Valid barcode required' });
  }
  const ratingInt = Number(rating);
  if (!Number.isInteger(ratingInt) || ratingInt < 1 || ratingInt > 5) {
    return res.status(400).json({ error: 'rating must be an integer between 1 and 5' });
  }
  const trimmedBody = typeof body === 'string' ? body.slice(0, 2000).trim() : null;

  try {
    const result = await db.query(
      `INSERT INTO product_reviews (user_id, barcode, rating, body, created_at)
       VALUES ($1, $2, $3, $4, NOW())
       ON CONFLICT (user_id, barcode)
       DO UPDATE SET rating = EXCLUDED.rating, body = EXCLUDED.body, created_at = NOW()
       RETURNING id, barcode, rating, body, created_at`,
      [userId, barcode, ratingInt, trimmedBody]
    );
    const row = result.rows[0];
    res.status(201).json({
      review: {
        id: row.id,
        barcode: row.barcode,
        rating: row.rating,
        body: row.body,
        createdAt: row.created_at,
      },
    });
  } catch (err) {
    console.error('POST /community/reviews error:', err);
    res.status(500).json({ error: 'Failed to save review' });
  }
});

// ─── GET /community/reviews/:barcode — public, anonymized ────────────────────

communityRouter.get('/reviews/:barcode', async (req, res) => {
  const { barcode } = req.params;
  if (!validBarcode(barcode)) {
    return res.status(400).json({ error: 'Valid barcode required' });
  }
  const limit = Math.min(100, Math.max(1, parseInt(String(req.query.limit ?? '50'), 10) || 50));

  try {
    const [aggRow, listRow] = await Promise.all([
      db.query(
        `SELECT AVG(rating)::numeric(3,2) AS avg, COUNT(*)::int AS count
         FROM product_reviews WHERE barcode = $1`,
        [barcode]
      ),
      db.query(
        `SELECT rating, body, created_at
         FROM product_reviews
         WHERE barcode = $1
         ORDER BY created_at DESC
         LIMIT $2`,
        [barcode, limit]
      ),
    ]);

    const avg = aggRow.rows[0]?.avg ? parseFloat(aggRow.rows[0].avg) : 0;
    const count = aggRow.rows[0]?.count ?? 0;

    res.json({
      barcode,
      avg,
      count,
      reviews: listRow.rows.map(r => ({
        rating: r.rating,
        body: r.body,
        createdAt: r.created_at,
      })),
    });
  } catch (err) {
    console.error('GET /community/reviews/:barcode error:', err);
    res.status(500).json({ error: 'Failed to fetch reviews' });
  }
});

// ─── POST /community/hall-of-shame/:barcode — upsert vote ────────────────────

communityRouter.post('/hall-of-shame/:barcode', requireAuth, async (req: AuthRequest, res) => {
  const userId = req.user!.userId;
  const { barcode } = req.params;
  if (!validBarcode(barcode)) {
    return res.status(400).json({ error: 'Valid barcode required' });
  }
  try {
    const result = await db.query(
      `INSERT INTO hall_of_shame_votes (user_id, barcode, created_at)
       VALUES ($1, $2, NOW())
       ON CONFLICT (user_id, barcode)
       DO UPDATE SET created_at = NOW()
       RETURNING id, barcode, created_at`,
      [userId, barcode]
    );
    res.status(201).json({ vote: result.rows[0] });
  } catch (err) {
    console.error('POST /community/hall-of-shame/:barcode error:', err);
    res.status(500).json({ error: 'Failed to record vote' });
  }
});

// ─── GET /community/hall-of-shame — leaderboard, last 30 days ────────────────

communityRouter.get('/hall-of-shame', async (req, res) => {
  const limit = Math.min(100, Math.max(1, parseInt(String(req.query.limit ?? '20'), 10) || 20));

  try {
    // Join against the `products` cache for name/brand/image. `scans` fallback
    // is attempted via a LATERAL query for grade — products table may not
    // carry a score column, so we take the most recent scan's grade instead.
    const result = await db.query(
      `SELECT v.barcode,
              COUNT(*)::int AS votes,
              p.name AS product_name,
              p.brand,
              p.image_url,
              p.category,
              (
                SELECT s.grade FROM scans s
                WHERE s.barcode = v.barcode
                ORDER BY s.scanned_at DESC
                LIMIT 1
              ) AS grade,
              (
                SELECT s.score FROM scans s
                WHERE s.barcode = v.barcode
                ORDER BY s.scanned_at DESC
                LIMIT 1
              ) AS score
       FROM hall_of_shame_votes v
       LEFT JOIN products p ON p.barcode = v.barcode
       WHERE v.created_at >= NOW() - INTERVAL '30 days'
       GROUP BY v.barcode, p.name, p.brand, p.image_url, p.category
       ORDER BY votes DESC, v.barcode ASC
       LIMIT $1`,
      [limit]
    );

    res.json({
      window: '30d',
      entries: result.rows.map(r => ({
        barcode: r.barcode,
        votes: r.votes,
        productName: r.product_name ?? 'Unknown product',
        brand: r.brand ?? 'Unknown',
        imageUrl: r.image_url ?? null,
        category: r.category ?? null,
        grade: r.grade ?? null,
        score: r.score ?? null,
      })),
    });
  } catch (err) {
    console.error('GET /community/hall-of-shame error:', err);
    res.status(500).json({ error: 'Failed to load Hall of Shame' });
  }
});
