import { db } from '../db';

const FREE_TIER_LIMIT = 10;

export interface ScanUsageResult {
  allowed: boolean;
  used: number;
  limit: number | null; // null = unlimited
  remaining: number | null;
}

/**
 * Atomically check-and-increment today's scan count for a user.
 * Free tier: 10 scans/day. Pro: unlimited.
 *
 * Concurrency-safe: the count is bumped by Postgres in a single statement with
 * ON CONFLICT + WHERE, so two in-flight requests can't both slip past the cap.
 */
export async function checkAndIncrementScanUsage(
  userId: string,
  tier: string
): Promise<ScanUsageResult> {
  if (tier === 'pro') {
    return { allowed: true, used: 0, limit: null, remaining: null };
  }

  const today = new Date().toISOString().slice(0, 10);

  // Atomic: only increment if we're still under the limit. RETURNING count
  // tells us the post-increment value; if no row is returned, we're capped.
  const result = await db.query(
    `INSERT INTO scan_usage (user_id, date, count)
     VALUES ($1, $2, 1)
     ON CONFLICT (user_id, date) DO UPDATE
       SET count = scan_usage.count + 1
       WHERE scan_usage.count < $3
     RETURNING count`,
    [userId, today, FREE_TIER_LIMIT]
  );

  if (result.rowCount === 0) {
    // Conflict fired but WHERE blocked the update → at or over the limit.
    const usage = await db.query(
      'SELECT count FROM scan_usage WHERE user_id = $1 AND date = $2',
      [userId, today]
    );
    const used = usage.rows[0]?.count ?? FREE_TIER_LIMIT;
    return { allowed: false, used, limit: FREE_TIER_LIMIT, remaining: 0 };
  }

  const newCount: number = result.rows[0].count;
  return {
    allowed: true,
    used: newCount,
    limit: FREE_TIER_LIMIT,
    remaining: Math.max(0, FREE_TIER_LIMIT - newCount),
  };
}

/**
 * Read-only view of current scan usage.
 */
export async function getScanUsage(userId: string, tier: string): Promise<ScanUsageResult> {
  if (tier === 'pro') {
    return { allowed: true, used: 0, limit: null, remaining: null };
  }

  const today = new Date().toISOString().slice(0, 10);
  const usageResult = await db.query(
    'SELECT count FROM scan_usage WHERE user_id = $1 AND date = $2',
    [userId, today]
  );

  const used = usageResult.rows[0]?.count ?? 0;
  return {
    allowed: used < FREE_TIER_LIMIT,
    used,
    limit: FREE_TIER_LIMIT,
    remaining: Math.max(0, FREE_TIER_LIMIT - used),
  };
}
