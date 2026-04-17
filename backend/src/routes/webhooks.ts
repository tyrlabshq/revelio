import { Router } from 'express';
import crypto from 'crypto';
import { db } from '../db';
import { logger } from '../logger';
import { revenueCatWebhookSchema } from '../lib/zod-schemas';
import { processReferralCommission } from './referrals';

export const webhookRouter = Router();

const REVENUECAT_WEBHOOK_SECRET = process.env.REVENUECAT_WEBHOOK_SECRET;

// ─── Signature verification ───────────────────────────────────────────────────

function verifyRevenueCatSignature(rawBody: string, signature: string | undefined): boolean {
  if (!REVENUECAT_WEBHOOK_SECRET) {
    // No secret configured — allow in dev
    logger.warn({ event: 'revenuecat_signature_skipped', reason: 'no_secret' });
    return true;
  }
  if (!signature) return false;

  const expected = crypto
    .createHmac('sha256', REVENUECAT_WEBHOOK_SECRET)
    .update(rawBody)
    .digest('hex');

  // Length mismatch would throw inside timingSafeEqual; handle up front.
  const expectedBuf = Buffer.from(expected, 'hex');
  const actualBuf = Buffer.from(signature, 'hex');
  if (expectedBuf.length !== actualBuf.length) return false;
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
      logger.warn({ event: 'revenuecat_signature_mismatch' });
      return res.status(401).json({ error: 'Invalid signature' });
    }

    const parsed = revenueCatWebhookSchema.safeParse(req.body);
    if (!parsed.success) {
      logger.warn({ event: 'revenuecat_schema_invalid', issues: parsed.error.issues.slice(0, 5) });
      return res.status(400).json({ error: 'Malformed event payload' });
    }

    const event = parsed.data.event;
    const eventType: string = event.type;
    // appUserId is a user_id-shaped field — the logger redacts it by default
    // but we also avoid including it in the message portion of any log line.
    const appUserId: string = event.app_user_id || event.aliases?.[0] || '';

    if (!appUserId) {
      return res.status(400).json({ error: 'Missing app_user_id' });
    }

    // Structured log: userId/user_id keys are on the redact list.
    logger.info({ event: 'revenuecat_event', eventType, userId: appUserId });

    try {
      if (PRO_EVENTS.has(eventType)) {
        await db.query(
          `UPDATE user_profiles SET tier = 'pro', updated_at = NOW() WHERE id = $1`,
          [appUserId]
        );
        logger.info({ event: 'subscription_upgraded', eventType, userId: appUserId });

        // ── Referral commission: RENEWAL and INITIAL_PURCHASE earn 20% ──
        if (eventType === 'RENEWAL' || eventType === 'INITIAL_PURCHASE' || eventType === 'TRIAL_CONVERTED') {
          const priceCents: number = Math.round((event.price || 0) * 100);
          const revCatEventId: string = event.id || `${appUserId}-${eventType}-${Date.now()}`;
          if (priceCents > 0) {
            await processReferralCommission(appUserId, priceCents, eventType, revCatEventId)
              .catch(err => logger.error({ err: err?.message, event: 'referral_commission_failed' }));
          }
        }
      } else if (FREE_EVENTS.has(eventType)) {
        await db.query(
          `UPDATE user_profiles SET tier = 'free', updated_at = NOW() WHERE id = $1`,
          [appUserId]
        );
        logger.info({ event: 'subscription_downgraded', eventType, userId: appUserId });

        // Mark attribution as inactive subscriber on cancellation/expiration
        if (eventType === 'CANCELLATION' || eventType === 'EXPIRATION') {
          await db.query(
            `UPDATE referral_attributions SET is_active_subscriber = FALSE WHERE referred_user_id = $1`,
            [appUserId]
          ).catch(err => logger.error({ err: err?.message, event: 'attribution_update_failed' }));
        }
      } else {
        logger.info({ event: 'revenuecat_event_unhandled', eventType });
      }

      return res.json({ ok: true, processed: eventType });
    } catch (err: any) {
      logger.error({ err: err?.message, event: 'revenuecat_db_error' });
      return res.status(500).json({ error: 'Failed to process event' });
    }
  }
);
