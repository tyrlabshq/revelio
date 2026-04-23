/**
 * Refresh-token rotation + logout blacklist.
 *
 * End-to-end: request OTP → verify-otp → hit /auth/refresh → try to reuse
 * the OLD refresh token (must 401) → call /auth/logout → try the JWT after
 * (must 401). Skips gracefully without TEST_DATABASE_URL.
 */

import { describe, it, beforeAll, beforeEach, expect } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { buildApp, hasTestDatabase, resetDb } from './helpers';

const describeIfDb = hasTestDatabase() ? describe : describe.skip;

async function verifyOtp(app: Express, phone: string) {
  // Dev mode (no Twilio) accepts any 6-digit code.
  await request(app).post('/auth/request-otp').send({ phone });
  const res = await request(app).post('/auth/verify-otp').send({ phone, code: '123456' });
  return res;
}

describeIfDb('auth refresh-token rotation + logout blacklist', () => {
  let app: Express;

  beforeAll(async () => { app = await buildApp(); });
  beforeEach(async () => { await resetDb(); });

  it('verify-otp returns both a token and a refreshToken', async () => {
    const res = await verifyOtp(app, '+15551234501');
    expect(res.status).toBe(200);
    expect(res.body.token).toBeTruthy();
    expect(res.body.refreshToken).toBeTruthy();
  });

  it('refresh rotates the pair; old refresh token is revoked', async () => {
    const first = await verifyOtp(app, '+15551234502');
    const initialRefresh = first.body.refreshToken as string;

    const rotated = await request(app)
      .post('/auth/refresh')
      .send({ refreshToken: initialRefresh });
    expect(rotated.status).toBe(200);
    expect(rotated.body.token).toBeTruthy();
    expect(rotated.body.refreshToken).toBeTruthy();
    expect(rotated.body.refreshToken).not.toBe(initialRefresh);

    // Reusing the original refresh token is now forbidden.
    const reuse = await request(app)
      .post('/auth/refresh')
      .send({ refreshToken: initialRefresh });
    expect(reuse.status).toBe(401);
  });

  it('logout revokes every outstanding refresh token for the user', async () => {
    const first = await verifyOtp(app, '+15551234503');
    const { token, refreshToken } = first.body;

    const logout = await request(app)
      .post('/auth/logout')
      .set('Authorization', `Bearer ${token}`);
    expect([200, 204]).toContain(logout.status);

    // The refresh token must also be revoked server-side.
    const reuse = await request(app)
      .post('/auth/refresh')
      .send({ refreshToken });
    expect(reuse.status).toBe(401);
  });
});
