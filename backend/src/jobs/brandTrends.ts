// Daily brand-trends aggregation.
//
// Rolls the last 7 days of `scans` into one row per (brand_slug, week_start)
// in `brand_trends`. The iOS deep-dive view consumes these rows to render a
// 12-week sparkline under the summary header — the aggregate is cheap to
// recompute nightly but prohibitively expensive to recompute on every
// /brands/:slug request, so we persist it.
//
// Scheduling lives in jobs/scheduler.ts (daily at 16:00 UTC). The function
// is deterministic: running it twice in the same UTC day just overwrites
// the same week's row with the latest averages, so the scheduler's
// utcDayKey dedup is a defence-in-depth rather than a correctness
// requirement.

import { db } from '../db';
import { logger } from '../logger';
import { slugifyBrand } from '../services/brandSummary';

export interface BrandTrendRow {
  brand_slug: string;
  avg_score: number;
  scan_count: number;
}

/** Monday 00:00 UTC of the ISO week that contains `d`. */
function weekStartUtc(d: Date): Date {
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dayNum = date.getUTCDay() || 7; // Sun=0 → treat as 7 so Mon is the week boundary
  date.setUTCDate(date.getUTCDate() - (dayNum - 1));
  return date;
}

/**
 * Aggregate the last 7 days of scans by brand (joined through the `products`
 * cache since `scans` stores barcode only) and upsert one row per brand.
 *
 * Returns the rows written so the scheduler can log cardinality and tests
 * can assert against a deterministic shape.
 */
export async function updateBrandTrends(
  asOf: Date = new Date()
): Promise<BrandTrendRow[]> {
  const weekStart = weekStartUtc(asOf);
  const weekStartIso = weekStart.toISOString().slice(0, 10);

  // Aggregate raw brand strings — we slugify in JS below so we don't rely
  // on Postgres' regex dialect matching the TS slugifier byte-for-byte. The
  // JS slugifier is the source of truth (shared with brandSummary).
  const { rows } = await db.query<{ brand: string | null; avg_score: string; scan_count: string }>(
    `SELECT p.brand AS brand,
            AVG(s.score)::numeric(5,2) AS avg_score,
            COUNT(*)::int AS scan_count
       FROM scans s
       JOIN products p ON p.barcode = s.barcode
      WHERE s.scanned_at >= $1
        AND s.score IS NOT NULL
        AND p.brand IS NOT NULL
        AND p.brand <> ''
      GROUP BY p.brand`,
    [weekStart]
  );

  // Fold by slug — OFF stores "Hellmann's" and "HELLMANNS" as distinct rows
  // but they should aggregate into one trend series. We combine the
  // per-raw-brand averages as a count-weighted mean.
  const folded = new Map<string, { sum: number; count: number }>();
  for (const r of rows) {
    const slug = slugifyBrand(r.brand ?? '');
    if (!slug) continue; // skip rows whose brand slugifies to empty (edge case: punctuation-only)
    const avg = Number(r.avg_score);
    const count = Number(r.scan_count);
    const entry = folded.get(slug);
    if (entry) {
      entry.sum += avg * count;
      entry.count += count;
    } else {
      folded.set(slug, { sum: avg * count, count });
    }
  }

  const written: BrandTrendRow[] = [];
  for (const [slug, { sum, count }] of folded.entries()) {
    const avgScore = Number((sum / count).toFixed(2));
    await db.query(
      `INSERT INTO brand_trends (brand_slug, week_start, avg_score, scan_count)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (brand_slug, week_start)
       DO UPDATE SET avg_score = EXCLUDED.avg_score,
                     scan_count = EXCLUDED.scan_count,
                     updated_at = NOW()`,
      [slug, weekStartIso, avgScore, count]
    );
    written.push({ brand_slug: slug, avg_score: avgScore, scan_count: count });
  }

  logger.info(
    { weekStart: weekStartIso, brands: written.length },
    '[brandTrends] upserted weekly averages'
  );
  return written;
}
