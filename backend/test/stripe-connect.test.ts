/**
 * Unit + HTTP coverage for the Stripe Connect creator-payout surface.
 *
 * Strategy: mock `stripe` (the npm package) end-to-end via `vi.mock` so the
 * tests never touch the network and never require a live Stripe key. The DB
 * layer is mocked too so the service-level assertions run without a live
 * Postgres. The HTTP-layer block uses supertest + the shared buildApp() and
 * SKIPS gracefully when no TEST_DATABASE_URL is wired.
 */

import { describe, it, beforeEach, afterEach, expect, vi } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';

// ─── Hoisted mocks ───────────────────────────────────────────────────────────
// vi.mock factories are hoisted above top-level imports by vitest. To keep
// hand-held references to each spy (so tests can stub per-case) we declare
// them via vi.hoisted() so they ALSO get hoisted.

const {
  accountsCreate,
  accountLinksCreate,
  accountsRetrieve,
  transfersCreate,
  webhooksConstructEvent,
  dbQuery,
} = vi.hoisted(() => ({
  accountsCreate: vi.fn(),
  accountLinksCreate: vi.fn(),
  accountsRetrieve: vi.fn(),
  transfersCreate: vi.fn(),
  webhooksConstructEvent: vi.fn(),
  dbQuery: vi.fn(),
}));

vi.mock('stripe', () => {
  const instance = {
    accounts: {
      create: accountsCreate,
      retrieve: accountsRetrieve,
    },
    accountLinks: {
      create: accountLinksCreate,
    },
    transfers: {
      create: transfersCreate,
    },
    webhooks: {
      constructEvent: webhooksConstructEvent,
    },
  };
  const Stripe: any = vi.fn(() => instance);
  return { default: Stripe, Stripe };
});

vi.mock('../src/db', () => ({
  db: { query: dbQuery },
  ensureAlternativesTable: vi.fn().mockResolvedValue(undefined),
}));

// Module under test — imported AFTER the mocks are registered.
import {
  isStripeConfigured,
  createAccountLink,
  queuePayout,
  processPendingPayouts,
  __resetStripeClientForTests,
} from '../src/services/stripeConnect';

// ─── Service-level unit tests ────────────────────────────────────────────────

