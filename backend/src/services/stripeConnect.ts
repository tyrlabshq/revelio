// Stripe Connect service for the creator-payout system.
//
// Responsibilities:
//   - Lazily construct the Stripe client (we never want `import 'stripe'` alone
//     to blow up in dev when STRIPE_SECRET_KEY is unset — we want boot to
//     succeed so developers can work on unrelated routes).
//   - Create Express connected accounts + account onboarding links.
//   - Reconcile our mirror of `payouts_enabled` / `status` against Stripe.
//   - Queue and process creator payouts (Stripe transfers) with local ledger
//     rows flipped to `transferred` / `failed` by id.
//
// Every function in this module throws `Error('Stripe not configured')` when
// the secret is unset. Callers are expected to either gate with
// `isStripeConfigured()` or surface the error (the route layer converts it
// into a 503 so the client sees a clean "not available" response).

import Stripe from 'stripe';
import { db } from '../db';
import { logger } from '../logger';

// The TS types for the default export (`StripeConstructor`) don't re-export
// the rich namespace that lives on `stripe.core`. Re-import it as a type-only
// alias so we can reference `StripeNS.Account` below.
type StripeNS = import('stripe').Stripe;
type StripeAccount = Awaited<ReturnType<StripeNS['accounts']['retrieve']>>;

// ─── Configuration ──────────────────────────────────────────────────────────

// Returns public base URL for constructing onboarding refresh/return URLs.
// The onboarding link redirects the creator back into the app via a universal
// link; until that is wired we fall back to the marketing page.
function publicBaseUrl(): string {
  return process.env.PUBLIC_BASE_URL || 'https://revelio.app';
}

let cachedClient: StripeNS | null = null;

function stripeClient(): StripeNS {
  if (!isStripeConfigured()) {
    throw new Error('Stripe not configured');
  }
  if (!cachedClient) {
    // Default api version matches the installed stripe-node release. Pinning
    // here lets us bump explicitly when we upgrade the dep; `typescript: true`
    // opts into the narrowed response typings.
    cachedClient = new Stripe(process.env.STRIPE_SECRET_KEY as string, {
      typescript: true,
    });
  }
  return cachedClient;
}

/** True when STRIPE_SECRET_KEY is set. Dev boxes can boot without it. */
export function isStripeConfigured(): boolean {
  return !!process.env.STRIPE_SECRET_KEY;
}

/** Test hook: clear the memoised client so `vi.mock('stripe', ...)` re-runs. */
export function __resetStripeClientForTests(): void {
  cachedClient = null;
}

// ─── Account onboarding ─────────────────────────────────────────────────────

/**
 * Create or return a Stripe Express account onboarding link for the given
 * user. On first call we create the Stripe account and insert a local row;
 * subsequent calls reuse the existing account_id.
 */
export async function createAccountLink(userId: string): Promise<{ url: string }> {
  if (!isStripeConfigured()) throw new Error('Stripe not configured');
  const stripe = stripeClient();

  const existing = await db.query(
    `SELECT stripe_account_id FROM creator_payout_accounts WHERE user_id = $1`,
    [userId]
  );

  let stripeAccountId: string;
  if (existing.rows.length === 0) {
    const account = await stripe.accounts.create({ type: 'express' });
    stripeAccountId = account.id;
    await db.query(
      `INSERT INTO creator_payout_accounts (user_id, stripe_account_id, status, payouts_enabled)
       VALUES ($1, $2, 'pending', FALSE)
       ON CONFLICT (user_id) DO UPDATE SET stripe_account_id = EXCLUDED.stripe_account_id`,
      [userId, stripeAccountId]
    );
  } else {
    stripeAccountId = existing.rows[0].stripe_account_id;
  }

  const base = publicBaseUrl();
  const link = await stripe.accountLinks.create({
    account: stripeAccountId,
    refresh_url: `${base}/creator/payouts/refresh`,
    return_url: `${base}/creator/payouts/return`,
    type: 'account_onboarding',
  });

  return { url: link.url };
}

// ─── Status sync ────────────────────────────────────────────────────────────

/**
 * Pull current account state from Stripe and update our mirror. Callers
 * (dashboard GET, webhook handler) use this to keep `payouts_enabled` honest
 * without trusting client-supplied state.
 */
