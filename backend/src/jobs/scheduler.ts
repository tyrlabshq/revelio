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
//   - priceCheck (daily 18:00 UTC): fetch affiliate prices + fire drop alerts.
//   - brandTrends (daily 16:00 UTC): upsert 7-day brand score averages.
//   - creatorPayouts (daily 17:00 UTC): drain pending Stripe transfers.
//     Skipped entirely when STRIPE_SECRET_KEY is unset so dev boxes boot clean.

import { logger } from '../logger';
import { sendWeeklyDigest } from './weeklyInsights';
import { ingestRecentRecalls } from './fdaRecalls';
import { runPriceCheck } from './priceCheck';
import { updateBrandTrends } from './brandTrends';
import { isStripeConfigured, processPendingPayouts } from '../services/stripeConnect';

const TICK_MS = 60 * 1000;
const SIX_HOURS_MS = 6 * 60 * 60 * 1000;
const TARGET_DAY_UTC = 1;   // 0=Sun, 1=Mon
const TARGET_HOUR_UTC = 15; // 15:00 UTC
const TARGET_MINUTE_UTC = 0;

const PRICE_CHECK_HOUR_UTC = 18;
const PRICE_CHECK_MINUTE_UTC = 0;

// Brand-trends: daily at 16:00 UTC. One hour after weekly insights and
// two hours before price-check so the heavy pg aggregates don't pile up in
// the same minute.
const BRAND_TRENDS_HOUR_UTC = 16;
const BRAND_TRENDS_MINUTE_UTC = 0;

// Creator payouts: daily at 17:00 UTC, between brand-trends and price-check.
const CREATOR_PAYOUTS_HOUR_UTC = 17;
const CREATOR_PAYOUTS_MINUTE_UTC = 0;

let lastFiredIsoWeek: string | null = null;
let lastFiredPriceDay: string | null = null;
let lastFiredBrandTrendsDay: string | null = null;
let lastFiredCreatorPayoutsDay: string | null = null;
let weeklyHandle: ReturnType<typeof setInterval> | null = null;
let recallsHandle: ReturnType<typeof setInterval> | null = null;
let priceHandle: ReturnType<typeof setInterval> | null = null;
let brandTrendsHandle: ReturnType<typeof setInterval> | null = null;
let creatorPayoutsHandle: ReturnType<typeof setInterval> | null = null;

// UTC calendar-day key (e.g. "2026-04-23") — used to deduplicate daily fires.
function utcDayKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

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

  logger.info({ event: 'scheduler-weekly-digest-firing', week: key }, `[scheduler] firing weekly digest`);
  try {
    const results = await sendWeeklyDigest();
    const sent = results.filter(r => r.sent).length;
    logger.info({ event: 'scheduler-weekly-digest-done', processed: results.length, sent }, `[scheduler] weekly digest done`);
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'scheduler-weekly-digest-failed' }, '[scheduler] weekly digest failed');
  }
}

async function priceCheckTick(): Promise<void> {
  const now = new Date();
  if (
    now.getUTCHours() !== PRICE_CHECK_HOUR_UTC ||
    now.getUTCMinutes() !== PRICE_CHECK_MINUTE_UTC
  ) {
    return;
  }
  const key = utcDayKey(now);
  if (key === lastFiredPriceDay) return;
  lastFiredPriceDay = key;

  try {
    const result = await runPriceCheck();
    logger.info({ event: 'price_check_fired', day: key, ...result });
  } catch (err) {
    logger.error({ event: 'price_check_failed', err: (err as Error)?.message });
  }
}

async function brandTrendsTick(): Promise<void> {
  const now = new Date();
  if (
    now.getUTCHours() !== BRAND_TRENDS_HOUR_UTC ||
    now.getUTCMinutes() !== BRAND_TRENDS_MINUTE_UTC
  ) {
    return;
  }
  const key = utcDayKey(now);
  if (key === lastFiredBrandTrendsDay) return;
  lastFiredBrandTrendsDay = key;

  try {
    const rows = await updateBrandTrends(now);
    logger.info({ event: 'brand_trends_fired', day: key, brands: rows.length });
  } catch (err) {
    logger.error({ event: 'brand_trends_failed', err: (err as Error)?.message });
  }
}

async function creatorPayoutsTick(): Promise<void> {
  const now = new Date();
  if (
    now.getUTCHours() !== CREATOR_PAYOUTS_HOUR_UTC ||
    now.getUTCMinutes() !== CREATOR_PAYOUTS_MINUTE_UTC
  ) {
    return;
  }
  const key = utcDayKey(now);
  if (key === lastFiredCreatorPayoutsDay) return;
  lastFiredCreatorPayoutsDay = key;

  // Dev boxes don't set STRIPE_SECRET_KEY; skip silently rather than throw.
  if (!isStripeConfigured()) {
    logger.info({ event: 'creator_payouts_skipped', reason: 'stripe_unconfigured', day: key });
    return;
  }

  try {
    const result = await processPendingPayouts();
    logger.info({ event: 'creator_payouts_fired', day: key, ...result });
  } catch (err) {
    logger.error({ event: 'creator_payouts_failed', err: (err as Error)?.message });
  }
}

/**
 * Start all schedulers. Safe to call multiple times — no-ops on re-invocation.
 */
export function startSchedulers(): void {
  if (weeklyHandle || recallsHandle || priceHandle || brandTrendsHandle || creatorPayoutsHandle) return;

  // Weekly digest (Mon 15:00 UTC)
  weeklyHandle = setInterval(() => {
    void weeklyTick();
  }, TICK_MS);

  // FDA recalls: kick once on boot so cold starts don't wait 6 hours.
  void ingestRecentRecalls().catch(err => {
    logger.error({ err: (err as Error)?.message, event: 'scheduler-fda-recalls-initial-failed' }, '[scheduler] initial fdaRecalls run failed');
  });
  recallsHandle = setInterval(() => {
    void ingestRecentRecalls().catch(err => {
      logger.error({ err: (err as Error)?.message, event: 'scheduler-fda-recalls-tick-failed' }, '[scheduler] fdaRecalls run failed');
    });
  }, SIX_HOURS_MS);

  // Daily price check (18:00 UTC). Ticked every minute; guarded by utcDayKey.
  priceHandle = setInterval(() => {
    void priceCheckTick();
  }, TICK_MS);

  // Daily brand trends (16:00 UTC). Same minute-tick + day-key dedup pattern.
  brandTrendsHandle = setInterval(() => {
    void brandTrendsTick();
  }, TICK_MS);

  // Daily creator payouts (17:00 UTC). No-ops when Stripe is unconfigured.
  creatorPayoutsHandle = setInterval(() => {
    void creatorPayoutsTick();
  }, TICK_MS);

  logger.info({ event: 'scheduler-started' }, '[scheduler] started — weekly digest Mon 15:00 UTC, fdaRecalls every 6h, brandTrends daily 16:00 UTC, creatorPayouts daily 17:00 UTC, priceCheck daily 18:00 UTC');
}

export function stopSchedulers(): void {
  if (weeklyHandle) { clearInterval(weeklyHandle); weeklyHandle = null; }
  if (recallsHandle) { clearInterval(recallsHandle); recallsHandle = null; }
  if (priceHandle) { clearInterval(priceHandle); priceHandle = null; }
  if (brandTrendsHandle) { clearInterval(brandTrendsHandle); brandTrendsHandle = null; }
  if (creatorPayoutsHandle) { clearInterval(creatorPayoutsHandle); creatorPayoutsHandle = null; }
}
