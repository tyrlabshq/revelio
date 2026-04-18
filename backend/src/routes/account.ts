import { Router, Response } from 'express';
import { db } from '../db';
import { logger } from '../logger';
import { requireAuth, AuthRequest } from '../middleware/requireAuth';
import { getRedis } from '../middleware/rateLimit';

/**
 * GDPR surface. Two endpoints:
 *   - DELETE /auth/account  → hard-delete every row owned by the user.
 *   - GET    /auth/export   → JSON dump of every row owned by the user.
 *
 * Both require auth; the router is mounted at /auth in index.ts so the public
 * paths end up as documented.
 */
export const accountRouter = Router();

// ─── DELETE /auth/account ─────────────────────────────────────────────────────

accountRouter.delete('/account', requireAuth, async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;
  const jti = req.user!.jti;
  const exp = req.user!.exp;
  const client = await db.connect();
  try {
    await client.query('BEGIN');

    // FK-safe order: leaf rows first. Any table with ON DELETE CASCADE on
    // user_profiles would clean up automatically, but we delete explicitly so
    // the order is legible and safe even if a future migration drops cascade.
    await client.query('DELETE FROM scans WHERE user_id = $1', [userId]);
    await client.query('DELETE FROM pantry_items WHERE user_id = $1', [userId]);
    await client.query('DELETE FROM family_members WHERE owner_id = $1', [userId]);
    await client.query('DELETE FROM refresh_tokens WHERE user_id = $1', [userId]);
    await client.query('DELETE FROM referral_attributions WHERE referred_user_id = $1', [userId]);
    await client.query('DELETE FROM referral_codes WHERE user_id = $1', [userId]);
    await client.query('DELETE FROM user_profiles WHERE id = $1', [userId]);

    await client.query('COMMIT');
  } catch (err: any) {
    await client.query('ROLLBACK').catch(() => {});
    logger.error({ err: err?.message, event: 'account_delete_failed' });
    return res.status(500).json({ error: 'Failed to delete account' });
  } finally {
    client.release();
  }

  // Blacklist the access token so it can't be replayed even before expiry.
  if (jti && exp) {
    const ttl = Math.max(1, exp - Math.floor(Date.now() / 1000));
    const redis = getRedis();
    if (redis) {
      try {
        await redis.set(`blacklist:jwt:${jti}`, '1', 'EX', ttl);
      } catch (err: any) {
        logger.warn({ err: err?.message, event: 'blacklist_set_failed' });
      }
    }
  }

  logger.info({ event: 'account_deleted' });
  return res.status(204).send();
});

// ─── GET /auth/export ─────────────────────────────────────────────────────────

async function safeSelect(query: string, params: unknown[]): Promise<any[]> {
  try {
    const r = await db.query(query, params);
    return r.rows;
  } catch (err: any) {
    // Tables may not exist yet on a fresh dev DB — return empty rather than 500.
    logger.warn({ err: err?.message, event: 'export_table_missing' });
    return [];
  }
}

accountRouter.get('/export', requireAuth, async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;

  try {
    const [profile, familyMembers, scans, pantry, referralAttribs, referralCodes, refreshTokens] = await Promise.all([
      safeSelect('SELECT id, phone, tier, priorities, allergies, goals, created_at, updated_at FROM user_profiles WHERE id = $1', [userId]),
      safeSelect('SELECT * FROM family_members WHERE owner_id = $1', [userId]),
      safeSelect('SELECT * FROM scans WHERE user_id = $1 ORDER BY scanned_at DESC', [userId]),
      safeSelect('SELECT * FROM pantry_items WHERE user_id = $1 ORDER BY added_at DESC', [userId]),
      safeSelect('SELECT * FROM referral_attributions WHERE referred_user_id = $1', [userId]),
      safeSelect('SELECT code, status, follower_count, platform, social_handle, applied_at, approved_at, total_earnings_cents, pending_payout_cents FROM referral_codes WHERE user_id = $1', [userId]),
      safeSelect('SELECT id, expires_at, revoked_at, created_at FROM refresh_tokens WHERE user_id = $1', [userId]),
    ]);

    const payload = {
      exportedAt: new Date().toISOString(),
      profile: profile[0] ?? null,
      familyMembers,
      scans,
      pantry,
      referrals: {
        attributions: referralAttribs,
        codes: referralCodes,
      },
      // Tokens themselves are never in the DB (only hashes) — surface metadata
      // only and mark the field as redacted for clarity.
      refreshTokens: refreshTokens.map(rt => ({
        id: rt.id,
        expires_at: rt.expires_at,
        revoked_at: rt.revoked_at,
        created_at: rt.created_at,
        token_hash: '[redacted]',
      })),
    };

    const date = new Date().toISOString().slice(0, 10);
    res.setHeader('Content-Type', 'application/json');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="revelio-export-${userId}-${date}.json"`
    );
    logger.info({ event: 'account_exported' });
    return res.send(JSON.stringify(payload, null, 2));
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'account_export_failed' });
    return res.status(500).json({ error: 'Failed to export account' });
  }
});
