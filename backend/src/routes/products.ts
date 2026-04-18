import { Router } from 'express';
import { db } from '../db';
import { requireAuth, AuthRequest } from './auth';
import { scoreProduct } from '../services/scorer';
import { UserPriority } from '../../../shared/scoring';
import { embedOneProduct } from '../jobs/embedProducts';

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

// ─── GET /products/:barcode/dupes?limit=3 ─────────────────────────────────────
// REV-T3.4: Dupe Finder.
// Returns N products in the same category that (a) are nearest-neighbors of the
// source product's description embedding, (b) score higher once personalized
// for the caller's priorities, and (c) have no severity-3 flag.
//
// If the source product has no embedding yet, embed it inline (2s soft cap).

interface DupeRow {
  barcode: string;
  name: string | null;
  brand: string | null;
  category: string | null;
  image_url: string | null;
  ingredients: unknown;
  distance: number;
}

async function loadUserPriorities(userId: string): Promise<UserPriority[]> {
  try {
    const r = await db.query(
      `SELECT priorities FROM user_profiles WHERE id = $1`,
      [userId]
    );
    const arr = (r.rows[0]?.priorities ?? []) as string[];
    return arr as UserPriority[];
  } catch {
    return [];
  }
}

function safeParseIngredients(raw: unknown): string[] {
  try {
    if (typeof raw === 'string') return JSON.parse(raw);
    if (Array.isArray(raw)) return raw as string[];
  } catch {
    /* noop */
  }
  return [];
}

async function runWithTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout')), ms);
    p.then(v => {
      clearTimeout(timer);
      resolve(v);
    }).catch(err => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

productRouter.get('/:barcode/dupes', requireAuth, async (req: AuthRequest, res) => {
  const { barcode } = req.params;
  const limit = Math.min(10, Math.max(1, parseInt((req.query.limit as string) ?? '3', 10)));

  try {
    // 1. Source product + embedding.
    const src = await db.query(
      `SELECT barcode, name, brand, category, image_url, ingredients,
              description_embedding
         FROM products WHERE barcode = $1`,
      [barcode]
    );
    const source = src.rows[0];
    if (!source) {
      return res.status(404).json({ error: 'Product not found' });
    }

    let sourceVectorLiteral: string | null = null;
    if (source.description_embedding) {
      // pg returns vector as a string like "[0.1,0.2,...]" already.
      sourceVectorLiteral =
        typeof source.description_embedding === 'string'
          ? source.description_embedding
          : null;
    }

    if (!sourceVectorLiteral) {
      try {
        sourceVectorLiteral = await runWithTimeout(
          embedOneProduct({
            barcode: source.barcode,
            name: source.name,
            brand: source.brand,
            category: source.category,
            ingredients: source.ingredients,
          }),
          2000
        );
        // Persist for next time (fire-and-forget).
        db.query(
          `UPDATE products SET description_embedding = $1::vector WHERE barcode = $2`,
          [sourceVectorLiteral, source.barcode]
        ).catch(() => { /* non-fatal */ });
      } catch (err) {
        console.error('[products/dupes] inline embed failed:', err);
        return res.json({ dupes: [], reason: 'source_embedding_unavailable' });
      }
    }

    // 2. Score the source for this user.
    const priorities = await loadUserPriorities(req.user!.userId);
    const srcIngs = safeParseIngredients(source.ingredients);
    const category = source.category || 'food';
    const srcScore = await scoreProduct(srcIngs, category, priorities);
    const srcPersonalized = srcScore.personalizedScore;

    // 3. Nearest-neighbors in the same category, excluding the source.
    // We over-fetch (5x limit, cap 30) so we can re-score + filter client-side
    // and still return `limit` results without a second round-trip.
    const ann = await db.query<DupeRow>(
      `SELECT barcode, name, brand, category, image_url, ingredients,
              description_embedding <=> $1::vector AS distance
         FROM products
        WHERE description_embedding IS NOT NULL
          AND category = $2
          AND barcode <> $3
        ORDER BY description_embedding <=> $1::vector
        LIMIT $4`,
      [sourceVectorLiteral, category, barcode, Math.min(30, limit * 5)]
    );

    // 4. Re-score each candidate with the user's priorities; drop any with a
    //    severity-3 flag or a score not strictly better than the source.
    const dupes: Array<{
      barcode: string;
      name: string;
      brand: string;
      category: string;
      imageUrl: string | null;
      score: number;
      grade: 'A' | 'B' | 'C' | 'D' | 'F';
      distance: number;
      affiliateUrl: string;
      affiliateNetwork: string;
    }> = [];

    for (const row of ann.rows) {
      if (dupes.length >= limit) break;
      const ings = safeParseIngredients(row.ingredients);
      const scored = await scoreProduct(ings, row.category || category, priorities);
      if (scored.personalizedScore <= srcPersonalized) continue;
      if (scored.flags.some(f => f.severity === 3)) continue;
      dupes.push({
        barcode: row.barcode,
        name: row.name || 'Unknown',
        brand: row.brand || 'Unknown',
        category: row.category || category,
        imageUrl: row.image_url,
        score: scored.personalizedScore,
        grade: scored.grade,
        distance: Number(row.distance) || 0,
        affiliateUrl: `https://www.amazon.com/s?k=${encodeURIComponent(
          [row.brand, row.name].filter(Boolean).join(' ')
        )}&tag=revelio-20`,
        affiliateNetwork: 'amazon',
      });
    }

    return res.json({
      sourceBarcode: barcode,
      sourceScore: srcPersonalized,
      sourceGrade: srcScore.grade,
      dupes,
    });
  } catch (err: any) {
    console.error('[products/dupes] error:', err);
    return res.status(500).json({ error: 'Failed to find dupes' });
  }
});
