import { Router } from 'express';
import { db } from '../db';

export const productRouter = Router();

// ─── GET /products/search ─────────────────────────────────────────────────────
// ?q=doritos&category=food&grade=A&limit=20
productRouter.get('/search', async (req, res) => {
  const { q = '', category, grade, limit = '20' } = req.query as Record<string, string | undefined>;
  const limitNum = Math.min(100, Math.max(1, parseInt(limit ?? '20', 10)));

  const conditions: string[] = [];
  const params: unknown[] = [];
  let p = 1;

  if (q && q.trim()) {
    conditions.push(`(product_name ILIKE $${p} OR brand ILIKE $${p} OR $${p} = ANY(ingredients))`);
    params.push(`%${q.trim()}%`);
    p++;
  }
  if (category) {
    conditions.push(`category = $${p++}`);
    params.push(category);
  }
  if (grade) {
    conditions.push(`UPPER(grade) = $${p++}`);
    params.push(grade.toUpperCase());
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  try {
    const result = await db.query(
      `SELECT id, barcode, product_name, brand, category, image_url, score, grade
       FROM products
       ${where}
       ORDER BY scan_count DESC NULLS LAST, product_name ASC
       LIMIT $${p}`,
      [...params, limitNum]
    );
    res.json({ results: result.rows });
  } catch (err) {
    console.error('[products/search]', err);
    res.status(500).json({ error: 'Search failed', results: [] });
  }
});

// ─── GET /products/trending ───────────────────────────────────────────────────
// Most scanned products in the last 7 days across all users
// ?limit=20
productRouter.get('/trending', async (req, res) => {
  const { limit = '20' } = req.query as Record<string, string | undefined>;
  const limitNum = Math.min(100, Math.max(1, parseInt(limit ?? '20', 10)));

  try {
    const result = await db.query(
      `SELECT p.id, p.barcode, p.product_name, p.brand, p.category,
              p.image_url, p.score, p.grade,
              COUNT(s.id)::int AS scan_count_7d
       FROM products p
       JOIN scans s ON s.barcode = p.barcode
       WHERE s.scanned_at >= NOW() - INTERVAL '7 days'
       GROUP BY p.id
       ORDER BY scan_count_7d DESC
       LIMIT $1`,
      [limitNum]
    );
    res.json({ products: result.rows });
  } catch (err) {
    console.error('[products/trending]', err);
    // Fallback: return top-scanned overall if scans table join fails
    try {
      const fallback = await db.query(
        `SELECT id, barcode, product_name, brand, category, image_url, score, grade
         FROM products
         ORDER BY scan_count DESC NULLS LAST
         LIMIT $1`,
        [limitNum]
      );
      res.json({ products: fallback.rows });
    } catch {
      res.json({ products: [] });
    }
  }
});

// ─── GET /products/hall-of-shame ──────────────────────────────────────────────
// Worst-scoring products (score < 30) — engagement bait, famous brands scoring F
// ?limit=20
productRouter.get('/hall-of-shame', async (req, res) => {
  const { limit = '20' } = req.query as Record<string, string | undefined>;
  const limitNum = Math.min(100, Math.max(1, parseInt(limit ?? '20', 10)));

  try {
    const result = await db.query(
      `SELECT id, barcode, product_name, brand, category, image_url, score, grade
       FROM products
       WHERE score < 30
       ORDER BY score ASC, scan_count DESC NULLS LAST
       LIMIT $1`,
      [limitNum]
    );
    res.json({ products: result.rows });
  } catch (err) {
    console.error('[products/hall-of-shame]', err);
    res.json({ products: [] });
  }
});

// ─── GET /products/hidden-gems ────────────────────────────────────────────────
// Highest-scoring products (score > 85) — clean swaps for common bad products
// ?limit=20
productRouter.get('/hidden-gems', async (req, res) => {
  const { limit = '20' } = req.query as Record<string, string | undefined>;
  const limitNum = Math.min(100, Math.max(1, parseInt(limit ?? '20', 10)));

  try {
    const result = await db.query(
      `SELECT id, barcode, product_name, brand, category, image_url, score, grade
       FROM products
       WHERE score > 85
       ORDER BY score DESC, scan_count DESC NULLS LAST
       LIMIT $1`,
      [limitNum]
    );
    res.json({ products: result.rows });
  } catch (err) {
    console.error('[products/hidden-gems]', err);
    res.json({ products: [] });
  }
});

// ─── GET /products/recently-added ────────────────────────────────────────────
// Products most recently added to the DB (freshness signal)
// ?limit=20
productRouter.get('/recently-added', async (req, res) => {
  const { limit = '20' } = req.query as Record<string, string | undefined>;
  const limitNum = Math.min(100, Math.max(1, parseInt(limit ?? '20', 10)));

  try {
    const result = await db.query(
      `SELECT id, barcode, product_name, brand, category, image_url, score, grade
       FROM products
       ORDER BY created_at DESC NULLS LAST
       LIMIT $1`,
      [limitNum]
    );
    res.json({ products: result.rows });
  } catch (err) {
    console.error('[products/recently-added]', err);
    res.json({ products: [] });
  }
});
