import { db } from '../db';
import { scoreProduct } from './scorer';
import { UserPriority } from '../../../shared/scoring';
import { embedOneProduct } from '../jobs/embedProducts';

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

// ─── Smart Swap Cart (REV-T3.2) ───────────────────────────────────────────────
// Turn every grade-D or grade-F pantry item into a cleaner affiliate pick,
// bundled into a single "checkout" URL per network. Reuses the Dupe Finder
// vector path under the hood so the ranking stays consistent with the scan
// result screen.

export interface SwapCartItem {
  sourceBarcode: string;
  sourceName: string;
  sourceBrand: string;
  sourceGrade: string;
  dupe: {
    barcode: string;
    name: string;
    brand: string;
    score: number;
    grade: string;
    imageUrl: string | null;
    category: string;
  } | null;
  affiliateUrl: string;
  priceCents: number | null;
}

export interface SwapCart {
  items: SwapCartItem[];
  totalCents: number;
  affiliateNetwork: string;
  bundledCheckoutUrl: string;
}

async function loadUserPriorities(userId: string): Promise<UserPriority[]> {
  try {
    const r = await db.query(`SELECT priorities FROM user_profiles WHERE id = $1`, [userId]);
    return ((r.rows[0]?.priorities ?? []) as string[]) as UserPriority[];
  } catch {
    return [];
  }
}

async function getOrEmbedSource(barcode: string): Promise<{ vector: string | null; category: string | null }> {
  const r = await db.query(
    `SELECT barcode, name, brand, category, ingredients, description_embedding
       FROM products WHERE barcode = $1`,
    [barcode]
  );
  const row = r.rows[0];
  if (!row) return { vector: null, category: null };
  if (row.description_embedding) {
    return {
      vector: typeof row.description_embedding === 'string' ? row.description_embedding : null,
      category: row.category,
    };
  }
  try {
    const vec = await embedOneProduct({
      barcode: row.barcode,
      name: row.name,
      brand: row.brand,
      category: row.category,
      ingredients: row.ingredients,
    });
    db.query(
      `UPDATE products SET description_embedding = $1::vector WHERE barcode = $2`,
      [vec, row.barcode]
    ).catch(() => { /* non-fatal */ });
    return { vector: vec, category: row.category };
  } catch {
    return { vector: null, category: row.category };
  }
}

async function findTopDupeForBarcode(
  sourceBarcode: string,
  priorities: UserPriority[]
): Promise<SwapCartItem['dupe']> {
  const { vector, category } = await getOrEmbedSource(sourceBarcode);
  if (!vector || !category) return null;

  // Source's personalized score, to ensure we only offer strictly better.
  const srcRow = await db.query(
    `SELECT ingredients FROM products WHERE barcode = $1`,
    [sourceBarcode]
  );
  const srcIngs = (() => {
    try {
      const raw = srcRow.rows[0]?.ingredients;
      return typeof raw === 'string' ? JSON.parse(raw) : Array.isArray(raw) ? raw : [];
    } catch {
      return [];
    }
  })();
  const srcScore = await scoreProduct(srcIngs, category, priorities);

  const ann = await db.query(
    `SELECT barcode, name, brand, category, image_url, ingredients
       FROM products
      WHERE description_embedding IS NOT NULL
        AND category = $2
        AND barcode <> $3
      ORDER BY description_embedding <=> $1::vector
      LIMIT 15`,
    [vector, category, sourceBarcode]
  );

  for (const row of ann.rows) {
    const ings = (() => {
      try {
        return typeof row.ingredients === 'string' ? JSON.parse(row.ingredients) : Array.isArray(row.ingredients) ? row.ingredients : [];
      } catch { return []; }
    })();
    const scored = await scoreProduct(ings, row.category || category, priorities);
    if (scored.personalizedScore <= srcScore.personalizedScore) continue;
    if (scored.flags.some(f => f.severity === 3)) continue;
    return {
      barcode: row.barcode,
      name: row.name || 'Unknown',
      brand: row.brand || 'Unknown',
      score: scored.personalizedScore,
      grade: scored.grade,
      imageUrl: row.image_url ?? null,
      category: row.category || category,
    };
  }
  return null;
}

/**
 * Build a "swap cart" for the authenticated user: one cleaner dupe for every
 * grade-D/F pantry item, bundled into a single affiliate checkout URL.
 */
export async function buildSwapCart(
  userId: string,
  network: 'amazon' | 'thrive_market' | 'iherb' = 'amazon'
): Promise<SwapCart> {
  const priorities = await loadUserPriorities(userId);

  const pantry = await db.query(
    `SELECT barcode, product_name, brand, grade
       FROM pantry_items
      WHERE user_id::text = $1 AND (grade = 'D' OR grade = 'F')`,
    [userId]
  );

  const items: SwapCartItem[] = [];
  let totalCents = 0;
  const searchTerms: string[] = [];

  for (const row of pantry.rows) {
    const dupe = await findTopDupeForBarcode(row.barcode, priorities);
    const searchQuery = dupe
      ? [dupe.brand, dupe.name].filter(Boolean).join(' ')
      : row.product_name || row.barcode;
    const affiliateUrl =
      network === 'amazon'
        ? `https://www.amazon.com/s?k=${encodeURIComponent(searchQuery)}&tag=revelio-20`
        : network === 'thrive_market'
          ? `https://thrivemarket.com/p/search?q=${encodeURIComponent(searchQuery)}&ref=revelio`
          : `https://www.iherb.com/search?kw=${encodeURIComponent(searchQuery)}&rcode=revelio`;
    searchTerms.push(searchQuery);

    items.push({
      sourceBarcode: row.barcode,
      sourceName: row.product_name || 'Unknown',
      sourceBrand: row.brand || 'Unknown',
      sourceGrade: row.grade,
      dupe,
      affiliateUrl,
      priceCents: null,
    });
  }

  // Bundle the search terms into one Amazon cart URL. Amazon doesn't have a
  // public multi-ASIN add-to-cart endpoint without affiliate tooling, so we
  // hand the user an aggregated search-results page keyed off every dupe.
  const bundleQuery = searchTerms.filter(Boolean).slice(0, 10).join(' | ');
  const bundledCheckoutUrl =
    network === 'amazon'
      ? `https://www.amazon.com/s?k=${encodeURIComponent(bundleQuery || 'clean pantry')}&tag=revelio-20`
      : network === 'thrive_market'
        ? `https://thrivemarket.com/p/search?q=${encodeURIComponent(bundleQuery)}&ref=revelio`
        : `https://www.iherb.com/search?kw=${encodeURIComponent(bundleQuery)}&rcode=revelio`;

  return {
    items,
    totalCents,
    affiliateNetwork: network,
    bundledCheckoutUrl,
  };
}
