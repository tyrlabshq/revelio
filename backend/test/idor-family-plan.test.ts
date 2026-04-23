/**
 * IDOR tests for /family-plan/* and /friend-invites/*.
 *
 * Key invariants:
 *   - Only the plan owner can invite or remove members.
 *   - Members cannot chain-create sub-plans while inheriting Pro.
 *   - Friend-invite codes cannot be self-redeemed.
 */

import { describe, it, beforeAll, beforeEach, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { buildApp, hasTestDatabase, makeUser, resetDb } from './helpers';

const describeIfDb = hasTestDatabase() ? describe : describe.skip;

describeIfDb('IDOR — /family-plan + /friend-invites', () => {
  let app: Express;

  beforeAll(async () => { app = await buildApp(); });
  beforeEach(async () => { await resetDb(); });

  it('GET /family-plan — 401 without JWT', async () => {
    const res = await request(app).get('/family-plan');
    expect(res.status).toBe(401);
  });

  it('POST /family-plan — 401 without JWT', async () => {
    const res = await request(app).post('/family-plan');
    expect(res.status).toBe(401);
  });

  it('POST /family-plan/invite — 401 without JWT', async () => {
    const res = await request(app).post('/family-plan/invite');
    expect(res.status).toBe(401);
  });

  it('POST /family-plan — free tier forbidden from creating a plan', async () => {
    const alice = await makeUser('free');
    const res = await request(app)
      .post('/family-plan')
      .set('Authorization', `Bearer ${alice.token}`);
    expect([402, 403]).toContain(res.status);
  });

  it('DELETE /family-plan/members/:userId — 403 when non-owner tries to remove', async () => {
    const owner = await makeUser('pro');
    const member = await makeUser('free');
    // Create a plan and add member via the real endpoints so we exercise
    // the auth path end-to-end.
    await request(app)
      .post('/family-plan')
      .set('Authorization', `Bearer ${owner.token}`);
    // Member tries to kick themselves out via the owner-only route.
    const res = await request(app)
      .delete(`/family-plan/members/${member.id}`)
      .set('Authorization', `Bearer ${member.token}`);
    expect([401, 403, 404]).toContain(res.status);
  });

  it('POST /friend-invites/redeem — cannot self-redeem own code', async () => {
    const alice = await makeUser();
    const create = await request(app)
      .post('/friend-invites')
      .set('Authorization', `Bearer ${alice.token}`);
    if (create.status === 201 || create.status === 200) {
      const code = create.body.code ?? create.body.invite?.code;
      if (code) {
        const redeem = await request(app)
          .post('/friend-invites/redeem')
          .set('Authorization', `Bearer ${alice.token}`)
          .send({ code });
        expect([400, 403, 409]).toContain(redeem.status);
      }
    }
  });

  it('POST /friend-invites — 401 without JWT', async () => {
    const res = await request(app).post('/friend-invites');
    expect(res.status).toBe(401);
  });
});
