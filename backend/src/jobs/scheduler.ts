// In-process scheduler for recurring background jobs.
//
// Dependency-free (just setInterval + a clock check) rather than node-cron to
// keep deploys slim. Fine for a single-instance deploy — a real deployment
// should rely on an external scheduler (Fly machines cron, K8s CronJob, GitHub
// Actions) and have this process expose secure trigger endpoints instead.
//
// Current jobs:
//   - weeklyInsights (Mon 15:00 UTC): per-user digest email.
//   - fdaRecalls (every 6h): ingest openFDA recalls + notify affected users.

import { sendWeeklyDigest } from './weeklyInsights';
import { ingestRecentRecalls } from './fdaRecalls';

const TICK_MS = 60 * 1000;
const SIX_HOURS_MS = 6 * 60 * 60 * 1000;
const TARGET_DAY_UTC = 1;   // 0=Sun, 1=Mon
const TARGET_HOUR_UTC = 15; // 15:00 UTC
const TARGET_MINUTE_UTC = 0;

let lastFiredIsoWeek: string | null = null;
let weeklyHandle: ReturnType<typeof setInterval> | null = null;
let recallsHandle: ReturnType<typeof setInterval> | null = null;

// ISO week-year key (e.g. "2026-W16") — used to deduplicate fires within a week.
function isoWeekKey(d: Date): string {
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dayNum = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((date.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
  return `${date.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

async function weeklyTick(): Promise<void> {
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
 * Start all schedulers. Safe to call multiple times — no-ops on re-invocation.
 */
export function startSchedulers(): void {
  if (weeklyHandle || recallsHandle) return;

  // Weekly digest (Mon 15:00 UTC)
  weeklyHandle = setInterval(() => {
    void weeklyTick();
  }, TICK_MS);

  // FDA recalls: kick once on boot so cold starts don't wait 6 hours.
  void ingestRecentRecalls().catch(err => {
    console.error('[scheduler] initial fdaRecalls run failed:', err);
  });
  recallsHandle = setInterval(() => {
    void ingestRecentRecalls().catch(err => {
      console.error('[scheduler] fdaRecalls run failed:', err);
    });
  }, SIX_HOURS_MS);

  console.log('[scheduler] started — weekly digest Mon 15:00 UTC, fdaRecalls every 6h');
}

export function stopSchedulers(): void {
  if (weeklyHandle) { clearInterval(weeklyHandle); weeklyHandle = null; }
  if (recallsHandle) { clearInterval(recallsHandle); recallsHandle = null; }
}