describe('stripeConnect service', () => {
  beforeEach(() => {
    dbQuery.mockReset();
    accountsCreate.mockReset();
    accountLinksCreate.mockReset();
    accountsRetrieve.mockReset();
    transfersCreate.mockReset();
    webhooksConstructEvent.mockReset();
    __resetStripeClientForTests();
    delete process.env.STRIPE_SECRET_KEY;
    delete process.env.STRIPE_WEBHOOK_SECRET;
  });

  it('isStripeConfigured → false when STRIPE_SECRET_KEY unset', () => {
    expect(isStripeConfigured()).toBe(false);
  });

  it('isStripeConfigured → true when STRIPE_SECRET_KEY is set', () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    expect(isStripeConfigured()).toBe(true);
  });

  it('createAccountLink creates a Stripe account on first call and inserts the row', async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    // 1st db.query: SELECT returns empty → no existing row.
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 });
    // 2nd db.query: INSERT.
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 });
    accountsCreate.mockResolvedValueOnce({ id: 'acct_new_123' });
    accountLinksCreate.mockResolvedValueOnce({ url: 'https://stripe.com/onboard/xyz' });

    const result = await createAccountLink('user-1');
    expect(result).toEqual({ url: 'https://stripe.com/onboard/xyz' });
    expect(accountsCreate).toHaveBeenCalledTimes(1);
    expect(accountsCreate).toHaveBeenCalledWith({ type: 'express' });
    // The INSERT should have persisted the new account id.
    expect(dbQuery.mock.calls[1][1]).toEqual(['user-1', 'acct_new_123']);
  });

  it('createAccountLink reuses an existing stripe_account_id on subsequent calls', async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    dbQuery.mockResolvedValueOnce({
      rows: [{ stripe_account_id: 'acct_existing' }],
      rowCount: 1,
    });
    accountLinksCreate.mockResolvedValueOnce({ url: 'https://stripe.com/onboard/abc' });

    const result = await createAccountLink('user-1');
    expect(result.url).toBe('https://stripe.com/onboard/abc');
    expect(accountsCreate).not.toHaveBeenCalled();
    expect(accountLinksCreate).toHaveBeenCalledWith(
      expect.objectContaining({ account: 'acct_existing', type: 'account_onboarding' })
    );
  });

  it('queuePayout inserts a pending row and returns the generated id', async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    dbQuery.mockResolvedValueOnce({ rows: [{ id: 'payout-uuid' }], rowCount: 1 });
    const id = await queuePayout('user-1', 7500, 'First payout');
    expect(id).toBe('payout-uuid');
    // Verify the INSERT parameters (no concatenation, all parameterized).
    expect(dbQuery.mock.calls[0][1]).toEqual(['user-1', 7500, 'First payout']);
  });

  it('queuePayout rejects non-positive amounts', async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    await expect(queuePayout('user-1', 0)).rejects.toThrow(/positive integer/);
    await expect(queuePayout('user-1', -100)).rejects.toThrow(/positive integer/);
    await expect(queuePayout('user-1', 1.5)).rejects.toThrow(/positive integer/);
  });

  it('queuePayout refuses when Stripe is not configured', async () => {
    await expect(queuePayout('user-1', 5000)).rejects.toThrow(/Stripe not configured/);
  });

  it('processPendingPayouts marks rows as transferred on success and failed on throw', async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    // 1st query: SELECT pending rows (two of them).
    dbQuery.mockResolvedValueOnce({
      rows: [
        {
          id: 'p1',
          user_id: 'u1',
          amount_cents: 5000,
          currency: 'usd',
          description: 'row-1',
          stripe_account_id: 'acct_ok',
          payouts_enabled: true,
        },
        {
          id: 'p2',
          user_id: 'u2',
          amount_cents: 6000,
          currency: 'usd',
          description: 'row-2',
          stripe_account_id: 'acct_bad',
          payouts_enabled: true,
        },
      ],
      rowCount: 2,
    });
    // p1 succeeds; p2 throws.
    transfersCreate
      .mockResolvedValueOnce({ id: 'tr_1' })
      .mockRejectedValueOnce(new Error('bank declined'));
    // UPDATE for p1, UPDATE for p2 — exact rows don't matter to us.
    dbQuery.mockResolvedValue({ rows: [], rowCount: 1 });

    const summary = await processPendingPayouts();
    expect(summary).toEqual({ processed: 2, succeeded: 1, failed: 1 });
    expect(transfersCreate).toHaveBeenCalledTimes(2);
    expect(transfersCreate.mock.calls[0][1]).toEqual({ idempotencyKey: 'payout:p1' });
  });

  it('processPendingPayouts skips accounts without payouts_enabled', async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    dbQuery.mockResolvedValueOnce({
      rows: [
        {
          id: 'p-disabled',
          user_id: 'u1',
          amount_cents: 5000,
          currency: 'usd',
          description: null,
          stripe_account_id: 'acct_disabled',
          payouts_enabled: false,
        },
      ],
      rowCount: 1,
    });
    dbQuery.mockResolvedValue({ rows: [], rowCount: 1 });

    const summary = await processPendingPayouts();
    expect(summary).toEqual({ processed: 1, succeeded: 0, failed: 1 });
    // We should never have even tried to create the transfer.
    expect(transfersCreate).not.toHaveBeenCalled();
  });
});

// ─── HTTP-layer tests (routes/payouts + routes/stripe-webhook) ───────────────
// These don't require the DB for the 401 / 503 paths. Happy-path cases are
// guarded by mocking the DB at the module level above.

