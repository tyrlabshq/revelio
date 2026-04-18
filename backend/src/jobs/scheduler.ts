// ─── backend/src/jobs/scheduler.ts ───────────────────────────────────────────
// Track 3.9 — naive in-process scheduler for the weekly insights digest.
//
// Intentionally dependency-free: uses setInterval + a clock check rather than
// pulling in node-cron. This is fine for a single-instance deploy but NOT
// production-robust — a real deployment should rely on an external scheduler
// (Fly.io machines with a cron schedule, Kubernetes CronJob, GitHub Actions,
// or similar) and have this process expose a secure trigger endpoint instead.
//
// Behavior: ticks every 60s. When it observes Monday at 15:00 UTC (i.e. the
// current minute matches and we have not already fired this week), it invokes
// sendWeeklyDigest().

import { sendWeeklyDigest } from './weeklyInsights';

const TICK_MS = 60 * 1000;
const TARGET_DAY_UTC = 1;   // 0=Sun, 1=Mon
const TARGET_HOUR_UTC = 15; // 15:00 UTC
const TARGET_MINUTE_UTC = 0;

let lastFiredIsoWeek: string | null = null;
let intervalHandle: ReturnType<typeof setInterval> | null = null;

// ISO week-year key (e.g. "2026-W16") — used to deduplicate fires within a week.
function isoWeekKey(d: Date): string {
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dayNum = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((date.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
  return `${date.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

async function tick(): Promise<void> {
  const now = new Date();
  if (
    now.getUTCDay() !== TARGET_DAY_UTC ||
    now.getUTCHours() !== TARGET_HOUR_UTC ||
    now.getUTCMinutes() !== TARGET_MINUTE_UTC
  ) {
    return;
  }
  const key = isoWeekKey(now);
  if (key === lastFiredIsoWeek) return;
  lastFiredIsoWeek = key;

  console.log(`[scheduler] firing weekly digest at ${now.toISOString()} (week ${key})`);
  try {
    const results = await sendWeeklyDigest();
    const sent = results.filter(r => r.sent).length;
    console.log(`[scheduler] weekly digest done: ${results.length} processed, ${sent} emails sent`);
  } catch (err) {
    console.error('[scheduler] weekly digest failed:', err);
  }
}

/**
 * Start the in-process scheduler. Safe to call multiple times — subsequent
 * calls are no-ops.
 *
 * NOTE: naive implementation. For production-grade reliability, replace with
 * an external scheduler (Fly machines, K8s CronJob, GitHub Actions) hitting
 * POST /insights/send-now (or a dedicated admin endpoint) with the right
 * credentials.
 */
export function startSchedulers(): void {
  if (intervalHandle) return;
  intervalHandle = setInterval(() => {
    void tick();
  }, TICK_MS);
  console.log('[scheduler] started — weekly digest at Mon 15:00 UTC');
}

export function stopSchedulers(): void {
  if (intervalHandle) {
    clearInterval(intervalHandle);
    intervalHandle = null;
  }
}
