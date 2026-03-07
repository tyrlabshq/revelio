import { db } from '../db';
import { scoreProduct } from './scorer';

export interface AlternativeResult {
  id: string;
  barcode: string;
  name: string;
  brand: string;
  score: number;
  grade: string;
  imageUrl: string | null;
  purchaseUrl: string;
  affiliateNetwork: string;
  priceCents: number | null;
}

// ─── scoreToGrade helper ──────────────────────────────────────────────────────

function scoreToGrade(score: number): string {
  if (score >= 85) return 'A';
  if (score >= 70) return 'B';
  if (score >= 55) return 'C';
  if (score >= 40) return 'D';
  return 'F';
}

// ─── Main finder ──────────────────────────────────────────────────────────────

export async function findAlternatives(
  barcode: string,
  category: string,
  flags: any[]
): Promise<AlternativeResult[]> {

  // Get the current product's score (for filtering — only show better alternatives)
  let currentScore = 0;
  try {
    const pRow = await db.query('SELECT ingredients FROM products WHERE barcode = $1', [barcode]);
    if (pRow.rows[0]) {
      const ings = typeof pRow.rows[0].ingredients === 'string'
        ? JSON.parse(pRow.rows[0].ingredients)
        : pRow.rows[0].ingredients;
      const scored = await scoreProduct(ings, category, []);
      currentScore = scored.baseScore;
    }
  } catch {
    // Non-fatal: if we can't get current score, just return seeded alternatives
  }

  // 1. Pull pre-seeded alternatives for this barcode
  const seeded = await db.query(
    `SELECT * FROM alternatives WHERE barcode = $1 AND score > $2 ORDER BY score DESC, (affiliate_url IS NOT NULL) DESC LIMIT 3`,
    [barcode, currentScore]
  );

  const results: AlternativeResult[] = seeded.rows.map((row: any) => ({
    id: String(row.id),
    barcode: row.alternative_barcode,
    name: row.name || 'Unknown Product',
    brand: row.brand || 'Unknown Brand',
    score: row.score ?? 85,
    grade: row.grade ?? scoreToGrade(row.score ?? 85),
    imageUrl: row.image_url ?? null,
    purchaseUrl: row.affiliate_url || `https://www.amazon.com/s?k=${encodeURIComponent(row.name || '')}`,
    affiliateNetwork: row.affiliate_network || 'amazon',
    priceCents: row.price_cents ?? null,
  }));

  if (results.length >= 3) return results.slice(0, 3);

  // 2. Supplement with dynamic lookup from products table (same category, no sev-3 flags)
  const sev3ingredients = flags
    .filter((f: any) => f.severity === 3)
    .map((f: any) => f.ingredient?.toLowerCase?.() ?? '');

  try {
    const dynamic = await db.query(
      `SELECT barcode, name, brand, image_url, ingredients FROM products
       WHERE category = $1 AND barcode != $2
       LIMIT 50`,
      [category, barcode]
    );

    for (const row of dynamic.rows) {
      if (results.length >= 3) break;
      if (results.some(r => r.barcode === row.barcode)) continue;

      const ings = typeof row.ingredients === 'string'
        ? JSON.parse(row.ingredients)
        : (row.ingredients ?? []);

      // Check no severity-3 ingredient
      const hasSev3 = sev3ingredients.some((bad: string) =>
        ings.some((ing: string) => ing.toLowerCase().includes(bad))
      );
      if (hasSev3) continue;

      const scored = await scoreProduct(ings, category, []);
      if (scored.baseScore <= currentScore) continue;

      results.push({
        id: `dyn-${row.barcode}`,
        barcode: row.barcode,
        name: row.name || 'Unknown',
        brand: row.brand || 'Unknown',
        score: scored.baseScore,
        grade: scored.grade,
        imageUrl: row.image_url ?? null,
        purchaseUrl: `https://www.amazon.com/s?k=${encodeURIComponent(row.name || '')}`,
        affiliateNetwork: 'amazon',
        priceCents: null,
      });
    }
  } catch {
    // Non-fatal: dynamic lookup failed, return what we have
  }

  // Sort final list: score desc, affiliate link first
  results.sort((a, b) => {
    if (a.purchaseUrl.includes('amzn') !== b.purchaseUrl.includes('amzn')) {
      return a.purchaseUrl.includes('amzn') ? -1 : 1;
    }
    return b.score - a.score;
  });

  return results.slice(0, 3);
}