describe('POST /payouts/onboarding-link — route layer', () => {
  let app: Express;
  let makeUser: typeof import('./helpers').makeUser;
  let hasTestDatabase: typeof import('./helpers').hasTestDatabase;

  beforeEach(async () => {
    dbQuery.mockReset();
    accountsCreate.mockReset();
    accountLinksCreate.mockReset();
    // Restore the un-mocked helpers module for buildApp (which imports the
    // real routes). Vi's isolation means the /src/db mock from earlier is
    // already in place for both modules under test.
    const helpers = await import('./helpers');
    makeUser = helpers.makeUser;
    hasTestDatabase = helpers.hasTestDatabase;
    app = await helpers.buildApp();
    __resetStripeClientForTests();
  });

  afterEach(() => {
    delete process.env.STRIPE_SECRET_KEY;
  });

  it('401 without JWT', async () => {
    const res = await request(app).post('/payouts/onboarding-link');
    expect(res.status).toBe(401);
  });

  it('503 when Stripe is not configured', async () => {
    if (!hasTestDatabase()) return; // need a user / JWT — skip without DB
    const user = await makeUser();
    const res = await request(app)
      .post('/payouts/onboarding-link')
      .set('Authorization', `Bearer ${user.token}`);
    expect(res.status).toBe(503);
    expect(res.body).toEqual({ error: 'Payouts are temporarily unavailable' });
  });

  it('200 with onboarding url when Stripe succeeds', async () => {
    if (!hasTestDatabase()) return; // need a real user row to sign a JWT
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    // The production db is mocked at module level (dbQuery) so the INSERT
    // / SELECT the service does won't actually hit Postgres.
    const user = await makeUser();
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 });
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 });
    accountsCreate.mockResolvedValueOnce({ id: 'acct_new' });
    accountLinksCreate.mockResolvedValueOnce({ url: 'https://stripe.onboard/ok' });

    const res = await request(app)
      .post('/payouts/onboarding-link')
      .set('Authorization', `Bearer ${user.token}`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ url: 'https://stripe.onboard/ok' });
  });
});

describe('POST /webhooks/stripe — signature + dispatch', () => {
  let app: Express;

  beforeEach(async () => {
    dbQuery.mockReset();
    webhooksConstructEvent.mockReset();
    accountsRetrieve.mockReset();
    const helpers = await import('./helpers');
    app = await helpers.buildApp();
    __resetStripeClientForTests();
  });

  afterEach(() => {
    delete process.env.STRIPE_SECRET_KEY;
    delete process.env.STRIPE_WEBHOOK_SECRET;
  });

  it('400 on bad signature', async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test';
    webhooksConstructEvent.mockImplementationOnce(() => {
      throw new Error('signature mismatch');
    });
    const res = await request(app)
      .post('/webhooks/stripe')
      .set('stripe-signature', 'v1=bogus')
      .set('Content-Type', 'application/json')
      .send('{"type":"account.updated"}');
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: 'Invalid signature' });
  });

  it('400 when stripe-signature header missing', async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test';
    const res = await request(app)
      .post('/webhooks/stripe')
      .set('Content-Type', 'application/json')
      .send('{}');
    expect(res.status).toBe(400);
  });

  it('200 on unhandled event type (ignored)', async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test';
    webhooksConstructEvent.mockReturnValueOnce({
      type: 'invoice.created',
      data: { object: {} },
    });
    const res = await request(app)
      .post('/webhooks/stripe')
      .set('stripe-signature', 'v1=ok')
      .set('Content-Type', 'application/json')
      .send('{"type":"invoice.created"}');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ received: true });
  });

  it('200 on account.updated syncs mirror', async () => {
    process.env.STRIPE_SECRET_KEY = 'sk_test_x';
    process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test';
    webhooksConstructEvent.mockReturnValueOnce({
      type: 'account.updated',
      data: { object: { id: 'acct_abc' } },
    });
    // First SELECT: find the mirror row. Second UPDATE inside syncAccountStatus.
    dbQuery.mockResolvedValueOnce({ rows: [{ user_id: 'u1' }], rowCount: 1 });
    dbQuery.mockResolvedValueOnce({ rows: [{ stripe_account_id: 'acct_abc' }], rowCount: 1 });
    accountsRetrieve.mockResolvedValueOnce({
      payouts_enabled: true,
      charges_enabled: true,
      details_submitted: true,
    });
    dbQuery.mockResolvedValueOnce({ rows: [], rowCount: 1 });

    const res = await request(app)
      .post('/webhooks/stripe')
      .set('stripe-signature', 'v1=ok')
      .set('Content-Type', 'application/json')
      .send('{"type":"account.updated"}');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ received: true });
  });

  it('200 when webhook arrives with no STRIPE_WEBHOOK_SECRET configured (logs + ignores)', async () => {
    delete process.env.STRIPE_SECRET_KEY;
    delete process.env.STRIPE_WEBHOOK_SECRET;
    const res = await request(app)
      .post('/webhooks/stripe')
      .set('stripe-signature', 'v1=ok')
      .set('Content-Type', 'application/json')
      .send('{}');
    expect(res.status).toBe(200);
  });
});
