/**
 * IDOR + GDPR tests for /auth/account + /auth/export.
 *
 * DELETE /auth/account must wipe only the caller's rows (cross-user data
 * untouched) and blacklist the access token so the same JWT cannot be
 * reused.
 */

import { describe, it, beforeAll, beforeEach, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { buildApp, hasTestDatabase, makeUser, resetDb } from './helpers';

const describeIfDb = hasTestDatabase() ? describe : describe.skip;

describeIfDb('IDOR — /auth/account + /auth/export', () => {
  let app: Express;

  beforeAll(async () => { app = await buildApp(); });
  beforeEach(async () => { await resetDb(); });

  it('DELETE /auth/account — 401 without JWT', async () => {
    const res = await request(app).delete('/auth/account');
    expect(res.status).toBe(401);
  });

  it('GET /auth/export — 401 without JWT', async () => {
    const res = await request(app).get('/auth/export');
    expect(res.status).toBe(401);
  });

  it('DELETE /auth/account — wipes only caller rows, leaves others untouched', async () => {
    const alice = await makeUser();
    const bob = await makeUser();

    // Seed one pantry item for each — resetDb gives us a clean slate.
    await request(app)
      .post('/pantry')
      .set('Authorization', `Bearer ${alice.token}`)
      .send({ barcode: '0000000000017' });
    await request(app)
      .post('/pantry')
      .set('Authorization', `Bearer ${bob.token}`)
      .send({ barcode: '0000000000018' });

    const del = await request(app)
      .delete('/auth/account')
      .set('Authorization', `Bearer ${alice.token}`);
    expect([200, 204]).toContain(del.status);

    // Alice's token should now be blacklisted.
    const meAfter = await request(app)
      .get('/auth/me')
      .set('Authorization', `Bearer ${alice.token}`);
    expect([401, 404]).toContain(meAfter.status);

    // Bob's pantry is untouched.
    const bobPantry = await request(app)
      .get('/pantry')
      .set('Authorization', `Bearer ${bob.token}`);
    expect(bobPantry.status).toBe(200);
    expect(bobPantry.body.items.length).toBe(1);
  });

  it('GET /auth/export — returns only caller rows', async () => {
    const alice = await makeUser();
    const bob = await makeUser();

    await request(app)
      .post('/pantry')
      .set('Authorization', `Bearer ${alice.token}`)
      .send({ barcode: '0000000000017' });

    const res = await request(app)
      .get('/auth/export')
      .set('Authorization', `Bearer ${bob.token}`);
    expect(res.status).toBe(200);
    // Bob's export must not include Alice's barcode.
    const serialized = JSON.stringify(res.body);
    expect(serialized).not.toContain('0000000000017');
  });
});
