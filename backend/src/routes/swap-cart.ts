// REV-T3.2: Smart Swap Cart — bundle cleaner dupes for every grade-D/F pantry
// item into a single affiliate checkout URL, and log clicks for attribution.

import { Router } from 'express';
import { db } from '../db';
import { requireAuth, AuthRequest } from './auth';
import { buildSwapCart } from '../services/alternatives';
import { logger } from '../logger';

export const swapCartRouter = Router();

async function ensureClicksTable(): Promise<void> {
  // Mirrors migrations/010_swap_cart_clicks.sql so the router is
  // self-contained in dev (migrations may not have run yet).
  await db.query(`
    CREATE TABLE IF NOT EXISTS swap_cart_clicks (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL,
      source_barcode VARCHAR(20) NOT NULL,
      dupe_barcode VARCHAR(20),
      affiliate_network VARCHAR(32) NOT NULL,
      clicked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await db.query(
    `CREATE INDEX IF NOT EXISTS idx_swap_clicks_user ON swap_cart_clicks(user_id)`
  );
}
ensureClicksTable().catch(err => logger.error({ err: (err as Error)?.message, event: 'swap-cart-table-setup-failed' }, '[swap-cart] table setup error'));

// ─── GET /swap-cart ───────────────────────────────────────────────────────────
swapCartRouter.get('/', requireAuth, async (req: AuthRequest, res) => {
  try {
    const network = ((req.query.network as string) || 'amazon') as
      | 'amazon'
      | 'thrive_market'
      | 'iherb';
    const cart = await buildSwapCart(req.user!.userId, network);
    return res.json(cart);
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'swap-cart-get-failed' }, '[swap-cart] GET error');
    return res.status(500).json({ error: 'Failed to build swap cart' });
  }
});

// ─── POST /swap-cart/click ────────────────────────────────────────────────────
// Body: { sourceBarcode, dupeBarcode?, affiliateNetwork }
swapCartRouter.post('/click', requireAuth, async (req: AuthRequest, res) => {
  const { sourceBarcode, dupeBarcode, affiliateNetwork } = req.body as {
    sourceBarcode?: string;
    dupeBarcode?: string;
    affiliateNetwork?: string;
  };
  if (!sourceBarcode || !affiliateNetwork) {
    return res.status(400).json({ error: 'sourceBarcode and affiliateNetwork required' });
  }
  try {
    await db.query(
      `INSERT INTO swap_cart_clicks (user_id, source_barcode, dupe_barcode, affiliate_network)
       VALUES ($1, $2, $3, $4)`,
      [req.user!.userId, sourceBarcode, dupeBarcode ?? null, affiliateNetwork]
    );
    return res.json({ ok: true });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'swap-cart-click-failed' }, '[swap-cart] click log error');
    return res.status(500).json({ error: 'Failed to log click' });
  }
});
