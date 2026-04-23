// Creator payout routes.
//
// All three endpoints are authed via `requireAuth` and pull `userId` from
// `req.user.userId` — the client never tells us whose payouts to look up.
// When Stripe is unconfigured these routes reply 503 so the iOS app can hide
// the feature without crashing.

import { Router, Response } from 'express';
import { requireAuth, AuthRequest } from '../middleware/requireAuth';
import {
  isStripeConfigured,
  createAccountLink,
  syncAccountStatus,
  queuePayout,
} from '../services/stripeConnect';
import { db } from '../db';
import { logger } from '../logger';

export const payoutsRouter = Router();

const MIN_PAYOUT_CENTS = 5000; // $50

function ensureConfigured(res: Response): boolean {
  if (!isStripeConfigured()) {
    res.status(503).json({ error: 'Payouts are temporarily unavailable' });
    return false;
  }
  return true;
}

// ─── POST /payouts/onboarding-link ─────────────────────────────────────────
// Client opens the returned URL in a SFSafariViewController. On dismissal
// the client polls /payouts/status to pick up the fresh Stripe state.
payoutsRouter.post('/onboarding-link', requireAuth, async (req: AuthRequest, res: Response) => {
  if (!ensureConfigured(res)) return;
  const userId = req.user!.userId;
  try {
    const { url } = await createAccountLink(userId);
    return res.json({ url });
  } catch (err: any) {
    logger.error({ event: 'payouts_onboarding_link_failed', err: err?.message });
    return res.status(500).json({ error: 'Could not create onboarding link' });
  }
});

// ─── GET /payouts/status ───────────────────────────────────────────────────
// Round-trips Stripe to refresh `payouts_enabled` + `status`, then sums
// still-queued ledger rows so the dashboard can render a running total.
payoutsRouter.get('/status', requireAuth, async (req: AuthRequest, res: Response) => {
  if (!ensureConfigured(res)) return;
  const userId = req.user!.userId;
  try {
    const { payoutsEnabled, status } = await syncAccountStatus(userId);

    const pending = await db.query(
      `SELECT COALESCE(SUM(amount_cents), 0) AS cents
         FROM creator_payouts
        WHERE user_id = $1 AND status = 'pending'`,
      [userId]
    );
    const pendingCents = parseInt(pending.rows[0].cents, 10) || 0;

    return res.json({ payoutsEnabled, status, pendingCents });
  } catch (err: any) {
    logger.error({ event: 'payouts_status_failed', err: err?.message });
    return res.status(500).json({ error: 'Could not load payout status' });
  }
});

// ─── POST /payouts/request ─────────────────────────────────────────────────
// Creator hits this from the dashboard when they want to withdraw. We compute
// the unpaid balance as lifetime commissions earned minus amounts already
// queued/paid via creator_payouts. Minimum threshold is $50 to keep per-wire
// fees proportionate.
payoutsRouter.post('/request', requireAuth, async (req: AuthRequest, res: Response) => {
  if (!ensureConfigured(res)) return;
  const userId = req.user!.userId;

  try {
    // Stripe is the source of truth for whether the creator can receive funds.
    const acct = await db.query(
      `SELECT payouts_enabled FROM creator_payout_accounts WHERE user_id = $1`,
      [userId]
    );
    if (acct.rows.length === 0 || !acct.rows[0].payouts_enabled) {
      return res.status(400).json({
        error: 'Payouts are not yet enabled. Complete Stripe onboarding first.',
      });
    }

    // Total commissions earned across this creator's referral code(s).
    const earnings = await db.query(
      `SELECT COALESCE(SUM(l.commission_cents), 0) AS cents
         FROM referral_earnings_log l
         JOIN referral_codes c ON c.code = l.referral_code
        WHERE c.user_id = $1`,
      [userId]
    );
    const earnedCents = parseInt(earnings.rows[0].cents, 10) || 0;

    // Amounts already queued or paid out (any status except 'failed').
    const alreadyQueued = await db.query(
      `SELECT COALESCE(SUM(amount_cents), 0) AS cents
         FROM creator_payouts
        WHERE user_id = $1 AND status <> 'failed'`,
      [userId]
    );
    const queuedCents = parseInt(alreadyQueued.rows[0].cents, 10) || 0;

    const availableCents = earnedCents - queuedCents;
    if (availableCents < MIN_PAYOUT_CENTS) {
      return res.status(400).json({
        error: `Minimum payout is $${(MIN_PAYOUT_CENTS / 100).toFixed(0)}. You have $${(availableCents / 100).toFixed(2)} available.`,
        availableCents,
      });
    }

    await queuePayout(userId, availableCents, 'Creator referral commission');
    return res.status(201).json({ queuedCents: availableCents });
  } catch (err: any) {
    logger.error({ event: 'payouts_request_failed', err: err?.message });
    return res.status(500).json({ error: 'Could not queue payout' });
  }
});
