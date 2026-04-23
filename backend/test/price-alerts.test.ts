/**
 * IDOR regression tests for /price-alerts/*.
 *
 * The three endpoints (POST, GET, DELETE) derive user_id from the JWT, so
 * the cross-user check reduces to: (a) no JWT → 401 on all three, and
 * (b) Alice's alert id is invisible to Bob — his DELETE returns 404
 * without affecting Alice's row.
 */

import { describe, it, beforeAll, beforeEach, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { buildApp, hasTestDatabase, makeUser, resetDb } from './helpers';

const describeIfDb = hasTestDatabase() ? describe : describe.skip;

describe('/price-alerts — auth gate', () => {
  let app: Express;

  beforeAll(async () => { app = await buildApp(); });

  it('POST /price-alerts — 401 without JWT', async () => {
    const res = await request(app)
      .post('/price-alerts')
      .send({ barcode: '0000000000017', thresholdCents: 500 });
    expect(res.status).toBe(401);
  });

  it('GET /price-alerts — 401 without JWT', async () => {
    const res = await request(app).get('/price-alerts');
    expect(res.status).toBe(401);
  });

  it('DELETE /price-alerts/:id — 401 without JWT', async () => {
    const res = await request(app).delete(
      '/price-alerts/00000000-0000-0000-0000-000000000000'
    );
    expect(res.status).toBe(401);
  });
});

describeIfDb('IDOR — /price-alerts', () => {
  let app: Express;

  beforeAll(async () => { app = await buildApp(); });
  beforeEach(async () => { await resetDb(); });

  it('Bob cannot soft-delete Alice\'s alert', async () => {
    const alice = await makeUser();
    const bob = await makeUser();

    const createRes = await request(app)
      .post('/price-alerts')
      .set('Authorization', `Bearer ${alice.token}`)
      .send({ barcode: '0000000000017', thresholdPct: 10 });
    expect([200, 201]).toContain(createRes.status);
    const aliceAlertId: string = createRes.body.id;

    // Bob tries to delete by id — 404, Alice's row is untouched.
    const bobDelete = await request(app)
      .delete(`/price-alerts/${aliceAlertId}`)
      .set('Authorization', `Bearer ${bob.token}`);
    expect(bobDelete.status).toBe(404);

    const aliceList = await request(app)
      .get('/price-alerts')
      .set('Authorization', `Bearer ${alice.token}`);
    expect(aliceList.status).toBe(200);
    expect(aliceList.body.data).toHaveLength(1);
    expect(aliceList.body.data[0].id).toBe(aliceAlertId);
  });
});
