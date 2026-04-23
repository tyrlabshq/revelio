/**
 * /status contract: JSON for API probes, HTML for browsers.
 *
 * We mock db.query so the status route's job-runs lookup returns a clean
 * empty result (the actual table may not be migrated in test envs).
 */

import { describe, it, beforeAll, beforeEach, expect, vi } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';

const { dbQuery } = vi.hoisted(() => ({ dbQuery: vi.fn() }));
vi.mock('../src/db', () => ({
  db: { query: dbQuery },
  ensureAlternativesTable: vi.fn().mockResolvedValue(undefined),
}));

async function makeApp(): Promise<Express> {
  const helpers = await import('./helpers');
  return helpers.buildApp();
}

beforeEach(() => {
  dbQuery.mockReset();
  // Simulate the table-not-migrated path — returns an empty jobs array.
  dbQuery.mockRejectedValue(Object.assign(new Error('relation does not exist'), { code: '42P01' }));
});

describe('GET /status', () => {
  let app: Express;
  beforeAll(async () => { app = await makeApp(); });

  it('JSON by default with ok / startedAt / buildSha / jobs', async () => {
    delete process.env.GIT_SHA;
    const res = await request(app)
      .get('/status')
      .set('Accept', 'application/json');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.startedAt).toBeTruthy();
    expect(res.body.buildSha).toBeNull();
    expect(Array.isArray(res.body.jobs)).toBe(true);
  });

  it('respects GIT_SHA when set', async () => {
    process.env.GIT_SHA = 'abc1234';
    const res = await request(app)
      .get('/status?format=json');
    expect(res.status).toBe(200);
    expect(res.body.buildSha).toBe('abc1234');
    delete process.env.GIT_SHA;
  });

  it('returns HTML when Accept: text/html', async () => {
    const res = await request(app)
      .get('/status')
      .set('Accept', 'text/html');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    expect(res.text).toContain('Revelio API');
  });
});
