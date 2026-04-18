import { db } from '../db';
import type { AuthRequest } from '../routes/auth';

// ─── Effective tier resolver ─────────────────────────────────────────────────
//
// A user has Pro access if any of the following is true:
//   1. Their own user_profiles.tier is 'pro'.
//   2. They are a member (or owner) of a family_plans whose owner is 'pro'.
//   3. They have an active pro_grants row (NOW() between starts_at and ends_at).
//
// The helper returns 'pro' or 'free'; no other tiers exist in the current schema.

export async function effectiveTier(userId: string): Promise<'pro' | 'free'> {
  // 1. Own tier
  const own = await db.query(
    `SELECT tier FROM user_profiles WHERE id = $1`,
    [userId]
  );
  if (own.rows[0]?.tier === 'pro') return 'pro';

  // 2. Family plan membership where the owner is Pro
  const fam = await db.query(
    `SELECT 1
       FROM family_plan_members fpm
       JOIN family_plans fp ON fp.id = fpm.plan_id
       JOIN user_profiles u ON u.id = fp.owner_id
       WHERE fpm.user_id = $1 AND u.tier = 'pro'
       LIMIT 1`,
    [userId]
  );
  if (fam.rows.length > 0) return 'pro';

  // 3. Active pro grant (friend invite, promo, etc.)
  const grant = await db.query(
    `SELECT 1 FROM pro_grants
       WHERE user_id = $1
         AND NOW() BETWEEN starts_at AND ends_at
       LIMIT 1`,
    [userId]
  );
  if (grant.rows.length > 0) return 'pro';

  return 'free';
}

// Convenience wrapper used by route handlers that previously did
// `req.user.tier === 'pro'`. Callers should `await` it.
export async function hasProAccess(req: AuthRequest): Promise<boolean> {
  const userId = req.user?.userId;
  if (!userId) return false;
  return (await effectiveTier(userId)) === 'pro';
}
