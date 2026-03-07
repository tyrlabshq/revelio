import { Router, Request, Response } from 'express';
import { db } from '../db';

export const referralsRouter = Router();

const COMMISSION_RATE = 0.20; // 20% recurring

// ─── POST /referrals/apply ─────────────────────────────────────────────────
// Called during signup when a ref code is present in the URL
referralsRouter.post('/apply', async (req: Request, res: Response) => {
  const { referral_code, user_id } = req.body;

  if (!referral_code || !user_id) {
    return res.status(400).json({ error: 'referral_code and user_id are required' });
  }

  try {
    // Verify code exists and is approved
    const codeResult = await db.query(
      `SELECT code, user_id FROM referral_codes WHERE code = $1 AND status = 'approved'`,
      [referral_code]
    );

    if (codeResult.rows.length === 0) {
      return res.status(404).json({ error: 'Referral code not found or not active' });
    }

    const creator = codeResult.rows[0];

    // Prevent self-referral
    if (creator.user_id === user_id) {
      return res.status(400).json({ error: 'Cannot use your own referral code' });
    }

    // Prevent double attribution
    const existing = await db.query(
      `SELECT id FROM referral_attributions WHERE referred_user_id = $1`,
      [user_id]
    );

    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'User already has a referral attribution' });
    }

    const result = await db.query(
      `INSERT INTO referral_attributions (referral_code, referred_user_id, attributed_at)
       VALUES ($1, $2, NOW())
       RETURNING id, referral_code, referred_user_id, attributed_at`,
      [referral_code, user_id]
    );

    return res.status(201).json({
      success: true,
      attribution: result.rows[0]
    });
  } catch (err) {
    console.error('[referrals/apply]', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── GET /referrals/my-stats ───────────────────────────────────────────────
// Creator dashboard stats — requires authenticated user_id
referralsRouter.get('/my-stats', async (req: Request, res: Response) => {
  const user_id = req.headers['x-user-id'] as string;

  if (!user_id) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  try {
    const codeResult = await db.query(
      `SELECT code, status, total_earnings_cents, pending_payout_cents
       FROM referral_codes WHERE user_id = $1`,
      [user_id]
    );

    if (codeResult.rows.length === 0) {
      return res.status(404).json({ error: 'No referral code found for this user' });
    }

    const creator = codeResult.rows[0];

    if (creator.status !== 'approved') {
      return res.json({
        code: creator.code,
        status: creator.status,
        message: creator.status === 'pending'
          ? 'Your creator application is under review'
          : 'Your creator account is not active'
      });
    }

    // Referral counts
    const countResult = await db.query(
      `SELECT
         COUNT(*) AS referred_count,
         COUNT(*) FILTER (WHERE is_active_subscriber = true) AS active_subscribers
       FROM referral_attributions
       WHERE referral_code = $1`,
      [creator.code]
    );

    // Earnings this month
    const monthEarnings = await db.query(
      `SELECT COALESCE(SUM(commission_cents), 0) AS month_earnings_cents
       FROM referral_earnings_log
       WHERE referral_code = $1
         AND recorded_at >= date_trunc('month', NOW())`,
      [creator.code]
    );

    return res.json({
      code: creator.code,
      shareUrl: `https://revelio.app/ref/${creator.code}`,
      status: creator.status,
      referredCount: parseInt(countResult.rows[0].referred_count),
      activeSubscribers: parseInt(countResult.rows[0].active_subscribers),
      totalEarningsCents: parseInt(creator.total_earnings_cents),
      pendingPayoutCents: parseInt(creator.pending_payout_cents),
      monthEarningsCents: parseInt(monthEarnings.rows[0].month_earnings_cents)
    });
  } catch (err) {
    console.error('[referrals/my-stats]', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── POST /referrals/creator-apply ────────────────────────────────────────
// Creator applies for the program
referralsRouter.post('/creator-apply', async (req: Request, res: Response) => {
  const { user_id, follower_count, platform, social_handle } = req.body;

  if (!user_id || !follower_count || !platform || !social_handle) {
    return res.status(400).json({
      error: 'user_id, follower_count, platform, and social_handle are required'
    });
  }

  try {
    // Check if already applied
    const existing = await db.query(
      `SELECT code, status FROM referral_codes WHERE user_id = $1`,
      [user_id]
    );

    if (existing.rows.length > 0) {
      return res.status(409).json({
        error: 'Already applied',
        status: existing.rows[0].status,
        code: existing.rows[0].code
      });
    }

    // Generate unique codename (handle-based, uppercase, clean)
    const baseCode = social_handle
      .replace(/[^a-zA-Z0-9]/g, '')
      .toUpperCase()
      .slice(0, 12);
    const code = `${baseCode}${Math.floor(Math.random() * 100)}`;

    // Auto-approve if >1K followers (honor system v1)
    const autoApprove = parseInt(follower_count) >= 1000;
    const status = autoApprove ? 'approved' : 'pending';

    const result = await db.query(
      `INSERT INTO referral_codes (user_id, code, status, follower_count, platform, social_handle, applied_at, approved_at)
       VALUES ($1, $2, $3, $4, $5, $6, NOW(), $7)
       RETURNING code, status`,
      [
        user_id,
        code,
        status,
        follower_count,
        platform,
        social_handle,
        autoApprove ? new Date() : null
      ]
    );

    return res.status(201).json({
      success: true,
      code: result.rows[0].code,
      status: result.rows[0].status,
      shareUrl: autoApprove ? `https://revelio.app/ref/${code}` : null,
      message: autoApprove
        ? `Welcome to the creator program! Your link: revelio.app/ref/${code}`
        : 'Application submitted. We\'ll review and reach out within 48 hours.'
    });
  } catch (err) {
    console.error('[referrals/creator-apply]', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── GET /referrals/payout-history ────────────────────────────────────────
referralsRouter.get('/payout-history', async (req: Request, res: Response) => {
  const user_id = req.headers['x-user-id'] as string;

  if (!user_id) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  try {
    const codeResult = await db.query(
      `SELECT code FROM referral_codes WHERE user_id = $1 AND status = 'approved'`,
      [user_id]
    );

    if (codeResult.rows.length === 0) {
      return res.status(404).json({ error: 'No active creator account found' });
    }

    const history = await db.query(
      `SELECT event_type, gross_cents, commission_cents, recorded_at
       FROM referral_earnings_log
       WHERE referral_code = $1
       ORDER BY recorded_at DESC
       LIMIT 50`,
      [codeResult.rows[0].code]
    );

    return res.json({ history: history.rows });
  } catch (err) {
    console.error('[referrals/payout-history]', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Internal helper: process commission ──────────────────────────────────
export async function processReferralCommission(
  referredUserId: string,
  grossCents: number,
  eventType: string,
  revenueCatEventId: string
): Promise<void> {
  const commissionCents = Math.floor(grossCents * COMMISSION_RATE);

  const attribution = await db.query(
    `SELECT referral_code FROM referral_attributions WHERE referred_user_id = $1`,
    [referredUserId]
  );

  if (attribution.rows.length === 0) return; // no referral for this user

  const code = attribution.rows[0].referral_code;

  // Idempotent insert
  await db.query(
    `INSERT INTO referral_earnings_log
       (referral_code, referred_user_id, event_type, gross_cents, commission_cents, revenue_cat_event_id)
     VALUES ($1, $2, $3, $4, $5, $6)
     ON CONFLICT (revenue_cat_event_id) DO NOTHING`,
    [code, referredUserId, eventType, grossCents, commissionCents, revenueCatEventId]
  );

  // Update creator totals + lifetime revenue on attribution
  await db.query(
    `UPDATE referral_codes
     SET total_earnings_cents = total_earnings_cents + $1,
         pending_payout_cents = pending_payout_cents + $1
     WHERE code = $2`,
    [commissionCents, code]
  );

  await db.query(
    `UPDATE referral_attributions
     SET lifetime_revenue_cents = lifetime_revenue_cents + $1,
         is_active_subscriber = TRUE
     WHERE referred_user_id = $2`,
    [grossCents, referredUserId]
  );
}
