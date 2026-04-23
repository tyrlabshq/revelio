/**
 * IDOR regression tests for /pantry/*.
 *
 * Pantry routes derive user_id from the JWT — there is no `:id` parameter to
 * spoof, so the cross-user check is implicit: Bob cannot see or delete Alice's
 * items regardless of what he sends, because every query filters by
 * `req.user.userId`. We verify by seeding one user's item and confirming the
 * other user's GET returns an empty list and DELETE returns 404.
 */

import { describe, it, beforeAll, beforeEach, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { buildApp, hasTestDatabase, makeUser, resetDb } from './helpers';

const describeIfDb = hasTestDatabase() ? describe : describe.skip;

describeIfDb('IDOR — /pantry', () => {
  let app: Express;

  beforeAll(async () => {
    app = await buildApp();
  });

  beforeEach(async () => {
    await resetDb();
  });

  it('GET /pantry — 401 without JWT', async () => {
    const res = await request(app).get('/pantry');
    expect(res.status).toBe(401);
  });

  it('POST /pantry — 401 without JWT', async () => {
    const res = await request(app).post('/pantry').send({ barcode: '0000000000017' });
    expect(res.status).toBe(401);
  });

  it('DELETE /pantry/:barcode — 401 without JWT', async () => {
    const res = await request(app).delete('/pantry/0000000000017');
    expect(res.status).toBe(401);
  });

  it('GET /pantry/score — 401 without JWT', async () => {
    const res = await request(app).get('/pantry/score');
    expect(res.status).toBe(401);
  });

  it('cross-user read returns only caller rows', async () => {
    const alice = await makeUser();
    const bob = await makeUser();

    // Alice adds a pantry item.
    const addRes = await request(app)
      .post('/pantry')
      .set('Authorization', `Bearer ${alice.token}`)
      .send({ barcode: '0000000000017' });
    expect([200, 201]).toContain(addRes.status);

    // Bob fetches his (empty) pantry.
    const bobList = await request(app)
      .get('/pantry')
      .set('Authorization', `Bearer ${bob.token}`);
    expect(bobList.status).toBe(200);
    expect(bobList.body.items).toEqual([]);

    // Alice fetches hers — should see the item.
    const aliceList = await request(app)
      .get('/pantry')
      .set('Authorization', `Bearer ${alice.token}`);
    expect(aliceList.status).toBe(200);
    expect(aliceList.body.items.length).toBe(1);
  });

  it('cross-user DELETE returns 404 (cannot delete another user’s item)', async () => {
    const alice = await makeUser();
    const bob = await makeUser();

    await request(app)
      .post('/pantry')
      .set('Authorization', `Bearer ${alice.token}`)
      .send({ barcode: '0000000000017' });

    const bobDel = await request(app)
      .delete('/pantry/0000000000017')
      .set('Authorization', `Bearer ${bob.token}`);
    expect(bobDel.status).toBe(404);

    // Alice's item must still be present.
    const aliceList = await request(app)
      .get('/pantry')
      .set('Authorization', `Bearer ${alice.token}`);
    expect(aliceList.body.items.length).toBe(1);
  });
});
