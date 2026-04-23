/**
 * Unit tests for the four-layer cache in `services/productLookup.ts`:
 *   memory -> redis -> postgres (7 day TTL) -> upstream (OFF/OBF/OPF).
 *
 * All dependencies are mocked. Each test asserts exactly which layers were
 * touched so regressions in cache-order behaviour are caught deterministically.
 */

import { describe, it, beforeEach, afterEach, expect, vi } from 'vitest';

// ─── Mocks (hoisted to run before vi.mock factories execute) ────────────────

const { dbQuery, redisGet, redisSet, getRedisMock, fetchMock } = vi.hoisted(() => ({
  dbQuery: vi.fn(),
  redisGet: vi.fn(),
  redisSet: vi.fn(),
  getRedisMock: vi.fn(),
  fetchMock: vi.fn(),
}));

vi.mock('../src/db', () => ({
  db: { query: dbQuery },
  ensureAlternativesTable: vi.fn().mockResolvedValue(undefined),
}));

vi.mock('../src/lib/redis', () => ({
  getRedis: getRedisMock,
}));

getRedisMock.mockImplementation(() => ({ get: redisGet, set: redisSet }));
vi.stubGlobal('fetch', fetchMock);

import { lookupProduct } from '../src/services/productLookup';

// ─── Helpers ─────────────────────────────────────────────────────────────────

function upstreamOk(raw: Record<string, unknown> = {}) {
  return {
    ok: true,
    status: 200,
    json: async () => ({
      status: 1,
      product: {
        product_name: 'Test',
        brands: 'ACME',
        image_url: 'https://img/x.png',
        ingredients_text: 'water, salt, sugar',
        categories_tags: [],
        nutriments: {},
        ...raw,
      },
    }),
  };
}

// ─── Tests ───────────────────────────────────────────────────────────────────

describe('lookupProduct cache layers', () => {
  beforeEach(() => {
    dbQuery.mockReset();
    redisGet.mockReset();
    redisSet.mockReset();
    fetchMock.mockReset();
    getRedisMock.mockReturnValue({ get: redisGet, set: redisSet });
    // Clear module-level memory cache by re-importing with isolateModules
    // isn't necessary: every test uses a DIFFERENT barcode to avoid
    // cross-test memory bleed.
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('cache miss on all three layers falls through to upstream fetch', async () => {
    // Redis: null. Postgres: empty.
    redisGet.mockResolvedValueOnce(null);
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 }); // SELECT products
    fetchMock.mockResolvedValueOnce(upstreamOk());
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 }); // UPSERT
    redisSet.mockResolvedValue('OK');

    const product = await lookupProduct('0000000001001');
    expect(product?.name).toBe('Test');
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(redisSet).toHaveBeenCalled(); // populated for next time
  });

  it('memory hit returns without touching Redis, Postgres, or network', async () => {
    // Prime the memory cache via a first call.
    redisGet.mockResolvedValueOnce(null);
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 });
    fetchMock.mockResolvedValueOnce(upstreamOk());
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 });
    await lookupProduct('0000000001002');

    // Second call on the same barcode: memory hit, no further mocks needed.
    redisGet.mockClear();
    dbQuery.mockClear();
    fetchMock.mockClear();

    const again = await lookupProduct('0000000001002');
    expect(again?.name).toBe('Test');
    expect(redisGet).not.toHaveBeenCalled();
    expect(dbQuery).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('Redis hit returns immediately and does NOT query Postgres / upstream', async () => {
    redisGet.mockResolvedValueOnce(
      JSON.stringify({
        barcode: '0000000001003',
        name: 'Cached',
        brand: 'Redis',
        category: 'food',
        ingredients: ['water'],
      })
    );

    const product = await lookupProduct('0000000001003');
    expect(product?.name).toBe('Cached');
    expect(dbQuery).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('bypassCache: true skips memory, Redis, and Postgres layers', async () => {
    // Seed memory + pretend Redis + Postgres would hit.
    redisGet.mockResolvedValueOnce(null);
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 });
    fetchMock.mockResolvedValueOnce(upstreamOk());
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 });
    await lookupProduct('0000000001004');

    redisGet.mockClear();
    dbQuery.mockClear();
    fetchMock.mockReset();
    // For the bypass call, only the UPSERT + fresh fetch should be touched.
    fetchMock.mockResolvedValueOnce(upstreamOk({ product_name: 'Fresh' }));
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 }); // UPSERT

    const product = await lookupProduct('0000000001004', { bypassCache: true });
    expect(product?.name).toBe('Fresh');
    expect(redisGet).not.toHaveBeenCalled(); // Redis skipped
    // Postgres is only UPSERTed, never SELECTed on bypass.
    expect(dbQuery).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('stale Postgres row (> 7 days) falls through to upstream', async () => {
    const eightDaysAgo = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000);
    redisGet.mockResolvedValueOnce(null);
    dbQuery.mockResolvedValueOnce({
      rows: [
        {
          barcode: '0000000001005',
          name: 'Stale',
          brand: 'Old',
          category: 'food',
          image_url: null,
          ingredients: JSON.stringify(['water']),
          off_data: {},
          nutri_score_grade: null,
          nova_group: null,
          ecoscore_grade: null,
          last_fetched: eightDaysAgo,
        },
      ],
      rowCount: 1,
    });
    fetchMock.mockResolvedValueOnce(upstreamOk({ product_name: 'Refreshed' }));
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 }); // UPSERT

    const product = await lookupProduct('0000000001005');
    expect(product?.name).toBe('Refreshed');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('fresh Postgres row (< 7 days) is hydrated without upstream fetch', async () => {
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    redisGet.mockResolvedValueOnce(null);
    dbQuery.mockResolvedValueOnce({
      rows: [
        {
          barcode: '0000000001006',
          name: 'Fresh DB',
          brand: 'db',
          category: 'food',
          image_url: null,
          ingredients: JSON.stringify(['water']),
          off_data: {},
          nutri_score_grade: null,
          nova_group: null,
          ecoscore_grade: null,
          last_fetched: oneHourAgo,
        },
      ],
      rowCount: 1,
    });
    redisSet.mockResolvedValue('OK');

    const product = await lookupProduct('0000000001006');
    expect(product?.name).toBe('Fresh DB');
    expect(fetchMock).not.toHaveBeenCalled();
    expect(redisSet).toHaveBeenCalled();
  });
});
