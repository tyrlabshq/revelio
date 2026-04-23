import { Response, NextFunction } from 'express';
import { db } from '../db';
import { logger } from '../logger';
import type { AuthRequest } from './requireAuth';

/**
 * Admin authorization middleware.
 *
 * MUST be chained AFTER `requireAuth` so `req.user.userId` is trusted.
 * We look up `is_admin` on every request rather than baking it into the
 * JWT — that way demoting an operator takes effect the moment the DB
 * flips, without needing to revoke their token.
 *
 * The query is a single PK-indexed lookup on user_profiles; the cost is
 * negligible relative to anything the admin dashboard does afterwards.
 */
export async function requireAdmin(
  req: AuthRequest,
  res: Response,
  next: NextFunction
): Promise<void | Response> {
  const userId = req.user?.userId;
  if (!userId) {
    // Defense-in-depth: if someone mounts this without requireAuth, fail
    // closed rather than silently granting access.
    return res.status(401).json({ error: 'Authorization required' });
  }
  try {
    const result = await db.query(
      `SELECT is_admin FROM user_profiles WHERE id = $1`,
      [userId]
    );
    const isAdmin = result.rows[0]?.is_admin === true;
    if (!isAdmin) {
      return res.status(403).json({ error: 'Admin access required' });
    }
    next();
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'require_admin_failed' });
    return res.status(500).json({ error: 'Authorization check failed' });
  }
}
