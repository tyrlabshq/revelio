import { Router } from 'express';
import { db } from '../db';
import { scoreProduct } from '../services/scorer';
import { UserPriority } from '../../../shared/scoring';
import { requireAuth, optionalAuth, AuthRequest } from '../middleware/auth';
import { checkAndIncrementScanUsage } from '../services/scan-rate-limiter';

export const scanRouter = Router();

const OFF_BASE = 'https://world.openfoodfacts.org/api/v2/product';

// Barcodes are numeric only (EAN-8/12/13, UPC-A/E). Reject anything else so we
// don't blindly forward junk to the Open Food Facts API or the DB.
const BARCODE_RE = /^[0-9]{6,14}$/;

async function fetchFromAPI(barcode: string): Promise<any> {
  try {
    const res = await fetch(`${OFF_BASE}/${barcode}.json?fields=product_name,brands,image_url,ingredients_text,categories_tags`);
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

const KNOWN_PRIORITIES: ReadonlySet<UserPriority> = new Set([
  'seed_oils',
  'artificial_additives',
  'heavy_metals',
  'endocrine_disruptors',
  'gluten_free',
  'keto',
  'vegan',
  'fragrance_free',
  'paraben_free',
  'sulfate_free',
]);

function sanitizePriorities(input: unknown): UserPriority[] {
  if (!Array.isArray(input)) return [];
  const out: UserPriority[] = [];
  for (const p of input) {
    if (typeof p === 'string' && KNOWN_PRIORITIES.has(p as UserPriority)) {
      out.push(p as UserPriority);
    }
    if (out.length >= 20) break;
  }
  return out;
}

// ─── GET /scan/:barcode ───────────────────────────────────────────────────────
// Public (product catalog lookup). If a valid token is supplied, free-tier
// users are rate-limited to 10 scans/day; pro is unlimited; anonymous callers
// are allowed through (they get no personalized history either way).

scanRouter.get('/:barcode', optionalAuth, async (req: AuthRequest, res) => {
  const { barcode } = req.params;
  if (!BARCODE_RE.test(barcode)) {
    return res.status(400).json({ error: 'Invalid barcode' });
  }

  if (req.user) {
    const usage = await checkAndIncrementScanUsage(req.user.userId, req.user.tier);
    if (!usage.allowed) {
      return res.status(429).json({
        error: 'Daily scan limit reached',
        used: usage.used,
        limit: usage.limit,
        upgradeRequired: true,
      });
    }
  }

  try {
    const cached = await db.query('SELECT * FROM products WHERE barcode = $1', [barcode]);
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

    res.json({
      id: crypto.randomUUID(), barcode, productName: product.name || 'Unknown', brand: product.brand || 'Unknown',
      category: product.category || 'food', imageUrl: product.image_url, ingredients: ings, flags: result.flags,
      baseScore: result.baseScore, personalizedScore: result.personalizedScore, grade: result.grade,
      scannedAt: new Date().toISOString()
    });
  } catch (err) {
    console.error('Scan error:', err);
    res.status(500).json({ error: 'Failed to scan' });
  }
});

// ─── POST /scan/history — Record a scan (authenticated) ──────────────────────

scanRouter.post('/history', requireAuth, async (req: AuthRequest, res) => {
  const userId = req.user!.userId;
  const { barcode, productName, brand, category, imageUrl, score, grade, flags } = req.body as {
    barcode?: string;
    productName?: string;
    brand?: string;
    category?: string;
    imageUrl?: string;
    score?: number;
    grade?: string;
    flags?: unknown[];
  };

  if (!barcode || !BARCODE_RE.test(barcode)) {
    return res.status(400).json({ error: 'valid barcode is required' });
  }
  if (typeof score !== 'number' || score < 0 || score > 100) {
    return res.status(400).json({ error: 'score must be a number 0-100' });
  }
  if (typeof grade !== 'string' || !/^[A-F]$/.test(grade)) {
    return res.status(400).json({ error: 'grade must be A-F' });
  }
  if (typeof productName !== 'string' || productName.length === 0 || productName.length > 200) {
    return res.status(400).json({ error: 'productName must be a non-empty string up to 200 chars' });
  }
  if (category !== undefined && typeof category === 'string' && category.length > 40) {
    return res.status(400).json({ error: 'category too long' });
  }

  // Validate the flags payload so we don't store arbitrary JSON blobs.
  const safeFlags = Array.isArray(flags)
    ? flags.slice(0, 50).filter((f): f is Record<string, unknown> =>
        typeof f === 'object' && f !== null && !Array.isArray(f)
      ).map(f => ({
        ingredient: typeof (f as any).ingredient === 'string' ? String((f as any).ingredient).slice(0, 100) : '',
        severity: Number.isInteger((f as any).severity) && (f as any).severity >= 0 && (f as any).severity <= 3
          ? (f as any).severity
          : 0,
        category: typeof (f as any).category === 'string' ? String((f as any).category).slice(0, 60) : '',
        reason: typeof (f as any).reason === 'string' ? String((f as any).reason).slice(0, 500) : '',
      }))
    : [];

  try {
    await db.query(
      `INSERT INTO scans (user_id, barcode, product_name, brand, category, image_url, score, grade, flags, scanned_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())`,
      [userId, barcode, productName, brand || null, category || 'food', imageUrl || null, score, grade, JSON.stringify(safeFlags)]
    );
    res.status(201).json({ ok: true });
  } catch (err) {
    console.error('History record error:', err);
    res.status(500).json({ error: 'Failed to record scan' });
  }
});

// ─── GET /scan/history ────────────────────────────────────────────────────────

scanRouter.get('/history', requireAuth, async (req: AuthRequest, res) => {
  const userId = req.user!.userId;
  const limit = Math.min(200, Math.max(1, parseInt((req.query.limit as string) ?? '50', 10) || 50));

  try {
    const result = await db.query(
      `SELECT id, barcode, product_name, score, grade, scanned_at
       FROM scans WHERE user_id = $1
       ORDER BY scanned_at DESC LIMIT $2`,
      [userId, limit]
    );
    res.json(result.rows);
  } catch (err) {
    console.error('History fetch error:', err);
    res.status(500).json({ error: 'Failed to fetch history' });
  }
});

// ─── POST /scan/personalize ───────────────────────────────────────────────────

scanRouter.post('/personalize', requireAuth, async (req: AuthRequest, res) => {
  const { barcode, priorities } = req.body as {
    barcode?: string;
    priorities?: unknown;
  };

  if (!barcode || !BARCODE_RE.test(barcode)) {
    return res.status(400).json({ error: 'valid barcode is required' });
  }

  const safePriorities = sanitizePriorities(priorities);

  try {
    const cached = await db.query('SELECT * FROM products WHERE barcode = $1', [barcode]);
    const product = cached.rows[0];

    if (!product) {
      return res.status(404).json({ error: 'Product not found. Scan it first via GET /scan/:barcode', barcode });
    }

    const ings = typeof product.ingredients === 'string' ? JSON.parse(product.ingredients) : product.ingredients;
    const result = await scoreProduct(ings, product.category || 'food', safePriorities);

    return res.json({
      barcode,
      productName: product.name || 'Unknown',
      personalizedScore: result.personalizedScore,
      grade: result.grade,
      flags: result.flags,
    });
  } catch (err) {
    console.error('Personalize error:', err);
    return res.status(500).json({ error: 'Failed to personalize score' });
  }
});
