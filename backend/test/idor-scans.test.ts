/**
 * IDOR regression tests for /scans/*.
 *
 * Like pantry, scans routes derive user_id from the JWT (no :id in the path
 * for GET), so cross-user leakage is verified via isolation:
 *   - /scans GET from Bob must not see Alice's scan
 *   - /scans/:id DELETE from Bob with Alice's scan id must return 404
 */

import { describe, it, beforeAll, beforeEach, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { buildApp, hasTestDatabase, makeUser, resetDb } from './helpers';

const describeIfDb = hasTestDatabase() ? describe : describe.skip;

async function seedScan(userId: string, opts: { score?: number; grade?: string } = {}): Promise<string> {
  const { db } = await import('../src/db');
  // `scans` is owned by another migration; create it if missing so the test
  // doesn't 500 on a fresh DB.
  await db.query(`
    CREATE TABLE IF NOT EXISTS scans (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL,
      barcode TEXT,
      product_name TEXT,
      brand TEXT,
      category TEXT,
      image_url TEXT,
      score INTEGER,
      grade TEXT,
      flags JSONB DEFAULT '[]'::jsonb,
      scanned_at TIMESTAMPTZ DEFAULT NOW()
    )
  `);
  const id = uuidv4();
  await db.query(
    `INSERT INTO scans (id, user_id, barcode, product_name, brand, category, score, grade, scanned_at)
       VALUES ($1, $2, '0000000000017', 'Test Product', 'Test Brand', 'food', $3, $4, NOW())`,
    [id, userId, opts.score ?? 50, opts.grade ?? 'C']
  );
  return id;
}

describeIfDb('IDOR — /scans', () => {
  let app: Express;

  beforeAll(async () => {
    app = await buildApp();
  });

  beforeEach(async () => {
    await resetDb();
  });

  it('GET /scans — 401 without JWT', async () => {
    const res = await request(app).get('/scans');
    expect(res.status).toBe(401);
  });

  it('GET /scans/insights — 401 without JWT', async () => {
    const res = await request(app).get('/scans/insights');
    expect(res.status).toBe(401);
  });

  it('DELETE /scans/:id — 401 without JWT', async () => {
    const res = await request(app).delete(`/scans/${uuidv4()}`);
    expect(res.status).toBe(401);
  });

  it('GET /scans returns only caller’s scans', async () => {
    const alice = await makeUser();
    const bob = await makeUser();
    await seedScan(alice.userId);

    const bobRes = await request(app)
      .get('/scans')
      .set('Authorization', `Bearer ${bob.token}`);
    expect(bobRes.status).toBe(200);
    expect(bobRes.body.data).toEqual([]);

    const aliceRes = await request(app)
      .get('/scans')
      .set('Authorization', `Bearer ${alice.token}`);
    expect(aliceRes.status).toBe(200);
    expect(aliceRes.body.data.length).toBe(1);
  });

  it('DELETE /scans/:id with another user’s scan id → 404', async () => {
    const alice = await makeUser();
    const bob = await makeUser();
    const aliceScanId = await seedScan(alice.userId);

    const res = await request(app)
      .delete(`/scans/${aliceScanId}`)
      .set('Authorization', `Bearer ${bob.token}`);
    expect(res.status).toBe(404);

    // Alice's scan must still exist.
    const aliceRes = await request(app)
      .get('/scans')
      .set('Authorization', `Bearer ${alice.token}`);
    expect(aliceRes.body.data.length).toBe(1);
  });
});
