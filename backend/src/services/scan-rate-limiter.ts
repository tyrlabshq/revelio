import { db } from '../db';

const FREE_TIER_LIMIT = 10;

export interface ScanUsageResult {
  allowed: boolean;
  used: number;
  limit: number | null; // null = unlimited
  remaining: number | null;
}

/**
 * Check if a user can perform a scan and increment the counter if allowed.
 * - Free tier: 10 scans/day
 * - Pro tier: unlimited
 */
export async function checkAndIncrementScanUsage(
  userId: string,
  tier: string
): Promise<ScanUsageResult> {
  if (tier === 'pro') {
    return { allowed: true, used: 0, limit: null, remaining: null };
  }

  const today = new Date().toISOString().slice(0, 10);

  // Get or create today's usage row
  const usageResult = await db.query(
    'SELECT count FROM scan_usage WHERE user_id = $1 AND date = $2',
    [userId, today]
  );

  const currentCount = usageResult.rows[0]?.count ?? 0;

  if (currentCount >= FREE_TIER_LIMIT) {
    return {
      allowed: false,
      used: currentCount,
      limit: FREE_TIER_LIMIT,
      remaining: 0,
    };
  }

  // Increment (upsert)
  await db.query(
    `INSERT INTO scan_usage (user_id, date, count)
     VALUES ($1, $2, 1)
     ON CONFLICT (user_id, date)
     DO UPDATE SET count = scan_usage.count + 1`,
    [userId, today]
  );

  const newCount = currentCount + 1;
  return {
    allowed: true,
    used: newCount,
    limit: FREE_TIER_LIMIT,
    remaining: FREE_TIER_LIMIT - newCount,
  };
}

/**
 * Get current scan usage for a user (read-only).
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
