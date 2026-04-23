/**
 * SSR contract for GET /p/:barcode. We mock lookupProduct + scoreProduct so
 * the HTML is fully deterministic. Assertions cover:
 *   - 200 status + text/html content-type
 *   - Grade letter present in the page
 *   - Open Graph tags present
 *   - revelio:// deep-link trigger present
 *   - Brand name is escaped — no raw <script> injection
 *   - Missing product → 404 with stable HTML error page
 *   - Invalid barcode → 400
 */

import { describe, it, beforeEach, expect, vi } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';

const { lookupProduct, scoreProduct } = vi.hoisted(() => ({
  lookupProduct: vi.fn(),
  scoreProduct: vi.fn(),
}));

vi.mock('../src/services/productLookup', () => ({
  lookupProduct,
}));
vi.mock('../src/services/scorer', () => ({
  scoreProduct,
  scoreBarcode: vi.fn(),
}));
vi.mock('../src/db', () => ({
  db: { query: vi.fn() },
  ensureAlternativesTable: vi.fn().mockResolvedValue(undefined),
}));

async function makeApp(): Promise<Express> {
  const helpers = await import('./helpers');
  return helpers.buildApp();
}

beforeEach(() => {
  lookupProduct.mockReset();
  scoreProduct.mockReset();
});

describe('GET /p/:barcode — happy path', () => {
  it('200 text/html with grade, OG tags, and deep-link script', async () => {
    lookupProduct.mockResolvedValueOnce({
      barcode: '0123456789012',
      name: 'Test Bar',
      brand: 'ACME',
      category: 'food',
      imageUrl: 'https://img/test.png',
      ingredients: ['water', 'salt'],
    });
    scoreProduct.mockResolvedValueOnce({
      baseScore: 85,
      personalizedScore: 85,
      grade: 'A',
      flags: [
        { ingredient: 'salt', severity: 1, reason: 'high sodium', category: 'x', priorities: [] },
      ],
    });

    const app = await makeApp();
    const res = await request(app).get('/p/0123456789012');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    const body = res.text;
    expect(body).toContain('Grade A');
    expect(body).toContain('og:title');
    expect(body).toContain('og:url');
    expect(body).toContain('og:description');
    expect(body).toContain('twitter:card');
    expect(body).toContain('revelio://scan/0123456789012');
  });

  it('escapes <script> injection from brand name', async () => {
    lookupProduct.mockResolvedValueOnce({
      barcode: '0123456789012',
      name: 'Safe',
      brand: '<script>alert(1)</script>',
      category: 'food',
      ingredients: [],
    });
    scoreProduct.mockResolvedValueOnce({
      baseScore: 100,
      personalizedScore: 100,
      grade: 'A',
      flags: [],
    });

    const app = await makeApp();
    const res = await request(app).get('/p/0123456789012');
    expect(res.status).toBe(200);
    // The tag itself must be escaped (no raw <script>alert).
    expect(res.text).not.toContain('<script>alert(1)</script>');
    expect(res.text).toContain('&lt;script&gt;alert(1)&lt;/script&gt;');
  });
});

describe('GET /p/:barcode — missing / invalid', () => {
  it('404 with HTML when product is not found', async () => {
    lookupProduct.mockResolvedValueOnce(null);
    const app = await makeApp();
    const res = await request(app).get('/p/9999999999999');
    expect(res.status).toBe(404);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    expect(res.text.toLowerCase()).toContain('not found');
  });

  it('400 when barcode is non-numeric', async () => {
    const app = await makeApp();
    const res = await request(app).get('/p/not-a-barcode');
    expect(res.status).toBe(400);
  });
});
