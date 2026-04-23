/**
 * Deeper IDOR coverage for /price-alerts — complements price-alerts.test.ts
 * with two end-to-end scenarios:
 *   1. Alice creates an alert; Bob's GET returns an empty list (alerts are
 *      per-user and filtered by req.user.userId in the SELECT).
 *   2. Bob cannot DELETE Alice's alert id — the UPDATE ... WHERE id=$1 AND
 *      user_id=$2 guard forces 404.
 */

import { describe, it, beforeAll, beforeEach, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { buildApp, hasTestDatabase, makeUser, resetDb } from './helpers';

const describeIfDb = hasTestDatabase() ? describe : describe.skip;

describeIfDb('IDOR — /price-alerts (cross-user)', () => {
  let app: Express;

  beforeAll(async () => { app = await buildApp(); });
  beforeEach(async () => { await resetDb(); });

  it('Alice creates an alert; Bob does not see it in GET /price-alerts', async () => {
    const alice = await makeUser();
    const bob = await makeUser();

    const create = await request(app)
      .post('/price-alerts')
      .set('Authorization', `Bearer ${alice.token}`)
      .send({ barcode: '0000000000017', thresholdCents: 1000 });
    expect([200, 201]).toContain(create.status);

    const bobList = await request(app)
      .get('/price-alerts')
      .set('Authorization', `Bearer ${bob.token}`);
    expect(bobList.status).toBe(200);
    expect(bobList.body.data).toEqual([]);

    const aliceList = await request(app)
      .get('/price-alerts')
      .set('Authorization', `Bearer ${alice.token}`);
    expect(aliceList.body.data).toHaveLength(1);
  });

  it('Bob cannot DELETE Alice\'s alert id — returns 404 and leaves the row active', async () => {
    const alice = await makeUser();
    const bob = await makeUser();

    const create = await request(app)
      .post('/price-alerts')
      .set('Authorization', `Bearer ${alice.token}`)
      .send({ barcode: '0000000000019', thresholdPct: 15 });
    const alertId = create.body.id as string;

    const bobDelete = await request(app)
      .delete(`/price-alerts/${alertId}`)
      .set('Authorization', `Bearer ${bob.token}`);
    expect(bobDelete.status).toBe(404);

    // Alice's alert remains active.
    const aliceList = await request(app)
      .get('/price-alerts')
      .set('Authorization', `Bearer ${alice.token}`);
    expect(aliceList.body.data).toHaveLength(1);
    expect(aliceList.body.data[0].active).toBe(true);
  });
});
