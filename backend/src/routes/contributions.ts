import { Router, Response } from 'express';
import { db } from '../db';
import { requireAuth, AuthRequest } from './auth';

export const contributionsRouter = Router();

// ─── POST /contributions — submit a missing product ───────────────────────────
// User-facing endpoint. Queued as `status = 'pending'` for later moderation
// before being pushed upstream to OpenFoodFacts.

contributionsRouter.post('/', requireAuth, async (req: AuthRequest, res: Response) => {
  const { barcode, name, brand, category, imageUrl, ingredientsText } = req.body as {
    barcode?: string;
    name?: string;
    brand?: string;
    category?: string;
    imageUrl?: string;
    ingredientsText?: string;
  };

  if (!barcode || typeof barcode !== 'string' || !/^[0-9]{6,20}$/.test(barcode.trim())) {
    return res.status(400).json({ error: 'Valid barcode (6–20 digits) is required' });
  }

  if (!name || name.trim().length < 2) {
    return res.status(400).json({ error: 'name is required' });
  }

  const allowedCategories = new Set(['food', 'cosmetics', 'cleaning', 'supplements']);
  const cat = category && allowedCategories.has(category) ? category : 'food';

  try {
    const result = await db.query(
      `INSERT INTO product_contributions
         (barcode, name, brand, category, image_url, ingredients_text, submitted_by, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending')
       RETURNING id, barcode, status, created_at`,
      [
        barcode.trim(),
        name.trim().slice(0, 255),
        brand ? brand.trim().slice(0, 255) : null,
        cat,
        imageUrl ? imageUrl.trim() : null,
        ingredientsText ? ingredientsText.trim() : null,
        req.user!.userId,
      ]
    );

    return res.status(201).json({
      ok: true,
      contribution: result.rows[0],
    });
  } catch (err: any) {
    console.error('[contributions] insert error:', err.message);
    return res.status(500).json({ error: 'Failed to submit contribution' });
  }
});

// ─── GET /contributions/pending — admin review queue ──────────────────────────
// Gated on `req.user.tier === 'admin'`. The current schema only exposes
// `free` and `pro` tiers.
// TODO: add an admin role column (e.g. `is_admin BOOLEAN`) to user_profiles
// and authorize against it here rather than overloading the tier field.

contributionsRouter.get('/pending', requireAuth, async (req: AuthRequest, res: Response) => {
  if (req.user?.tier !== 'admin') {
    return res.status(403).json({ error: 'Admin access required' });
  }

  try {
    const result = await db.query(
      `SELECT id, barcode, name, brand, category, image_url, ingredients_text,
              submitted_by, status, created_at
         FROM product_contributions
         WHERE status = 'pending'
         ORDER BY created_at ASC
         LIMIT 200`
    );
    return res.json({ contributions: result.rows });
  } catch (err: any) {
    console.error('[contributions] pending fetch error:', err.message);
    return res.status(500).json({ error: 'Failed to fetch pending contributions' });
  }
});
