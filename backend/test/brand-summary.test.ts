/**
 * Route-layer coverage for /brands/:slug and /brands/:slug/summary.
 *
 * Mocks db.query so these tests stand alone from Postgres. We assert:
 *   - pagination arithmetic (offset = (page-1) * limit)
 *   - grade filter forwarding
 *   - the summary response shape iOS's `BrandSummary` struct reads
 *   - SQL is parameterized — malicious slugs never reach a concatenated query
 */

import { describe, it, beforeEach, expect, vi } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';

const { dbQuery } = vi.hoisted(() => ({ dbQuery: vi.fn() }));
vi.mock('../src/db', () => ({
  db: { query: dbQuery },
  ensureAlternativesTable: vi.fn().mockResolvedValue(undefined),
}));

// Redis — return null so the summary test hits the DB path.
vi.mock('../src/lib/redis', () => ({ getRedis: () => null }));

// `scoreBarcode` is called per-row; stub it to avoid pulling in the full
// scorer + flag loader.
vi.mock('../src/services/scorer', () => ({
  scoreBarcode: vi.fn(async (_barcode: string) => ({
    grade: 'A',
    personalizedScore: 90,
    baseScore: 100,
    flags: [],
  })),
}));

async function makeApp(): Promise<Express> {
  const helpers = await import('./helpers');
  return helpers.buildApp();
}

beforeEach(() => {
  dbQuery.mockReset();
});

describe('GET /brands/:slug — pagination', () => {
  it('computes OFFSET as (page - 1) * limit and forwards to SQL', async () => {
    // listBrandProducts fires two queries in parallel (rows + total). Mock both.
    dbQuery.mockResolvedValue({ rows: [], rowCount: 0 });

    const app = await makeApp();
    await request(app).get('/brands/hellmanns?page=3&limit=10');

    // Grab the rows-query call (first query using LIMIT + OFFSET).
    const rowsCall = dbQuery.mock.calls.find(
      (c) => typeof c[0] === 'string' && c[0].includes('LIMIT')
    );
    expect(rowsCall).toBeDefined();
    // args: [slug, limit, offset]. offset = (3 - 1) * 10 = 20.
    expect(rowsCall![1]).toEqual(['hellmanns', 10, 20]);
  });

  it('defaults to page=1 limit=24 when query params are missing', async () => {
    dbQuery.mockResolvedValue({ rows: [], rowCount: 0 });
    const app = await makeApp();
    await request(app).get('/brands/hellmanns');
    const rowsCall = dbQuery.mock.calls.find(
      (c) => typeof c[0] === 'string' && c[0].includes('LIMIT')
    );
    expect(rowsCall![1]).toEqual(['hellmanns', 24, 0]);
  });

  it('rejects invalid grade filter with 400', async () => {
    const app = await makeApp();
    const res = await request(app).get('/brands/hellmanns?grade=Z');
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'invalid grade' });
  });

  it('grade filter is applied client-side after scoring (not via WHERE)', async () => {
    // This route currently does the grade filter post-scoring, so we only
    // assert that a non-matching grade returns zero products.
    dbQuery.mockResolvedValue({
      rows: [{ barcode: '0000000000017', name: 'x', brand: 'ACME', image_url: null }],
      rowCount: 1,
    });
    // Summary SELECT also gets mocked to the same
    const app = await makeApp();
    const res = await request(app).get('/brands/acme?grade=F'); // scorer returns A → no match
    expect(res.status).toBe(200);
    expect(res.body.products).toEqual([]);
  });
});

describe('GET /brands/:slug — SQL safety', () => {
  it('user-supplied slug text never appears concatenated into the query', async () => {
    dbQuery.mockResolvedValue({ rows: [], rowCount: 0 });
    const app = await makeApp();

    // A hostile slug: URL-encoded quote + SQL tail. The slugifier should
    // strip these to benign chars, but even if it didn't, the raw sequence
    // must never land in the SQL string — it must arrive as a $1 parameter.
    await request(app).get("/brands/%27%20OR%201%3D1%20--");

    for (const call of dbQuery.mock.calls) {
      const sql = call[0] as string;
      expect(sql).not.toContain('OR 1=1');
      expect(sql).not.toContain('--');
    }
    // The SQL template DOES contain `'-'` literals as regex trim args;
    // instead, assert each call's params array contains the (sanitized) slug.
    const paramsCalls = dbQuery.mock.calls.map((c) => c[1]);
    for (const params of paramsCalls) {
      expect(Array.isArray(params)).toBe(true);
      // params[0] is the slug for every query — slugified form has no quotes.
      expect(String(params[0])).not.toContain("'");
      expect(String(params[0])).not.toContain('OR 1=1');
    }
  });

  it('path-traversal slug is sanitized before reaching SQL', async () => {
    dbQuery.mockResolvedValue({ rows: [], rowCount: 0 });
    const app = await makeApp();
    const res = await request(app).get('/brands/..%2F..%2Fetc%2Fpasswd');
    // Sluggified "../../etc/passwd" → "etc-passwd" or similar; either way
    // the response is valid (200) and no raw traversal string hits the DB.
    expect([200, 400]).toContain(res.status);
    for (const call of dbQuery.mock.calls) {
      expect(String(call[1]?.[0] ?? '')).not.toContain('../');
    }
  });

  it('rejects empty slugs with 400', async () => {
    const app = await makeApp();
    // The slugifier reduces `---` to the empty string; route returns 400.
    const res = await request(app).get('/brands/---');
    expect(res.status).toBe(400);
  });
});

describe('GET /brands/:slug/summary — response shape', () => {
  it('response matches BrandSummary Swift struct', async () => {
    // One row so scored summary includes a grade distribution entry.
    dbQuery.mockResolvedValue({
      rows: [
        { barcode: '0000000000017', name: 'Peanut Butter', brand: 'ACME', image_url: null, last_fetched: new Date() },
      ],
      rowCount: 1,
    });

    const app = await makeApp();
    const res = await request(app).get('/brands/acme/summary');
    expect(res.status).toBe(200);
    // Required keys the iOS BrandSummary decoder reads.
    expect(Object.keys(res.body).sort()).toEqual(
      [
        'cachedAt',
        'cleanestPercent',
        'distribution',
        'slug',
        'topCleanest',
        'totalProducts',
        'worstProducts',
      ].sort()
    );
    // Distribution has ALL five grade keys even when some are zero.
    expect(Object.keys(res.body.distribution).sort()).toEqual(['A', 'B', 'C', 'D', 'F']);
    expect(res.body.totalProducts).toBe(1);
    expect(res.body.distribution.A).toBe(1);
    expect(res.body.cleanestPercent).toBe(100);
  });

  it('empty brand → zeroed distribution, cleanestPercent 0', async () => {
    dbQuery.mockResolvedValue({ rows: [], rowCount: 0 });
    const app = await makeApp();
    const res = await request(app).get('/brands/nobody/summary');
    expect(res.status).toBe(200);
    expect(res.body.totalProducts).toBe(0);
    expect(res.body.cleanestPercent).toBe(0);
    expect(res.body.distribution).toEqual({ A: 0, B: 0, C: 0, D: 0, F: 0 });
  });
});
