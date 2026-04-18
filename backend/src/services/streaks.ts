import { db } from '../db';

/**
 * Records a scan event toward the user's streak and returns the new streak state.
 *
 * Rules (all dates evaluated in UTC `DATE` terms — trades off edge-of-day
 * foreign-traveller weirdness for server simplicity):
 *   - Same calendar day as `last_scan_date`  → no-op, return existing state.
 *   - Exactly one day after `last_scan_date` → increment current streak.
 *     If that ties or beats `longest_streak_days`, bump the longest too.
 *   - Gap > 1 day, or no prior scan           → reset current streak to 1.
 *   - Always update `last_scan_date = today`.
 *
 * Callers: POST /scan/history (the one place that persists a scan). Safe to
 * invoke inside a single request — one SELECT + one UPSERT.
 */
export interface StreakState {
  currentStreakDays: number;
  longestStreakDays: number;
  lastScanDate: string | null; // ISO YYYY-MM-DD
  weeklyGoal: number;
}

export async function recordScanForStreak(userId: string): Promise<StreakState> {
  const existing = await db.query(
    `SELECT current_streak_days, longest_streak_days, last_scan_date, weekly_goal
       FROM user_streaks WHERE user_id = $1`,
    [userId]
  );

  const today = new Date();
  const todayStr = isoDate(today);
  const yesterdayStr = isoDate(new Date(today.getTime() - 24 * 60 * 60 * 1000));

  let current = 1;
  let longest = 1;
  let weeklyGoal = 10;

  if (existing.rows.length > 0) {
    const row = existing.rows[0];
    const last: string | null = row.last_scan_date ? isoDate(new Date(row.last_scan_date)) : null;
    weeklyGoal = row.weekly_goal ?? 10;
    const prevCurrent = row.current_streak_days ?? 0;
    const prevLongest = row.longest_streak_days ?? 0;

    if (last === todayStr) {
      // Already recorded today — return as-is.
      return {
        currentStreakDays: prevCurrent,
        longestStreakDays: prevLongest,
        lastScanDate: last,
        weeklyGoal,
      };
    }

    if (last === yesterdayStr) {
      current = prevCurrent + 1;
    } else {
      current = 1;
    }
    longest = Math.max(prevLongest, current);
  }

  await db.query(
    `INSERT INTO user_streaks (user_id, current_streak_days, longest_streak_days, last_scan_date, weekly_goal, updated_at)
     VALUES ($1, $2, $3, $4::date, $5, NOW())
     ON CONFLICT (user_id) DO UPDATE SET
       current_streak_days = EXCLUDED.current_streak_days,
       longest_streak_days = EXCLUDED.longest_streak_days,
       last_scan_date = EXCLUDED.last_scan_date,
       updated_at = NOW()`,
    [userId, current, longest, todayStr, weeklyGoal]
  );

  return {
    currentStreakDays: current,
    longestStreakDays: longest,
    lastScanDate: todayStr,
    weeklyGoal,
  };
}

/** Count scans for the current ISO week (Mon–Sun) for progress UI. */
export async function weeklyScanCount(userId: string): Promise<number> {
  const result = await db.query(
    `SELECT COUNT(*)::int AS n
       FROM scans
      WHERE user_id = $1
        AND scanned_at >= date_trunc('week', NOW())`,
    [userId]
  );
  return result.rows[0]?.n ?? 0;
}

export async function getStreak(userId: string): Promise<StreakState> {
  const result = await db.query(
    `SELECT current_streak_days, longest_streak_days, last_scan_date, weekly_goal
       FROM user_streaks WHERE user_id = $1`,
    [userId]
  );
  if (result.rows.length === 0) {
    return { currentStreakDays: 0, longestStreakDays: 0, lastScanDate: null, weeklyGoal: 10 };
  }
  const row = result.rows[0];
  return {
    currentStreakDays: row.current_streak_days ?? 0,
    longestStreakDays: row.longest_streak_days ?? 0,
    lastScanDate: row.last_scan_date ? isoDate(new Date(row.last_scan_date)) : null,
    weeklyGoal: row.weekly_goal ?? 10,
  };
}

export async function setWeeklyGoal(userId: string, goal: number): Promise<StreakState> {
  await db.query(
    `INSERT INTO user_streaks (user_id, weekly_goal, updated_at)
     VALUES ($1, $2, NOW())
     ON CONFLICT (user_id) DO UPDATE SET weekly_goal = EXCLUDED.weekly_goal, updated_at = NOW()`,
    [userId, goal]
  );
  return getStreak(userId);
}

function isoDate(d: Date): string {
  // YYYY-MM-DD in UTC — matches PostgreSQL DATE casting for our USA/EU traffic.
  return d.toISOString().slice(0, 10);
}
