// Brand deep-dive summary service.
//
// Aggregates a brand's product catalogue into:
//   - total product count
//   - grade distribution (A/B/C/D/F)
//   - top 5 cleanest (highest grade, newest)
//   - bottom 5 worst (lowest grade, newest)
//
// The grade is computed on-the-fly per product using scoreBarcode from
// services/scorer — this keeps the brand summary consistent with the
// single-product scan response. Results are cached 24h in Redis so the
// aggregation does not hammer the DB for popular brands.

import { db } from '../db';
import { getRedis } from '../lib/redis';
import { scoreBarcode } from './scorer';
import { logger } from '../logger';

const CACHE_TTL_SEC = 24 * 60 * 60;
const cacheKey = (slug: string) => `brand:summary:v1:${slug}`;

export interface BrandProductCard {
  barcode: string;
  name: string;
  brand: string;
  imageUrl?: string;
  grade: 'A' | 'B' | 'C' | 'D' | 'F';
  score: number;
}

export interface BrandSummary {
  slug: string;
  totalProducts: number;
  distribution: Record<'A' | 'B' | 'C' | 'D' | 'F', number>;
  cleanestPercent: number;
  topCleanest: BrandProductCard[];
  worstProducts: BrandProductCard[];
  cachedAt: string;
}

// ─── Slug helpers ────────────────────────────────────────────────────────────
//
// OFF stores brand strings in a variety of shapes: "Hellmann's", "HELLMANNS",
// "Hellmann's Real" (multiple brands are comma-separated). We slugify on
// write-free reads: lowercase, strip punctuation, collapse spaces to `-`.

export function slugifyBrand(brand: string): string {
  return brand
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // strip diacritics
    .replace(/['’`]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

// Matches any product whose brand column slugs to `slug`. Uses a functional
// LIKE on a normalized column for clarity — pg_trgm would be faster but the
// existing index is on raw brand.
function brandMatchSql(): string {
  // Postgres equivalent of slugifyBrand. We chain regex_replace calls to
  // normalize casing, drop apostrophes, collapse non-alphanumerics to
  // dashes, and trim leading/trailing dashes.
  return `
    trim(
      both '-' from
      regexp_replace(
        regexp_replace(
          regexp_replace(lower(coalesce(brand, '')), '[''’\`]', '', 'g'),
          '[^a-z0-9]+', '-', 'g'
        ),
        '-+', '-', 'g'
      )
    )
  `;
}

// ─── Public API ──────────────────────────────────────────────────────────────

export async function listBrandProducts(
  slug: string,
  opts: { page: number; limit: number; grade?: string }
): Promise<{ products: BrandProductCard[]; total: number }> {
  const offset = Math.max(0, (opts.page - 1) * opts.limit);
  const sql = `
    SELECT barcode, name, brand, image_url
    FROM products
    WHERE ${brandMatchSql()} = $1
    ORDER BY last_fetched DESC
    LIMIT $2 OFFSET $3
  `;
  const totalSql = `SELECT COUNT(*)::int AS c FROM products WHERE ${brandMatchSql()} = $1`;
  const [rows, totalRows] = await Promise.all([
    db.query(sql, [slug, opts.limit, offset]),
    db.query(totalSql, [slug]),
  ]);

  const cards: BrandProductCard[] = [];
  for (const row of rows.rows) {
    const scored = await scoreBarcode(row.barcode, []);
    if (!scored) continue;
    if (opts.grade && scored.grade !== opts.grade) continue;
    cards.push({
      barcode: row.barcode,
      name: row.name ?? 'Unknown',
      brand: row.brand ?? '',
      imageUrl: row.image_url ?? undefined,
      grade: scored.grade,
      score: scored.personalizedScore,
    });
  }

  return { products: cards, total: totalRows.rows[0]?.c ?? 0 };
}

export async function getBrandSummary(slug: string): Promise<BrandSummary> {
  const redis = getRedis();
  if (redis) {
    try {
      const cached = await redis.get(cacheKey(slug));
      if (cached) return JSON.parse(cached) as BrandSummary;
    } catch (err) {
      logger.error({ err: (err as Error).message, event: 'brand-summary-redis-get-failed' }, '[brandSummary] redis get failed');
    }
  }

  const { rows } = await db.query(
    `SELECT barcode, name, brand, image_url, last_fetched
     FROM products
     WHERE ${brandMatchSql()} = $1
     ORDER BY last_fetched DESC`,
    [slug]
  );

  const distribution: BrandSummary['distribution'] = { A: 0, B: 0, C: 0, D: 0, F: 0 };
  const scored: BrandProductCard[] = [];

  for (const row of rows) {
    const s = await scoreBarcode(row.barcode, []);
    if (!s) continue;
    distribution[s.grade]++;
    scored.push({
      barcode: row.barcode,
      name: row.name ?? 'Unknown',
      brand: row.brand ?? '',
      imageUrl: row.image_url ?? undefined,
      grade: s.grade,
      score: s.personalizedScore,
    });
  }

  // "Cleanest %" = A + B products. Matches the client-side donut stat.
  const total = scored.length;
  const cleanestPercent = total === 0
    ? 0
    : Math.round(((distribution.A + distribution.B) / total) * 100);

  const byScoreDesc = [...scored].sort((a, b) => b.score - a.score);
  const topCleanest = byScoreDesc.slice(0, 5);
  const worstProducts = byScoreDesc.slice(-5).reverse();

  const summary: BrandSummary = {
    slug,
    totalProducts: total,
    distribution,
    cleanestPercent,
    topCleanest,
    worstProducts,
    cachedAt: new Date().toISOString(),
  };

  if (redis) {
    try {
      await redis.set(cacheKey(slug), JSON.stringify(summary), 'EX', CACHE_TTL_SEC);
    } catch (err) {
      logger.error({ err: (err as Error).message, event: 'brand-summary-redis-set-failed' }, '[brandSummary] redis set failed');
    }
  }

  return summary;
}

// Expose the SQL slug expression for tests / other services that need to
// join on the same canonical form (e.g. the brand-trends job).
export const BRAND_SLUG_SQL = brandMatchSql;
