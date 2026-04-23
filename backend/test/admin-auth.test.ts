/**
 * Admin gating: GET /admin and friends require requireAuth + requireAdmin.
 *
 * We exercise both guards:
 *   1. No JWT → 401 (requireAuth)
 *   2. Valid JWT for a regular user → 403 (requireAdmin)
 *   3. Valid JWT for a user with is_admin=true → 200 HTML
 *
 * The last case requires a DB to flip is_admin; we skip it without one. The
 * 401/403 cases are DB-free because the admin router errors out long
 * before hitting the dashboard data queries.
 */

import { describe, it, beforeAll, expect, vi } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';

// The 401/403 paths don't need the DB, but requireAdmin DOES run a SELECT
// to check is_admin. Stub the db module so that SELECT returns an empty row
// set — which the middleware reads as "not admin" → 403.
const { dbQueryMock } = vi.hoisted(() => ({
  dbQueryMock: vi.fn().mockResolvedValue({ rows: [], rowCount: 0 }),
}));
vi.mock('../src/db', () => ({
  db: { query: dbQueryMock },
  ensureAlternativesTable: vi.fn().mockResolvedValue(undefined),
}));

async function makeApp(): Promise<Express> {
  const helpers = await import('./helpers');
  return helpers.buildApp();
}

function signJwt(userId: string, phone: string = '+15550000001'): string {
  // Re-sign here (rather than calling helpers.makeUser) because we don't
  // want a DB round-trip — the mock above intercepts db.query.
  const jwt = require('jsonwebtoken');
  return jwt.sign(
    { userId, phone, tier: 'free', jti: 'test-jti' },
    process.env.JWT_SECRET!,
    { expiresIn: '15m' }
  );
}

describe('admin auth gating', () => {
  let app: Express;
  beforeAll(async () => { app = await makeApp(); });

  it('GET /admin — 401 without JWT', async () => {
    const res = await request(app).get('/admin');
    expect(res.status).toBe(401);
  });

  it('GET /admin — 403 for a non-admin user', async () => {
    const token = signJwt('00000000-0000-0000-0000-000000000001');
    const res = await request(app)
      .get('/admin')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
  });

  it('POST /admin/contributions/:id/approve — 401 without JWT', async () => {
    const res = await request(app).post('/admin/contributions/00000000-0000-0000-0000-000000000000/approve');
    expect(res.status).toBe(401);
  });

  it('POST /admin/contributions/:id/reject — 403 for non-admin user', async () => {
    const token = signJwt('00000000-0000-0000-0000-000000000002');
    const res = await request(app)
      .post('/admin/contributions/00000000-0000-0000-0000-000000000000/reject')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
  });

  it('GET /admin — 200 HTML for an is_admin=true user', async () => {
    // Flip the SELECT is_admin mock to return { is_admin: true } for the
    // first requireAdmin call, then return empty rows for every downstream
    // query collectSystemMetrics + friends make.
    dbQueryMock.mockReset();
    dbQueryMock.mockImplementation(async (sql: string) => {
      if (typeof sql === 'string' && sql.includes('is_admin')) {
        return { rows: [{ is_admin: true }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    });

    const token = signJwt('00000000-0000-0000-0000-000000000003');
    const res = await request(app)
      .get('/admin')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    expect(res.text).toContain('Admin dashboard');
  });
});
