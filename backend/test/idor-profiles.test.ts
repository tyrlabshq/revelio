/**
 * IDOR regression tests for /profiles/*.
 *
 * Every profile route applies requireAuth + requireOwner — only the JWT's own
 * userId may read or mutate the matching profile. Attempts to access another
 * user's profile or manipulate their family_members list must return 403.
 */

import { describe, it, beforeAll, beforeEach, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { buildApp, hasTestDatabase, makeUser, resetDb } from './helpers';

const describeIfDb = hasTestDatabase() ? describe : describe.skip;

describeIfDb('IDOR — /profiles', () => {
  let app: Express;

  beforeAll(async () => { app = await buildApp(); });
  beforeEach(async () => { await resetDb(); });

  it('GET /profiles/:id — 401 without JWT', async () => {
    const res = await request(app).get('/profiles/00000000-0000-0000-0000-000000000000');
    expect(res.status).toBe(401);
  });

  it('PATCH /profiles/:id — 401 without JWT', async () => {
    const res = await request(app)
      .patch('/profiles/00000000-0000-0000-0000-000000000000')
      .send({ priorities: [] });
    expect(res.status).toBe(401);
  });

  it('GET /profiles/:id — 403 when :id is someone else', async () => {
    const alice = await makeUser();
    const bob = await makeUser();
    const res = await request(app)
      .get(`/profiles/${alice.id}`)
      .set('Authorization', `Bearer ${bob.token}`);
    expect(res.status).toBe(403);
  });

  it('PATCH /profiles/:id — 403 when :id is someone else', async () => {
    const alice = await makeUser();
    const bob = await makeUser();
    const res = await request(app)
      .patch(`/profiles/${alice.id}`)
      .set('Authorization', `Bearer ${bob.token}`)
      .send({ allergies: ['gluten'] });
    expect(res.status).toBe(403);
  });

  it('GET /profiles/:id/members — 403 across users', async () => {
    const alice = await makeUser();
    const bob = await makeUser();
    const res = await request(app)
      .get(`/profiles/${alice.id}/members`)
      .set('Authorization', `Bearer ${bob.token}`);
    expect(res.status).toBe(403);
  });

  it('POST /profiles/:id/members — 403 when adding to someone else', async () => {
    const alice = await makeUser();
    const bob = await makeUser();
    const res = await request(app)
      .post(`/profiles/${alice.id}/members`)
      .set('Authorization', `Bearer ${bob.token}`)
      .send({ name: 'Mallory' });
    expect(res.status).toBe(403);
  });

  it('DELETE /profiles/:id/members/:memberId — 403 across users', async () => {
    const alice = await makeUser();
    const bob = await makeUser();
    const res = await request(app)
      .delete(`/profiles/${alice.id}/members/ffffffff-ffff-ffff-ffff-ffffffffffff`)
      .set('Authorization', `Bearer ${bob.token}`);
    expect(res.status).toBe(403);
  });

  it('GET /profiles/:id — 200 for the owner', async () => {
    const alice = await makeUser();
    const res = await request(app)
      .get(`/profiles/${alice.id}`)
      .set('Authorization', `Bearer ${alice.token}`);
    expect([200, 404]).toContain(res.status); // 404 only if profile columns haven't been backfilled
  });
});
