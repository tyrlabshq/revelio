import { Router } from 'express';
import { z } from 'zod';
import { db } from '../db';
import { requireAuth, AuthRequest } from './auth';
import { scoreProduct } from '../services/scorer';
import { logger } from '../logger';

export const receiptsRouter = Router();

// ─── Zod schema ───────────────────────────────────────────────────────────────

const ScoreBody = z.object({
  lines: z
    .array(z.string().min(1).max(80))
    .min(1)
    .max(50),
});

// ─── Types ────────────────────────────────────────────────────────────────────

interface ProductSummary {
  barcode: string;
  name: string;
  brand: string;
  category: string;
  imageUrl: string | null;
}

interface LineItemResult {
  line: string;
  match: ProductSummary | null;
  score: number | null;
  grade: string | null;
  flags: unknown[];
}

interface Aggregate {
  avgScore: number;
  grade: string;
  clean: number;
  concerning: number;
  avoid: number;
  worstOffender: ProductSummary | null;
  swapSuggestion: ProductSummary | null;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function gradeFromScore(score: number): string {
  if (score >= 85) return 'A';
  if (score >= 70) return 'B';
  if (score >= 55) return 'C';
  if (score >= 40) return 'D';
  return 'F';
}

async function topCandidate(line: string): Promise<ProductSummary | null> {
  // Use pg_trgm similarity across name + brand, take best over the threshold.
  const result = await db.query(
    `
    SELECT barcode, name, brand, category, image_url,
           GREATEST(
             similarity(COALESCE(name, ''), $1),
             similarity(COALESCE(brand, ''), $1)
           ) AS sim
      FROM products
     WHERE name ILIKE '%' || $1 || '%'
        OR brand ILIKE '%' || $1 || '%'
        OR similarity(COALESCE(name, ''), $1) >= 0.6
        OR similarity(COALESCE(brand, ''), $1) >= 0.6
     ORDER BY sim DESC
     LIMIT 1
    `,
    [line]
  );
  const row = result.rows[0];
  if (!row || Number(row.sim) < 0.6) return null;
  return {
    barcode: row.barcode,
    name: row.name ?? 'Unknown',
    brand: row.brand ?? 'Unknown',
    category: row.category ?? 'food',
    imageUrl: row.image_url ?? null,
  };
}

async function findCleanerSwap(
  offender: ProductSummary
): Promise<ProductSummary | null> {
  // Try the alternatives table first; fall back to a same-category high scorer.
  try {
    const alt = await db.query(
      `SELECT alternative_barcode AS barcode, name, brand, NULL::text AS image_url
         FROM alternatives
        WHERE barcode = $1
        ORDER BY score DESC NULLS LAST
        LIMIT 1`,
      [offender.barcode]
    );
    if (alt.rows[0]) {
      return {
        barcode: alt.rows[0].barcode,
        name: alt.rows[0].name ?? 'Cleaner option',
        brand: alt.rows[0].brand ?? 'Unknown',
        category: offender.category,
        imageUrl: alt.rows[0].image_url ?? null,
      };
    }
  } catch {
    // alternatives table may be empty/not-present in some environments
  }
  return null;
}

// ─── POST /receipts/score ─────────────────────────────────────────────────────

receiptsRouter.post('/score', requireAuth, async (req: AuthRequest, res) => {
  const parsed = ScoreBody.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      error: 'Invalid body',
      issues: parsed.error.issues.map(i => ({ path: i.path, message: i.message })),
    });
  }

  const { lines } = parsed.data;

  try {
    const items: LineItemResult[] = [];

    for (const line of lines) {
      const cleaned = line.trim();
      if (cleaned.length < 3) {
        items.push({ line, match: null, score: null, grade: null, flags: [] });
        continue;
      }

      const match = await topCandidate(cleaned);
      if (!match) {
        items.push({ line, match: null, score: null, grade: null, flags: [] });
        continue;
      }

      const prodRow = await db.query(
        'SELECT ingredients, category FROM products WHERE barcode = $1',
        [match.barcode]
      );
      const prod = prodRow.rows[0];
      const ings: string[] =
        typeof prod?.ingredients === 'string'
          ? JSON.parse(prod.ingredients)
          : Array.isArray(prod?.ingredients)
          ? prod.ingredients
          : [];
      const category = prod?.category ?? match.category;

      const scored = await scoreProduct(ings, category, []);
      items.push({
        line,
        match,
        score: scored.personalizedScore,
        grade: scored.grade,
        flags: scored.flags,
      });
    }

    // ─── Aggregate ──────────────────────────────────────────────────────────
    const matched = items.filter(i => i.match && typeof i.score === 'number');
    const total = matched.length;

    let aggregate: Aggregate;
    if (total === 0) {
      aggregate = {
        avgScore: 0,
        grade: 'N/A',
        clean: 0,
        concerning: 0,
        avoid: 0,
        worstOffender: null,
        swapSuggestion: null,
      };
    } else {
      const sum = matched.reduce((acc, i) => acc + (i.score ?? 0), 0);
      const avgScore = Math.round(sum / total);
      const clean = matched.filter(i => i.grade === 'A' || i.grade === 'B').length;
      const concerning = matched.filter(i => i.grade === 'C').length;
      const avoid = matched.filter(i => i.grade === 'D' || i.grade === 'F').length;

      const worst = matched.reduce((prev, cur) =>
        (prev.score ?? 100) <= (cur.score ?? 100) ? prev : cur
      );
      const worstOffender = worst.match;
      const swapSuggestion = worstOffender
        ? await findCleanerSwap(worstOffender)
        : null;

      aggregate = {
        avgScore,
        grade: gradeFromScore(avgScore),
        clean: Math.round((clean / total) * 100),
        concerning: Math.round((concerning / total) * 100),
        avoid: Math.round((avoid / total) * 100),
        worstOffender,
        swapSuggestion,
      };
    }

    return res.json({ items, aggregate });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'receipts-score-failed' }, '[receipts] score error');
    return res.status(500).json({ error: 'Failed to score receipt' });
  }
});
