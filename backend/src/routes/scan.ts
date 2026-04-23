import { Router } from 'express';
import { db } from '../db';
import { scoreProduct } from '../services/scorer';
import { recordScanForStreak } from '../services/streaks';
import { UserPriority } from '../../../shared/scoring';
import { requireAuth, AuthRequest } from './auth';
import { logger } from '../logger';

export const scanRouter = Router();

const OFF_BASE = 'https://world.openfoodfacts.org/api/v2/product';

async function fetchFromAPI(barcode: string): Promise<any> {
  try {
    const res = await fetch(`${OFF_BASE}/${barcode}.json?fields=product_name,brands,image_url,ingredients_text,categories_tags`);
    // as any: OFF v2 API has no published TS types — the shape is validated by the status/product checks below.
    const data = await res.json() as any;
    if (data.status === 1 && data.product) return data.product;
  } catch {}
  return null;
}

function parseIngredients(text: string): string[] {
  if (!text) return [];
  return text.toLowerCase().replace(/\([^)]*\)/g, '').replace(/\d+%/g, '')
    .split(/[,;]/).map(s => s.trim().replace(/^[\-*•]/, '').trim()).filter(s => s.length > 1);
}

// ─── GET /scan/:barcode ───────────────────────────────────────────────────────
//
// Public, unauthed lookup — safe for Cloudflare / any downstream CDN to cache.
// Cache-Control: let browsers reuse for 1 day, let the shared cache (CDN)
// reuse for 7 days (matches the Postgres/Redis freshness window), and allow
// serving stale up to 1 day while we refetch in the background.
// Vary: Authorization is defensive — if an auth header ever leaks into this
// path it must not pollute a shared cache entry.

scanRouter.get('/:barcode', async (req, res) => {
  const { barcode } = req.params;
  const bypassCache = /no-cache/i.test(req.headers['cache-control'] ?? '');
  try {
    const cached = bypassCache
      // as any[]: synthetic pg.QueryResult-shaped placeholder when we skip the DB cache — matches the rows shape downstream.
      ? { rows: [] as any[] }
      : await db.query('SELECT * FROM products WHERE barcode = $1', [barcode]);
    let product = cached.rows[0];
    const needsFetch = !product || (Date.now() - new Date(product.last_fetched).getTime() > 7 * 24 * 60 * 60 * 1000);

    if (needsFetch) {
      const raw = await fetchFromAPI(barcode);
      if (!raw) return res.status(404).json({ found: false, barcode });
      const ingredients = parseIngredients(raw.ingredients_text || '');
      const category = (raw.categories_tags || []).some((c: string) => c.includes('cosmetic') || c.includes('beauty')) ? 'cosmetics' : 'food';
      await db.query(`
        INSERT INTO products (barcode, name, brand, category, image_url, ingredients, off_data, last_fetched)
        VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
        ON CONFLICT (barcode) DO UPDATE SET name=$2, brand=$3, category=$4, image_url=$5, ingredients=$6, off_data=$7, last_fetched=NOW()`,
        [barcode, raw.product_name || 'Unknown', raw.brands || 'Unknown', category, raw.image_url, JSON.stringify(ingredients), JSON.stringify(raw)]
      );
      product = { barcode, name: raw.product_name, brand: raw.brands, category, image_url: raw.image_url, ingredients };
    }

    const ings = typeof product.ingredients === 'string' ? JSON.parse(product.ingredients) : product.ingredients;
    const result = await scoreProduct(ings, product.category, []);

    res.setHeader(
      'Cache-Control',
      'public, max-age=86400, s-maxage=604800, stale-while-revalidate=86400'
    );
    res.setHeader('Vary', 'Authorization');
    res.json({
      id: crypto.randomUUID(), barcode, productName: product.name || 'Unknown', brand: product.brand || 'Unknown',
      category: product.category || 'food', imageUrl: product.image_url, ingredients: ings, flags: result.flags,
      baseScore: result.baseScore, personalizedScore: result.personalizedScore, grade: result.grade,
      scannedAt: new Date().toISOString()
    });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'scan-failed' }, 'Scan error');
    res.status(500).json({ error: 'Failed to scan' });
  }
});

// ─── POST /scan/history — Record a scan ───────────────────────────────────────

