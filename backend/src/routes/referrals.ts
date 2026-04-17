import { Router, Response } from 'express';
import { db } from '../db';
import { requireAuth, AuthRequest } from '../middleware/auth';

export const referralsRouter = Router();

const COMMISSION_RATE = 0.20; // 20% recurring
const REFERRAL_CODE_RE = /^[A-Z0-9]{3,20}$/;

// ─── POST /referrals/apply ────────────────────────────────────────────────────
referralsRouter.post('/apply', requireAuth, async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;
  const { referral_code } = req.body as { referral_code?: string };

  if (!referral_code || typeof referral_code !== 'string' || !REFERRAL_CODE_RE.test(referral_code)) {
    return res.status(400).json({ error: 'valid referral_code is required' });
  }

  try {
    const codeResult = await db.query(
      `SELECT code, user_id FROM referral_codes WHERE code = $1 AND status = 'approved'`,
      [referral_code]
    );

    if (codeResult.rows.length === 0) {
      return res.status(404).json({ error: 'Referral code not found or not active' });
    }

    const creator = codeResult.rows[0];

    if (creator.user_id === userId) {
      return res.status(400).json({ error: 'Cannot use your own referral code' });
    }

    // Atomic insert: the UNIQUE constraint on referred_user_id prevents any
    // concurrent second apply from slipping through. If the row already
    // exists, ON CONFLICT DO NOTHING leaves it untouched and rowCount is 0.
    const insertResult = await db.query(
      `INSERT INTO referral_attributions (referral_code, referred_user_id, attributed_at)
       VALUES ($1, $2, NOW())
       ON CONFLICT (referred_user_id) DO NOTHING
       RETURNING id, referral_code, referred_user_id, attributed_at`,
      [referral_code, userId]
    );

    if (insertResult.rowCount === 0) {
      return res.status(409).json({ error: 'User already has a referral attribution' });
    }

    return res.status(201).json({
      success: true,
      attribution: insertResult.rows[0],
    });
  } catch (err) {
    console.error('[referrals/apply]', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── GET /referrals/my-stats ──────────────────────────────────────────────────
referralsRouter.get('/my-stats', requireAuth, async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;

  try {
    const codeResult = await db.query(
      `SELECT code, status, total_earnings_cents, pending_payout_cents
       FROM referral_codes WHERE user_id = $1`,
      [userId]
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
          : 'Your creator account is not active',
      });
    }

    const countResult = await db.query(
      `SELECT
         COUNT(*) AS referred_count,
         COUNT(*) FILTER (WHERE is_active_subscriber = true) AS active_subscribers
       FROM referral_attributions
       WHERE referral_code = $1`,
      [creator.code]
    );

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
      monthEarningsCents: parseInt(monthEarnings.rows[0].month_earnings_cents),
    });
  } catch (err) {
    console.error('[referrals/my-stats]', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── POST /referrals/creator-apply ────────────────────────────────────────────
referralsRouter.post('/creator-apply', requireAuth, async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;
  const { follower_count, platform, social_handle } = req.body as {
    follower_count?: unknown;
    platform?: unknown;
    social_handle?: unknown;
  };

  const followerNum = typeof follower_count === 'number'
    ? follower_count
    : typeof follower_count === 'string'
      ? parseInt(follower_count, 10)
      : NaN;
  if (!Number.isFinite(followerNum) || followerNum < 0 || followerNum > 1_000_000_000) {
    return res.status(400).json({ error: 'valid follower_count required' });
  }
  if (typeof platform !== 'string' || !['tiktok', 'instagram', 'youtube', 'x', 'twitter'].includes(platform.toLowerCase())) {
    return res.status(400).json({ error: 'valid platform required' });
  }
  if (typeof social_handle !== 'string' || social_handle.length === 0 || social_handle.length > 40) {
    return res.status(400).json({ error: 'valid social_handle required (1-40 chars)' });
  }

  try {
    const existing = await db.query(
      `SELECT code, status FROM referral_codes WHERE user_id = $1`,
      [userId]
    );

    if (existing.rows.length > 0) {
      return res.status(409).json({
        error: 'Already applied',
        status: existing.rows[0].status,
        code: existing.rows[0].code,
      });
    }

    const baseCode = social_handle.replace(/[^a-zA-Z0-9]/g, '').toUpperCase().slice(0, 12);
    const code = `${baseCode}${Math.floor(Math.random() * 100)}`;

    const autoApprove = followerNum >= 1000;
    const status = autoApprove ? 'approved' : 'pending';

    const result = await db.query(
      `INSERT INTO referral_codes (user_id, code, status, follower_count, platform, social_handle, applied_at, approved_at)
       VALUES ($1, $2, $3, $4, $5, $6, NOW(), $7)
       RETURNING code, status`,
      [
        userId,
        code,
        status,
        followerNum,
        platform.toLowerCase(),
        social_handle,
        autoApprove ? new Date() : null,
      ]
    );

    return res.status(201).json({
      success: true,
      code: result.rows[0].code,
      status: result.rows[0].status,
      shareUrl: autoApprove ? `https://revelio.app/ref/${code}` : null,
      message: autoApprove
        ? `Welcome to the creator program! Your link: revelio.app/ref/${code}`
        : 'Application submitted. We\'ll review and reach out within 48 hours.',
    });
  } catch (err) {
    console.error('[referrals/creator-apply]', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── GET /referrals/payout-history ────────────────────────────────────────────
referralsRouter.get('/payout-history', requireAuth, async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;

  try {
    const codeResult = await db.query(
      `SELECT code FROM referral_codes WHERE user_id = $1 AND status = 'approved'`,
      [userId]
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

// ─── Internal helper: process commission ──────────────────────────────────────
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

  if (attribution.rows.length === 0) return;

  const code = attribution.rows[0].referral_code;

  // Idempotent insert (UNIQUE on revenue_cat_event_id). xmax is 0 on a real
  // insert; non-zero on conflict — we only credit the creator once per event.
  const inserted = await db.query(
    `INSERT INTO referral_earnings_log
       (referral_code, referred_user_id, event_type, gross_cents, commission_cents, revenue_cat_event_id)
     VALUES ($1, $2, $3, $4, $5, $6)
     ON CONFLICT (revenue_cat_event_id) DO NOTHING
     RETURNING id`,
    [code, referredUserId, eventType, grossCents, commissionCents, revenueCatEventId]
  );

  if (inserted.rowCount === 0) return;

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
