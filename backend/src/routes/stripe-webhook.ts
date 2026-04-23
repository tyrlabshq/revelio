// Stripe webhook receiver.
//
// Stripe signs webhook bodies with a shared secret; verifying the signature
// requires the RAW request bytes, not the parsed JSON. The router attaches
// `express.raw({ type: 'application/json' })` locally so the global
// `express.json()` middleware in index.ts must be mounted AFTER this router
// (or this router must be mounted before it). See index.ts for the ordering.

import express, { Router, Response, Request } from 'express';
import Stripe from 'stripe';
import { db } from '../db';
import { logger } from '../logger';
import { isStripeConfigured, syncAccountStatus } from '../services/stripeConnect';

export const stripeWebhookRouter = Router();

let memoizedClient: InstanceType<typeof Stripe> | null = null;
function client(): InstanceType<typeof Stripe> {
  if (!memoizedClient) {
    memoizedClient = new Stripe(process.env.STRIPE_SECRET_KEY as string, {
      typescript: true,
    });
  }
  return memoizedClient;
}

stripeWebhookRouter.post(
  '/',
  express.raw({ type: 'application/json' }),
  async (req: Request, res: Response) => {
    if (!isStripeConfigured() || !process.env.STRIPE_WEBHOOK_SECRET) {
      // If the server is mis-configured we still want to 200 back so Stripe
      // doesn't hammer the endpoint, but log loudly. In production the
      // startup guard should have caught this earlier.
      logger.warn({ event: 'stripe_webhook_not_configured' });
      return res.status(200).json({ received: true });
    }

    const sig = req.headers['stripe-signature'];
    if (!sig || Array.isArray(sig)) {
      return res.status(400).json({ error: 'Missing stripe-signature header' });
    }

    // `express.raw` leaves req.body as a Buffer.
    const rawBody = req.body as Buffer;

    let event;
    try {
      event = client().webhooks.constructEvent(
        rawBody,
        sig,
        process.env.STRIPE_WEBHOOK_SECRET as string
      );
    } catch (err: any) {
      logger.warn({ event: 'stripe_webhook_bad_signature', err: err?.message });
      return res.status(400).json({ error: 'Invalid signature' });
    }

    try {
      // Cast to string: stripe-node's Stripe.Event.Type union narrows to
      // events exported in the current d.ts and omits Connect-only events
      // like transfer.paid / transfer.failed. The runtime value is always a
      // string delivered by Stripe; the cast is safe.
      switch (event.type as string) {
        case 'account.updated': {
          const account = event.data.object as { id?: string };
          if (account?.id) {
            const row = await db.query(
              `SELECT user_id FROM creator_payout_accounts WHERE stripe_account_id = $1`,
              [account.id]
            );
            if (row.rows.length > 0) {
              await syncAccountStatus(row.rows[0].user_id);
            }
          }
          break;
        }

        case 'transfer.paid': {
          const transfer = event.data.object as { id?: string };
          if (transfer?.id) {
            await db.query(
              `UPDATE creator_payouts SET status = 'transferred' WHERE stripe_transfer_id = $1`,
              [transfer.id]
            );
          }
          break;
        }

        case 'transfer.failed': {
          const transfer = event.data.object as { id?: string; failure_message?: string };
          if (transfer?.id) {
            await db.query(
              `UPDATE creator_payouts
                  SET status = 'failed',
                      description = COALESCE(description,'') || ' [webhook: ' || COALESCE($2,'transfer.failed') || ']'
                WHERE stripe_transfer_id = $1`,
              [transfer.id, (transfer.failure_message ?? '').slice(0, 300)]
            );
          }
          break;
        }

        default:
          // Unknown events are expected; Stripe retries until we 200.
          break;
      }

      return res.json({ received: true });
    } catch (err: any) {
      logger.error({ event: 'stripe_webhook_handler_failed', eventType: event.type, err: err?.message });
      // 500 so Stripe will retry — fine because our DB updates are idempotent.
      return res.status(500).json({ error: 'handler error' });
    }
  }
);
