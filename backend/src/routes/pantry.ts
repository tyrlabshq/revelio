import { Router, Request, Response } from 'express';
import { db } from '../db';

export const pantryRouter = Router();

// ─── Helpers ──────────────────────────────────────────────────────────────────

function gradeFromScore(score: number): string {
  if (score >= 85) return 'A';
  if (score >= 70) return 'B';
  if (score >= 55) return 'C';
  if (score >= 40) return 'D';
  return 'F';
}

function weightForGrade(grade: string): number {
  if (grade === 'F') return 3;
  if (grade === 'D') return 2;
  return 1;
}

async function ensurePantryTable(): Promise<void> {
  await db.query(`
    CREATE TABLE IF NOT EXISTS pantry_items (
      id          SERIAL PRIMARY KEY,
      user_id     VARCHAR NOT NULL,
      barcode     VARCHAR NOT NULL,
      product_name VARCHAR,
      brand       VARCHAR,
      score       INTEGER DEFAULT 0,
      grade       VARCHAR DEFAULT 'C',
      image_url   TEXT,
      category    VARCHAR DEFAULT 'food',
      added_at    TIMESTAMP DEFAULT NOW(),
      UNIQUE(user_id, barcode)
    )
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_pantry_user ON pantry_items(user_id)
  `);
}

// Bootstrap table on first import
ensurePantryTable().catch(console.error);

// ─── POST /pantry — add item ──────────────────────────────────────────────────
pantryRouter.post('/', async (req: Request, res: Response) => {
  const { user_id, barcode } = req.body;
  if (!user_id || !barcode) {
    return res.status(400).json({ error: 'user_id and barcode required' });
  }

  try {
    // Pull cached product data
    const prod = await db.query('SELECT * FROM products WHERE barcode = $1', [barcode]);
    const product = prod.rows[0];

    const name = product?.name || 'Unknown Product';
    const brand = product?.brand || 'Unknown';
    const imageUrl = product?.image_url || null;
    const category = product?.category || 'food';

    // Pull cached score (from scores table if available, or fall back)
    let score = 50;
    let grade = 'C';
    try {
      const scoreRow = await db.query(
        'SELECT score, grade FROM product_scores WHERE barcode = $1 ORDER BY created_at DESC LIMIT 1',
        [barcode]
      );
      if (scoreRow.rows[0]) {
        score = scoreRow.rows[0].score;
        grade = scoreRow.rows[0].grade;
      }
    } catch {
      // scores table may not exist yet — ignore
    }

    await db.query(`
      INSERT INTO pantry_items (user_id, barcode, product_name, brand, score, grade, image_url, category)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      ON CONFLICT (user_id, barcode) DO UPDATE SET
        product_name = EXCLUDED.product_name,
        brand = EXCLUDED.brand,
        score = EXCLUDED.score,
        grade = EXCLUDED.grade,
        image_url = EXCLUDED.image_url,
        category = EXCLUDED.category,
        added_at = NOW()
    `, [user_id, barcode, name, brand, score, grade, imageUrl, category]);

    return res.status(201).json({ ok: true, barcode, name, score, grade });
  } catch (err) {
    console.error('[pantry] POST error:', err);
    return res.status(500).json({ error: 'Failed to add item' });
  }
});

// ─── DELETE /pantry/:barcode — remove item ────────────────────────────────────
pantryRouter.delete('/:barcode', async (req: Request, res: Response) => {
  const user_id = req.query.user_id as string || req.body?.user_id;
  const { barcode } = req.params;

  if (!user_id) return res.status(400).json({ error: 'user_id required' });

  try {
    const result = await db.query(
      'DELETE FROM pantry_items WHERE user_id = $1 AND barcode = $2 RETURNING id',
      [user_id, barcode]
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Item not found' });
    return res.json({ ok: true, barcode });
  } catch (err) {
    console.error('[pantry] DELETE error:', err);
    return res.status(500).json({ error: 'Failed to remove item' });
  }
});

// ─── GET /pantry — all items for a user ──────────────────────────────────────
pantryRouter.get('/', async (req: Request, res: Response) => {
  const user_id = req.query.user_id as string;
  if (!user_id) return res.status(400).json({ error: 'user_id required' });

  try {
    const result = await db.query(
      `SELECT id, barcode, product_name, brand, score, grade, image_url, category, added_at
       FROM pantry_items WHERE user_id = $1 ORDER BY added_at DESC`,
      [user_id]
    );

    const items = result.rows.map(r => ({
      id: r.id,
      barcode: r.barcode,
      productName: r.product_name,
      brand: r.brand,
      score: r.score,
      grade: r.grade,
      imageUrl: r.image_url,
      category: r.category,
      addedAt: r.added_at,
    }));

    return res.json({ items });
  } catch (err) {
    console.error('[pantry] GET error:', err);
    return res.status(500).json({ error: 'Failed to fetch pantry' });
  }
});

// ─── GET /pantry/score — household aggregate ──────────────────────────────────
pantryRouter.get('/score', async (req: Request, res: Response) => {
  const user_id = req.query.user_id as string;
  if (!user_id) return res.status(400).json({ error: 'user_id required' });

  try {
    const result = await db.query(
      'SELECT score, grade FROM pantry_items WHERE user_id = $1',
      [user_id]
    );

    const items = result.rows;
    if (items.length === 0) {
      return res.json({ score: 0, grade: 'N/A', clean: 0, concerning: 0, avoid: 0, total: 0 });
    }

    let weightedSum = 0;
    let totalWeight = 0;
    let clean = 0, concerning = 0, avoid = 0;

    for (const item of items) {
      const w = weightForGrade(item.grade);
      weightedSum += item.score * w;
      totalWeight += w;

      if (item.grade === 'A' || item.grade === 'B') clean++;
      else if (item.grade === 'C') concerning++;
      else avoid++;
    }

    const householdScore = Math.round(weightedSum / totalWeight);
    const grade = gradeFromScore(householdScore);
    const total = items.length;

    // Worst offenders (top 3 lowest scored)
    const worstOffenders = await db.query(
      `SELECT barcode, product_name, score, grade
       FROM pantry_items WHERE user_id = $1
       ORDER BY score ASC LIMIT 3`,
      [user_id]
    );

    // Quick wins (score < 50)
    const quickWins = await db.query(
      `SELECT barcode, product_name, score, grade
       FROM pantry_items WHERE user_id = $1 AND score < 50
       ORDER BY score ASC LIMIT 3`,
      [user_id]
    );

    return res.json({
      score: householdScore,
      grade,
      clean: Math.round((clean / total) * 100),
      concerning: Math.round((concerning / total) * 100),
      avoid: Math.round((avoid / total) * 100),
      total,
      worstOffenders: worstOffenders.rows.map(r => ({
        barcode: r.barcode,
        productName: r.product_name,
        score: r.score,
        grade: r.grade,
      })),
      quickWins: quickWins.rows.map(r => ({
        barcode: r.barcode,
        productName: r.product_name,
        score: r.score,
        grade: r.grade,
      })),
    });
  } catch (err) {
    console.error('[pantry] score error:', err);
    return res.status(500).json({ error: 'Failed to compute household score' });
  }
});