scanRouter.post('/history', requireAuth, async (req: AuthRequest, res) => {
  const { barcode, productName, brand, category, imageUrl, score, grade, flags } = req.body as {
    barcode: string;
    productName: string;
    brand?: string;
    category?: string;
    imageUrl?: string;
    score: number;
    grade: string;
    flags?: unknown[];
  };

  const userId = req.user!.userId;
  if (!barcode) return res.status(400).json({ error: 'barcode is required' });

  try {
    await db.query(
      `INSERT INTO scans (user_id, barcode, product_name, brand, category, image_url, score, grade, flags, scanned_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())`,
      [userId, barcode, productName, brand || null, category || 'food', imageUrl || null, score, grade, JSON.stringify(flags ?? [])]
    );
    if (userId) {
      // Narrowly scoped: update streak state for this authenticated user.
      // Failures here shouldn't block the scan insert.
      try {
        await recordScanForStreak(userId);
      } catch (streakErr: any) {
        logger.error({ err: streakErr?.message, event: 'scan-streak-update-failed' }, 'streak update failed');
      }
    }
    res.status(201).json({ ok: true });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'scan-history-record-failed' }, 'History record error');
    res.status(500).json({ error: 'Failed to record scan' });
  }
});

// ─── GET /scan/history — Get scan history for a user ──────────────────────────

scanRouter.get('/history', requireAuth, async (req: AuthRequest, res) => {
  const { limit = '50' } = req.query as { limit?: string };
  const userId = req.user!.userId;

  try {
    const result = await db.query(
      `SELECT id, barcode, product_name, score, grade, scanned_at
       FROM scans WHERE user_id = $1
       ORDER BY scanned_at DESC LIMIT $2`,
      [userId, parseInt(limit, 10)]
    );
    res.json(result.rows);
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'scan-history-fetch-failed' }, 'History fetch error');
    res.status(500).json({ error: 'Failed to fetch history' });
  }
});

// ─── POST /scan/personalize ───────────────────────────────────────────────────

scanRouter.post('/personalize', async (req, res) => {
  const { barcode, priorities } = req.body as {
    barcode: string;
    priorities: UserPriority[];
  };

  if (!barcode) {
    return res.status(400).json({ error: 'barcode is required' });
  }

  try {
    const cached = await db.query('SELECT * FROM products WHERE barcode = $1', [barcode]);
    const product = cached.rows[0];

    if (!product) {
      return res.status(404).json({ error: 'Product not found. Scan it first via GET /scan/:barcode', barcode });
    }

    const ings = typeof product.ingredients === 'string' ? JSON.parse(product.ingredients) : product.ingredients;
    const result = await scoreProduct(ings, product.category || 'food', priorities ?? []);

    return res.json({
      barcode,
      productName: product.name || 'Unknown',
      personalizedScore: result.personalizedScore,
      grade: result.grade,
      flags: result.flags,
    });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'scan-personalize-failed' }, 'Personalize error');
    return res.status(500).json({ error: 'Failed to personalize score' });
  }
});

// ─── POST /scan/ocr — score an ingredient list from on-device OCR ─────────────
// Added by OCR/offline agent (Track 2.4). Accepts raw ingredient text captured
// on-device by the iOS Vision pipeline and returns the same shape as
// GET /scan/:barcode so clients can reuse their rendering logic.

scanRouter.post('/ocr', requireAuth, async (req: AuthRequest, res) => {
  const { ingredientText, category, priorities, barcode } = req.body as {
    ingredientText?: string;
    category?: string;
    priorities?: UserPriority[];
    barcode?: string;
  };

  if (!ingredientText || typeof ingredientText !== 'string' || ingredientText.trim().length < 3) {
    return res.status(400).json({ error: 'ingredientText is required' });
  }

  // Guardrail on payload size — OCR'd labels rarely exceed ~4 KB.
  if (ingredientText.length > 20_000) {
    return res.status(413).json({ error: 'ingredientText too long' });
  }

  try {
    const ings = parseIngredients(ingredientText);
    if (ings.length === 0) {
      return res.status(422).json({ error: 'No ingredients parsed from text' });
    }

    const cat = (category === 'cosmetics' || category === 'cleaning' || category === 'supplements')
      ? category
      : 'food';

    const result = await scoreProduct(ings, cat, priorities ?? []);

    return res.json({
      id: crypto.randomUUID(),
      barcode: barcode || `ocr-${Date.now()}`,
      productName: 'Scanned Label',
      brand: 'Unknown',
      category: cat,
      imageUrl: null,
      ingredients: ings,
      flags: result.flags,
      baseScore: result.baseScore,
      personalizedScore: result.personalizedScore,
      grade: result.grade,
      scannedAt: new Date().toISOString(),
      source: 'ocr',
    });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'scan-ocr-failed' }, '[scan/ocr] error');
    return res.status(500).json({ error: 'Failed to score OCR ingredients' });
  }
});
