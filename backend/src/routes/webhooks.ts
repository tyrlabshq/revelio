import { Router } from 'express';
import crypto from 'crypto';
import { db } from '../db';
import { processReferralCommission } from './referrals';

export const webhookRouter = Router();

const REVENUECAT_WEBHOOK_SECRET = process.env.REVENUECAT_WEBHOOK_SECRET;

// ─── Signature verification ───────────────────────────────────────────────────

function verifyRevenueCatSignature(rawBody: string, signature: string | undefined): boolean {
  if (!REVENUECAT_WEBHOOK_SECRET) {
    if (process.env.NODE_ENV === 'production') {
      // Fail closed — never accept unsigned webhooks in production.
      console.error('[webhooks] REVENUECAT_WEBHOOK_SECRET not set in production — rejecting');
      return false;
    }
    console.warn('[webhooks] REVENUECAT_WEBHOOK_SECRET not set, skipping signature check (dev only)');
    return true;
  }
  if (!signature) return false;

  const expected = crypto
    .createHmac('sha256', REVENUECAT_WEBHOOK_SECRET)
    .update(rawBody)
    .digest('hex');

  const expectedBuf = Buffer.from(expected, 'hex');
  let actualBuf: Buffer;
  try {
    actualBuf = Buffer.from(signature, 'hex');
  } catch {
    return false;
  }
  if (actualBuf.length !== expectedBuf.length) return false;
  return crypto.timingSafeEqual(expectedBuf, actualBuf);
}

// ─── Event type mapping ───────────────────────────────────────────────────────

const PRO_EVENTS = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'PRODUCT_CHANGE',
  'TRIAL_CONVERTED',
]);

const FREE_EVENTS = new Set([
  'CANCELLATION',
  'EXPIRATION',
  'BILLING_ISSUE',
  'SUBSCRIBER_ALIAS',
]);

// ─── POST /webhooks/revenuecat ────────────────────────────────────────────────

webhookRouter.post(
  '/revenuecat',
  // Raw body middleware for signature verification
  (req, res, next) => {
    let raw = '';
    req.on('data', (chunk: Buffer) => { raw += chunk.toString(); });
    req.on('end', () => {
      (req as any).rawBody = raw;
      try {
        req.body = JSON.parse(raw);
      } catch {
        req.body = {};
      }
      next();
    });
  },
  async (req, res) => {
    const signature = req.headers['x-revenuecat-signature'] as string | undefined;
    const rawBody = (req as any).rawBody as string;

    if (!verifyRevenueCatSignature(rawBody, signature)) {
      console.warn('[webhooks] RevenueCat signature mismatch');
      return res.status(401).json({ error: 'Invalid signature' });
    }

    const event = req.body?.event;
    if (!event) {
      return res.status(400).json({ error: 'Missing event payload' });
    }

    const eventType: string = event.type || '';
    const appUserId: string = event.app_user_id || event.aliases?.[0] || '';

    console.log(`[webhooks] RevenueCat event: ${eventType} for user: ${appUserId}`);

    if (!appUserId) {
      return res.status(400).json({ error: 'Missing app_user_id' });
    }

    try {
      if (PRO_EVENTS.has(eventType)) {
        await db.query(
          `UPDATE user_profiles SET tier = 'pro', updated_at = NOW() WHERE id = $1`,
          [appUserId]
        );
        console.log(`[webhooks] Upgraded ${appUserId} to pro (${eventType})`);

        // ── Referral commission: RENEWAL and INITIAL_PURCHASE earn 20% ──
        if (eventType === 'RENEWAL' || eventType === 'INITIAL_PURCHASE' || eventType === 'TRIAL_CONVERTED') {
          const priceCents: number = Math.round((event.price || 0) * 100);
          const revCatEventId: string = event.id || `${appUserId}-${eventType}-${Date.now()}`;
          if (priceCents > 0) {
            await processReferralCommission(appUserId, priceCents, eventType, revCatEventId)
              .catch(err => console.error('[webhooks] Referral commission error:', err.message));
          }
        }
      } else if (FREE_EVENTS.has(eventType)) {
        await db.query(
          `UPDATE user_profiles SET tier = 'free', updated_at = NOW() WHERE id = $1`,
          [appUserId]
        );
        console.log(`[webhooks] Downgraded ${appUserId} to free (${eventType})`);

        // Mark attribution as inactive subscriber on cancellation/expiration
        if (eventType === 'CANCELLATION' || eventType === 'EXPIRATION') {
          await db.query(
            `UPDATE referral_attributions SET is_active_subscriber = FALSE WHERE referred_user_id = $1`,
            [appUserId]
          ).catch(err => console.error('[webhooks] Attribution update error:', err.message));
        }
      } else {
        console.log(`[webhooks] Unhandled event type: ${eventType}`);
      }

      return res.json({ ok: true, processed: eventType });
    } catch (err: any) {
      console.error('[webhooks] DB error:', err.message);
      return res.status(500).json({ error: 'Failed to process event' });
    }
  }
);
