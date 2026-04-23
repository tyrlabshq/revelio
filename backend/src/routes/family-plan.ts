import { Router, Response } from 'express';
import { randomBytes } from 'crypto';
import { db } from '../db';
import { requireAuth, AuthRequest } from './auth';
import { hasProAccess } from '../middleware/familyTier';
import { logger } from '../logger';

export const familyPlanRouter = Router();

// ─── Helpers ──────────────────────────────────────────────────────────────────

function generateInviteCode(): string {
  // 10-char alphanumeric (uppercase, no ambiguous chars) for easy verbal sharing.
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = randomBytes(10);
  let code = '';
  for (let i = 0; i < 10; i++) {
    code += alphabet[bytes[i] % alphabet.length];
  }
  return code;
}

async function getPlanForUser(userId: string): Promise<{
  plan: { id: string; owner_id: string; max_members: number; created_at: string };
  role: 'owner' | 'member';
} | null> {
  // Owner?
  const ownerRow = await db.query(
    `SELECT id, owner_id, max_members, created_at
       FROM family_plans WHERE owner_id = $1`,
    [userId]
  );
  if (ownerRow.rows[0]) {
    return { plan: ownerRow.rows[0], role: 'owner' };
  }

  // Member?
  const memberRow = await db.query(
    `SELECT fp.id, fp.owner_id, fp.max_members, fp.created_at
       FROM family_plan_members fpm
       JOIN family_plans fp ON fp.id = fpm.plan_id
       WHERE fpm.user_id = $1
       LIMIT 1`,
    [userId]
  );
  if (memberRow.rows[0]) {
    return { plan: memberRow.rows[0], role: 'member' };
  }

  return null;
}

async function listMembers(planId: string) {
  const result = await db.query(
    `SELECT fpm.user_id, fpm.role, fpm.joined_at, u.phone, u.tier
       FROM family_plan_members fpm
       JOIN user_profiles u ON u.id = fpm.user_id
       WHERE fpm.plan_id = $1
       ORDER BY fpm.joined_at ASC`,
    [planId]
  );
  return result.rows.map(r => ({
    userId: r.user_id,
    role: r.role,
    joinedAt: r.joined_at,
    phone: r.phone,
  }));
}

// ─── GET /family-plan ─────────────────────────────────────────────────────────

familyPlanRouter.get('/', requireAuth, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.userId;
    const tier = (await hasProAccess(req)) ? 'pro' : 'free';
    const found = await getPlanForUser(userId);

    if (!found) {
      return res.json({ plan: null, members: [], tier });
    }

    const members = await listMembers(found.plan.id);
    return res.json({
      plan: {
        id: found.plan.id,
        ownerId: found.plan.owner_id,
        maxMembers: found.plan.max_members,
        createdAt: found.plan.created_at,
        role: found.role,
      },
      members,
      tier,
    });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'family-plan-get-failed' }, '[family-plan GET] error');
    return res.status(500).json({ error: 'Failed to load family plan' });
  }
});

// ─── POST /family-plan ────────────────────────────────────────────────────────

familyPlanRouter.post('/', requireAuth, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.userId;

    // Only Pro users can create a plan. We use the JWT's tier here because
    // the creator must themselves be paying — family-plan membership shouldn't
    // transitively let a member create a sub-plan.
    if (req.user!.tier !== 'pro') {
      return res.status(403).json({ error: 'Pro subscription required to start a family plan' });
    }

    // Idempotent: return existing plan if one exists.
    const existing = await db.query(
      `SELECT id, owner_id, max_members, created_at FROM family_plans WHERE owner_id = $1`,
      [userId]
    );
    if (existing.rows[0]) {
      const members = await listMembers(existing.rows[0].id);
      return res.json({
        plan: {
          id: existing.rows[0].id,
          ownerId: existing.rows[0].owner_id,
          maxMembers: existing.rows[0].max_members,
          createdAt: existing.rows[0].created_at,
          role: 'owner',
        },
        members,
        created: false,
      });
    }

    const insertPlan = await db.query(
      `INSERT INTO family_plans (owner_id) VALUES ($1)
         RETURNING id, owner_id, max_members, created_at`,
      [userId]
    );
    const plan = insertPlan.rows[0];

    // Also insert the owner as a member with role = 'owner' for cleaner queries.
    await db.query(
      `INSERT INTO family_plan_members (plan_id, user_id, role)
         VALUES ($1, $2, 'owner')
         ON CONFLICT (plan_id, user_id) DO NOTHING`,
      [plan.id, userId]
    );

    const members = await listMembers(plan.id);
    return res.status(201).json({
      plan: {
        id: plan.id,
        ownerId: plan.owner_id,
        maxMembers: plan.max_members,
        createdAt: plan.created_at,
        role: 'owner',
      },
      members,
      created: true,
    });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'family-plan-post-failed' }, '[family-plan POST] error');
    return res.status(500).json({ error: 'Failed to create family plan' });
  }
});

// ─── POST /family-plan/invite ─────────────────────────────────────────────────

