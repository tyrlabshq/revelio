import { Router, Response } from 'express';
import { randomBytes } from 'crypto';
import { db } from '../db';
import { requireAuth, AuthRequest } from './auth';
import { logger } from '../logger';

export const friendInvitesRouter = Router();

const INVITE_EXPIRY_DAYS = 30;
const GRANT_DURATION_DAYS = 7;
const SHARE_BASE_URL = 'https://revelio.app/i';

function generateInviteCode(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = randomBytes(8);
  let code = '';
  for (let i = 0; i < 8; i++) {
    code += alphabet[bytes[i] % alphabet.length];
  }
  return code;
}

// ─── POST /friend-invites ─────────────────────────────────────────────────────

friendInvitesRouter.post('/', requireAuth, async (req: AuthRequest, res: Response) => {
  try {
    const inviterId = req.user!.userId;

    // Retry on (astronomically unlikely) code collision.
    let code = '';
    for (let attempt = 0; attempt < 5; attempt++) {
      code = generateInviteCode();
      const clash = await db.query(
        `SELECT 1 FROM friend_invites WHERE code = $1`,
        [code]
      );
      if (clash.rows.length === 0) break;
      code = '';
    }
    if (!code) {
      return res.status(500).json({ error: 'Failed to generate unique invite code' });
    }

    const result = await db.query(
      `INSERT INTO friend_invites (inviter_id, code, expires_at)
         VALUES ($1, $2, NOW() + INTERVAL '${INVITE_EXPIRY_DAYS} days')
         RETURNING code, expires_at`,
      [inviterId, code]
    );

    return res.status(201).json({
      code: result.rows[0].code,
      expiresAt: result.rows[0].expires_at,
      shareUrl: `${SHARE_BASE_URL}/${result.rows[0].code}`,
    });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'friend-invites-post-failed' }, '[friend-invites POST] error');
    return res.status(500).json({ error: 'Failed to generate invite' });
  }
});

// ─── POST /friend-invites/redeem ──────────────────────────────────────────────

friendInvitesRouter.post('/redeem', requireAuth, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.userId;
    const { code } = req.body as { code?: string };

    if (!code || typeof code !== 'string' || code.length > 16) {
      return res.status(400).json({ error: 'Invite code is required' });
    }

    const inviteRow = await db.query(
      `SELECT id, inviter_id, invited_user_id, redeemed_at, expires_at
         FROM friend_invites
         WHERE code = $1`,
      [code.trim()]
    );
    const invite = inviteRow.rows[0];
    if (!invite) {
      return res.status(404).json({ error: 'Invite not found' });
    }
    if (invite.inviter_id === userId) {
      return res.status(400).json({ error: 'Cannot redeem your own invite' });
    }
    if (invite.redeemed_at) {
      return res.status(409).json({ error: 'Invite already redeemed' });
    }
    if (new Date(invite.expires_at).getTime() < Date.now()) {
      return res.status(410).json({ error: 'Invite expired' });
    }

    // Idempotency guard: if this user already has a friend-invite grant still active,
    // return success without stacking another one.
    const existingGrant = await db.query(
      `SELECT 1 FROM pro_grants
         WHERE user_id = $1 AND reason = 'friend_invite'
           AND ends_at > NOW()
         LIMIT 1`,
      [userId]
    );
    if (existingGrant.rows.length > 0) {
      return res.status(409).json({ error: 'You already have an active friend-invite Pro grant' });
    }

    // Do the redemption + both grants atomically.
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      const upd = await client.query(
        `UPDATE friend_invites
           SET redeemed_at = NOW(), invited_user_id = $1
           WHERE id = $2 AND redeemed_at IS NULL
           RETURNING id`,
        [userId, invite.id]
      );
      if (upd.rowCount === 0) {
        // Someone else redeemed it between our SELECT and UPDATE.
        await client.query('ROLLBACK');
        return res.status(409).json({ error: 'Invite already redeemed' });
      }

      await client.query(
        `INSERT INTO pro_grants (user_id, reason, ends_at)
           VALUES ($1, 'friend_invite', NOW() + INTERVAL '${GRANT_DURATION_DAYS} days')`,
        [userId]
      );
      await client.query(
        `INSERT INTO pro_grants (user_id, reason, ends_at)
           VALUES ($1, 'friend_invite', NOW() + INTERVAL '${GRANT_DURATION_DAYS} days')`,
        [invite.inviter_id]
      );

      await client.query('COMMIT');
    } catch (txErr) {
      await client.query('ROLLBACK');
      throw txErr;
    } finally {
      client.release();
    }

    return res.json({
      ok: true,
      grantDays: GRANT_DURATION_DAYS,
    });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'friend-invites-redeem-failed' }, '[friend-invites/redeem] error');
    return res.status(500).json({ error: 'Failed to redeem invite' });
  }
});
