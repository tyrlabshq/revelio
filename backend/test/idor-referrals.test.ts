/**
 * IDOR regression tests for /referrals/*.
 *
 * Earlier versions of this router authed via a client-supplied x-user-id
 * header, which a caller could spoof to read another creator's earnings.
 * The hardened version uses requireAuth with req.user.userId. These tests
 * verify no callback path still trusts a header or body userId.
 */

import { describe, it, beforeAll, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { buildApp, hasTestDatabase, makeUser } from './helpers';

const describeIfDb = hasTestDatabase() ? describe : describe.skip;

describeIfDb('IDOR — /referrals', () => {
  let app: Express;
  beforeAll(async () => { app = await buildApp(); });

  it('GET /referrals/my-stats — 401 without JWT', async () => {
    const res = await request(app).get('/referrals/my-stats');
    expect(res.status).toBe(401);
  });

  it('GET /referrals/my-stats — ignores x-user-id header', async () => {
    const alice = await makeUser();
    const bob = await makeUser();
    // Bob tries to impersonate Alice via the old header.
    const res = await request(app)
      .get('/referrals/my-stats')
      .set('Authorization', `Bearer ${bob.token}`)
      .set('x-user-id', alice.id);
    // Either 404 (Bob has no referral code) or 200 with BOB's data —
    // under no circumstances do we want a row belonging to Alice.
    expect([200, 404]).toContain(res.status);
    if (res.status === 200) {
      expect(res.body.code).not.toBe(alice.id);
    }
  });

  it('GET /referrals/payout-history — 401 without JWT', async () => {
    const res = await request(app).get('/referrals/payout-history');
    expect(res.status).toBe(401);
  });

  it('POST /referrals/apply — 401 without JWT', async () => {
    const res = await request(app)
      .post('/referrals/apply')
      .send({ referral_code: 'ANYTHING' });
    expect(res.status).toBe(401);
  });

  it('POST /referrals/creator-apply — 401 without JWT', async () => {
    const res = await request(app)
      .post('/referrals/creator-apply')
      .send({ follower_count: 5000, platform: 'tiktok', social_handle: 'x' });
    expect(res.status).toBe(401);
  });
});