familyPlanRouter.post('/invite', requireAuth, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.userId;

    const planRow = await db.query(
      `SELECT id, max_members FROM family_plans WHERE owner_id = $1`,
      [userId]
    );
    const plan = planRow.rows[0];
    if (!plan) {
      return res.status(404).json({ error: 'You do not own a family plan' });
    }

    // Enforce max_members cap — current members + outstanding (unconsumed, unexpired) invites.
    const countRow = await db.query(
      `SELECT COUNT(*)::int AS members FROM family_plan_members WHERE plan_id = $1`,
      [plan.id]
    );
    const outstandingRow = await db.query(
      `SELECT COUNT(*)::int AS pending FROM family_plan_invites
         WHERE plan_id = $1 AND consumed_by IS NULL AND expires_at > NOW()`,
      [plan.id]
    );
    const currentMembers = countRow.rows[0].members as number;
    const pending = outstandingRow.rows[0].pending as number;
    if (currentMembers + pending >= plan.max_members) {
      return res.status(409).json({ error: 'Family plan is full (including pending invites)' });
    }

    // Generate a unique code. Retry a few times on the (astronomically unlikely) collision.
    let code = '';
    for (let attempt = 0; attempt < 5; attempt++) {
      code = generateInviteCode();
      const clash = await db.query(
        `SELECT 1 FROM family_plan_invites WHERE code = $1`,
        [code]
      );
      if (clash.rows.length === 0) break;
      code = '';
    }
    if (!code) {
      return res.status(500).json({ error: 'Failed to generate unique invite code' });
    }

    const result = await db.query(
      `INSERT INTO family_plan_invites (plan_id, code, expires_at)
         VALUES ($1, $2, NOW() + INTERVAL '7 days')
         RETURNING code, expires_at`,
      [plan.id, code]
    );

    return res.status(201).json({
      code: result.rows[0].code,
      expiresAt: result.rows[0].expires_at,
    });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'family-plan-invite-failed' }, '[family-plan/invite] error');
    return res.status(500).json({ error: 'Failed to generate invite' });
  }
});

// ─── POST /family-plan/join ───────────────────────────────────────────────────

familyPlanRouter.post('/join', requireAuth, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.user!.userId;
    const { code } = req.body as { code?: string };

    if (!code || typeof code !== 'string' || code.length > 16) {
      return res.status(400).json({ error: 'Invite code is required' });
    }

    // Reject if user is already a member of any plan.
    const existing = await db.query(
      `SELECT 1 FROM family_plan_members WHERE user_id = $1 LIMIT 1`,
      [userId]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'You are already on a family plan' });
    }

    const inviteRow = await db.query(
      `SELECT id, plan_id, expires_at, consumed_by
         FROM family_plan_invites
         WHERE code = $1`,
      [code.trim()]
    );
    const invite = inviteRow.rows[0];
    if (!invite) {
      return res.status(404).json({ error: 'Invite not found' });
    }
    if (invite.consumed_by) {
      return res.status(409).json({ error: 'Invite already used' });
    }
    if (new Date(invite.expires_at).getTime() < Date.now()) {
      return res.status(410).json({ error: 'Invite expired' });
    }

    // Check capacity
    const planRow = await db.query(
      `SELECT id, max_members FROM family_plans WHERE id = $1`,
      [invite.plan_id]
    );
    const plan = planRow.rows[0];
    if (!plan) {
      return res.status(404).json({ error: 'Family plan no longer exists' });
    }
    const countRow = await db.query(
      `SELECT COUNT(*)::int AS members FROM family_plan_members WHERE plan_id = $1`,
      [plan.id]
    );
    if (countRow.rows[0].members >= plan.max_members) {
      return res.status(409).json({ error: 'Family plan is full' });
    }

    // Insert the member + mark the invite consumed in one transaction.
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `INSERT INTO family_plan_members (plan_id, user_id, role)
           VALUES ($1, $2, 'member')
           ON CONFLICT (plan_id, user_id) DO NOTHING`,
        [plan.id, userId]
      );
      await client.query(
        `UPDATE family_plan_invites
           SET consumed_by = $1, consumed_at = NOW()
           WHERE id = $2 AND consumed_by IS NULL`,
        [userId, invite.id]
      );
      await client.query('COMMIT');
    } catch (txErr) {
      await client.query('ROLLBACK');
      throw txErr;
    } finally {
      client.release();
    }

    return res.json({ ok: true, planId: plan.id });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'family-plan-join-failed' }, '[family-plan/join] error');
    return res.status(500).json({ error: 'Failed to join family plan' });
  }
});

// ─── DELETE /family-plan/members/:userId ──────────────────────────────────────

familyPlanRouter.delete('/members/:userId', requireAuth, async (req: AuthRequest, res: Response) => {
  try {
    const ownerId = req.user!.userId;
    const targetUserId = req.params.userId;

    const planRow = await db.query(
      `SELECT id FROM family_plans WHERE owner_id = $1`,
      [ownerId]
    );
    const plan = planRow.rows[0];
    if (!plan) {
      return res.status(404).json({ error: 'You do not own a family plan' });
    }

    // Disallow removing the owner themselves via this endpoint.
    if (targetUserId === ownerId) {
      return res.status(400).json({ error: 'Cannot remove the owner; delete the plan instead' });
    }

    const result = await db.query(
      `DELETE FROM family_plan_members
         WHERE plan_id = $1 AND user_id = $2
         RETURNING id`,
      [plan.id, targetUserId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Member not found on this plan' });
    }

    return res.json({ ok: true, removed: targetUserId });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'family-plan-members-delete-failed' }, '[family-plan/members DELETE] error');
    return res.status(500).json({ error: 'Failed to remove member' });
  }
});