export async function syncAccountStatus(
  userId: string
): Promise<{ payoutsEnabled: boolean; status: string }> {
  if (!isStripeConfigured()) throw new Error('Stripe not configured');
  const stripe = stripeClient();

  const row = await db.query(
    `SELECT stripe_account_id FROM creator_payout_accounts WHERE user_id = $1`,
    [userId]
  );
  if (row.rows.length === 0) {
    return { payoutsEnabled: false, status: 'none' };
  }

  const stripeAccountId: string = row.rows[0].stripe_account_id;
  const account = await stripe.accounts.retrieve(stripeAccountId);

  const payoutsEnabled = !!account.payouts_enabled;
  // We store a coarse status string; Stripe's `requirements.disabled_reason`
  // is richer but this is all the dashboard needs.
  const status = deriveStatus(account);

  await db.query(
    `UPDATE creator_payout_accounts
        SET payouts_enabled = $2, status = $3, updated_at = NOW()
      WHERE user_id = $1`,
    [userId, payoutsEnabled, status]
  );

  return { payoutsEnabled, status };
}

function deriveStatus(account: StripeAccount): string {
  if (account.payouts_enabled && account.charges_enabled) return 'active';
  if (account.details_submitted) return 'pending_verification';
  return 'onboarding';
}

// ─── Payout ledger ──────────────────────────────────────────────────────────

/**
 * Queue a payout row. Does NOT call Stripe — the background job picks rows up
 * in the `pending` state and issues the transfer. Returns the ledger row id
 * so callers can surface it to the client.
 */
export async function queuePayout(
  userId: string,
  amountCents: number,
  description?: string
): Promise<string> {
  if (!isStripeConfigured()) throw new Error('Stripe not configured');
  if (!Number.isInteger(amountCents) || amountCents <= 0) {
    throw new Error('amountCents must be a positive integer');
  }

  const result = await db.query(
    `INSERT INTO creator_payouts (user_id, amount_cents, currency, status, description)
     VALUES ($1, $2, 'usd', 'pending', $3)
     RETURNING id`,
    [userId, amountCents, description ?? null]
  );
  return result.rows[0].id as string;
}

/**
 * Drain every pending payout: for each row, call `stripe.transfers.create`
 * and update the row to `transferred` (with the transfer id) or `failed`.
 *
 * Idempotency: Stripe transfers accept an idempotency key; we use the payout
 * row id so a retried run doesn't double-send.
 */
export async function processPendingPayouts(): Promise<{
  processed: number;
  succeeded: number;
  failed: number;
}> {
  if (!isStripeConfigured()) throw new Error('Stripe not configured');
  const stripe = stripeClient();

  const pending = await db.query(
    `SELECT p.id, p.user_id, p.amount_cents, p.currency, p.description,
            a.stripe_account_id, a.payouts_enabled
       FROM creator_payouts p
       JOIN creator_payout_accounts a ON a.user_id = p.user_id
      WHERE p.status = 'pending'
      ORDER BY p.created_at ASC`
  );

  let succeeded = 0;
  let failed = 0;

  for (const row of pending.rows) {
    const payoutId: string = row.id;
    const destination: string = row.stripe_account_id;
    const amountCents: number = row.amount_cents;
    const currency: string = row.currency || 'usd';

    if (!row.payouts_enabled) {
      await db.query(
        `UPDATE creator_payouts SET status = 'failed', description = COALESCE(description,'') || ' [payouts_disabled]' WHERE id = $1`,
        [payoutId]
      );
      failed++;
      continue;
    }

    try {
      const transfer = await stripe.transfers.create(
        {
          amount: amountCents,
          currency,
          destination,
          description: row.description ?? 'Revelio creator payout',
        },
        { idempotencyKey: `payout:${payoutId}` }
      );

      await db.query(
        `UPDATE creator_payouts
            SET status = 'transferred', stripe_transfer_id = $2
          WHERE id = $1`,
        [payoutId, transfer.id]
      );
      succeeded++;
    } catch (err: any) {
      const message = (err?.message || 'transfer_failed').slice(0, 500);
      await db.query(
        `UPDATE creator_payouts
            SET status = 'failed', description = COALESCE(description,'') || ' [error: ' || $2 || ']'
          WHERE id = $1`,
        [payoutId, message]
      );
      logger.error({ event: 'creator_payout_failed', payoutId, err: message });
      failed++;
    }
  }

  return { processed: pending.rows.length, succeeded, failed };
}
