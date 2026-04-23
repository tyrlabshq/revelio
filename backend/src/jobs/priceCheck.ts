// REV-20: Price-drop alert job.
//
// Runs daily at 18:00 UTC via jobs/scheduler.ts. Walks every barcode we have
// an active subscription to (union of price_alerts.active + recent
// swap_cart_clicks so the first tap on a swap cart already seeds a price
// history entry), fetches the current affiliate price, appends to
// price_history, and fans out push notifications to users whose thresholds
// just crossed. A 24h dedup window keyed on price_alerts.last_notified_at
// prevents slide-show spam during multi-day declines.
//
// TODO(price): swap fetchAffiliatePrice() for a real PA-API / Thrive
// pricing call. For MVP we deterministically shave ~3% off the last seen
// price so the end-to-end flow (fetch → compare → notify → dedup) is
// exercised without live creds.

import { db } from '../db';
import { sendPush } from '../services/push';
import { logger } from '../logger';

const AFFILIATE_NETWORK = 'amazon';
const DEFAULT_SEED_PRICE_CENTS = 1299;   // ~$12.99 — plausible seed when we've never seen a price before
const DEV_STUB_DROP_RATIO = 0.97;        // 3% shave each run so thresholds trip within a few days
const DEDUP_MS = 24 * 60 * 60 * 1000;

interface PriceAlertRow {
  id: string;
  user_id: string;
  barcode: string;
  threshold_cents: number | null;
  threshold_pct: number | null;
  last_notified_at: string | null;
}

interface LatestPriceRow {
  price_cents: number;
  recorded_at: string;
}

/**
 * Fetch the current affiliate price for a barcode. MVP stub: take the most
 * recent price_history row and shave DEV_STUB_DROP_RATIO off it; if we've
 * never seen this barcode, seed with DEFAULT_SEED_PRICE_CENTS so the first
 * run still produces a row callers can diff against.
 *
 * Real implementation will call into an affiliate-network helper (PA-API
 * for amazon, Thrive Market public price endpoint, iHerb product feed)
 * and return the live price in cents.
 */
async function fetchAffiliatePrice(barcode: string): Promise<number | null> {
  const { rows } = await db.query<LatestPriceRow>(
    `SELECT price_cents, recorded_at
       FROM price_history
      WHERE barcode = $1 AND affiliate_network = $2
      ORDER BY recorded_at DESC
      LIMIT 1`,
    [barcode, AFFILIATE_NETWORK]
  );
  const previous = rows[0]?.price_cents;
  if (typeof previous === 'number') {
    return Math.max(1, Math.round(previous * DEV_STUB_DROP_RATIO));
  }
  return DEFAULT_SEED_PRICE_CENTS;
}

/**
 * Return the set of distinct barcodes that we should price-check this run:
 * every barcode with an active alert, plus every barcode a user has clicked
 * through the swap cart for (so we warm price_history for likely-future
 * alerts).
 */
async function candidateBarcodes(): Promise<string[]> {
  const { rows } = await db.query<{ barcode: string }>(
    `SELECT DISTINCT barcode FROM (
       SELECT barcode FROM price_alerts WHERE active = TRUE
       UNION
       SELECT source_barcode AS barcode FROM swap_cart_clicks
       UNION
       SELECT dupe_barcode AS barcode FROM swap_cart_clicks WHERE dupe_barcode IS NOT NULL
     ) AS src`
  );
  return rows.map(r => r.barcode);
}

function crossesThreshold(
  alert: PriceAlertRow,
  currentCents: number,
  previousCents: number | null
): boolean {
  if (alert.threshold_cents !== null && currentCents <= alert.threshold_cents) {
    return true;
  }
  if (alert.threshold_pct !== null && previousCents !== null && previousCents > 0) {
    const dropPct = ((previousCents - currentCents) / previousCents) * 100;
    if (dropPct >= alert.threshold_pct) return true;
  }
  return false;
}

function withinDedupWindow(lastNotifiedAt: string | null, now: Date): boolean {
  if (!lastNotifiedAt) return false;
  return now.getTime() - new Date(lastNotifiedAt).getTime() < DEDUP_MS;
}

export async function runPriceCheck(): Promise<{ checked: number; notified: number }> {
  const now = new Date();
  let checked = 0;
  let notified = 0;

  const barcodes = await candidateBarcodes();

  for (const barcode of barcodes) {
    // Previous latest price (before we insert this run's observation).
    const prev = await db.query<LatestPriceRow>(
      `SELECT price_cents FROM price_history
        WHERE barcode = $1 AND affiliate_network = $2
        ORDER BY recorded_at DESC LIMIT 1`,
      [barcode, AFFILIATE_NETWORK]
    );
    const previousCents = prev.rows[0]?.price_cents ?? null;

    const currentCents = await fetchAffiliatePrice(barcode);
    if (currentCents === null) continue;

    await db.query(
      `INSERT INTO price_history (barcode, affiliate_network, price_cents)
       VALUES ($1, $2, $3)`,
      [barcode, AFFILIATE_NETWORK, currentCents]
    );
    checked += 1;

    // Fan out to any active alerts on this barcode.
    const alerts = await db.query<PriceAlertRow>(
      `SELECT id, user_id, barcode, threshold_cents, threshold_pct, last_notified_at
         FROM price_alerts
        WHERE barcode = $1 AND active = TRUE`,
      [barcode]
    );

    for (const alert of alerts.rows) {
      if (withinDedupWindow(alert.last_notified_at, now)) continue;
      if (!crossesThreshold(alert, currentCents, previousCents)) continue;

      const dollars = (currentCents / 100).toFixed(2);
      await sendPush(alert.user_id, {
        title: 'Price drop alert',
        body: `The price just dropped to $${dollars}.`,
        data: {
          type: 'price_drop',
          barcode: alert.barcode,
          priceCents: currentCents,
        },
      });

      await db.query(
        `UPDATE price_alerts SET last_notified_at = NOW() WHERE id = $1`,
        [alert.id]
      );
      notified += 1;
    }
  }

  logger.info({ event: 'price_check_done', checked, notified });
  return { checked, notified };
}
