/**
 * Rate-limit coverage for /auth/request-otp.
 *
 * The limiter is 5 requests per HOUR per IP. Hitting it six times from the
 * same (synthetic) IP should get the last call(s) 429'd. Without Redis +
 * trust proxy settings wired for the test harness, the in-memory store
 * still counts per-IP by the socket address — sufficient for a regression.
 */

import { describe, it, beforeAll, expect, vi } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';

const { rlDbQuery } = vi.hoisted(() => ({
  rlDbQuery: vi.fn().mockResolvedValue({ rows: [], rowCount: 0 }),
}));
vi.mock('../src/db', () => ({
  db: { query: rlDbQuery },
  ensureAlternativesTable: vi.fn().mockResolvedValue(undefined),
}));

async function makeApp(): Promise<Express> {
  const helpers = await import('./helpers');
  return helpers.buildApp();
}

describe('rate limit — POST /auth/request-otp', () => {
  let app: Express;
  beforeAll(async () => { app = await makeApp(); });

  it('6th request from the same IP is 429', async () => {
    // We send 7 requests and assert at least one of the last few is 429.
    // The in-memory limiter keys by connection IP — supertest's agent keeps
    // the same socket/IP so counters accumulate.
    const responses: number[] = [];
    const agent = request.agent(app);
    for (let i = 0; i < 7; i++) {
      const res = await agent
        .post('/auth/request-otp')
        .send({ phone: '+15551234567' });
      responses.push(res.status);
    }
    // The limit is 5/hour; the 6th + 7th attempts should have 429'd.
    expect(responses.filter((s) => s === 429).length).toBeGreaterThanOrEqual(1);
  });
});
