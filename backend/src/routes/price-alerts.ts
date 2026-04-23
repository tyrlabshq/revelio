// REV-20: price-drop alert CRUD.
//
// POST   /price-alerts      — upsert (user_id, barcode) with at least one threshold.
// GET    /price-alerts      — list the caller's active alerts.
// DELETE /price-alerts/:id  — soft-delete by flipping active=false.
//
// All routes pull userId from the JWT via requireAuth. No user_id is ever
// accepted from the client — DELETE matches on (id, user_id) so a caller
// cannot deactivate someone else's alert by guessing UUIDs.

import { Router } from 'express';
import { z } from 'zod';
import { db } from '../db';
import { requireAuth, AuthRequest } from './auth';
import { barcodeSchema, uuidSchema } from '../lib/zod-schemas';
import { logger } from '../logger';

export const priceAlertsRouter = Router();

// ─── Zod schemas ──────────────────────────────────────────────────────────────

const CreateBody = z
  .object({
    barcode: barcodeSchema,
    thresholdCents: z.number().int().positive().max(10_000_000).optional(),
    thresholdPct: z.number().int().min(1).max(99).optional(),
  })
  .refine(
    body => body.thresholdCents !== undefined || body.thresholdPct !== undefined,
    { message: 'At least one of thresholdCents or thresholdPct is required' }
  );

// ─── POST /price-alerts ───────────────────────────────────────────────────────

priceAlertsRouter.post('/', requireAuth, async (req: AuthRequest, res) => {
  const parsed = CreateBody.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      error: 'Invalid body',
      issues: parsed.error.issues.map(i => ({ path: i.path, message: i.message })),
    });
  }

  const userId = req.user!.userId;
  const { barcode, thresholdCents, thresholdPct } = parsed.data;

  try {
    // Upsert keyed on (user_id, barcode). ON CONFLICT re-activates and swaps
    // thresholds so toggling on after a soft-delete doesn't leave stale rows
    // behind.
    const result = await db.query(
      `INSERT INTO price_alerts (user_id, barcode, threshold_cents, threshold_pct, active)
       VALUES ($1, $2, $3, $4, TRUE)
       ON CONFLICT (user_id, barcode)
         DO UPDATE SET
           threshold_cents = EXCLUDED.threshold_cents,
           threshold_pct   = EXCLUDED.threshold_pct,
           active          = TRUE,
           last_notified_at = NULL
       RETURNING id, barcode, threshold_cents, threshold_pct, active, created_at`,
      [userId, barcode, thresholdCents ?? null, thresholdPct ?? null]
    );
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'price-alerts-post-failed' }, '[price-alerts] POST error');
    return res.status(500).json({ error: 'Failed to create price alert' });
  }
});

// ─── GET /price-alerts ────────────────────────────────────────────────────────

priceAlertsRouter.get('/', requireAuth, async (req: AuthRequest, res) => {
  const userId = req.user!.userId;
  try {
    const { rows } = await db.query(
      `SELECT id, barcode, threshold_cents, threshold_pct, active,
              created_at, last_notified_at
         FROM price_alerts
        WHERE user_id = $1 AND active = TRUE
        ORDER BY created_at DESC`,
      [userId]
    );
    return res.json({ data: rows });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'price-alerts-get-failed' }, '[price-alerts] GET error');
    return res.status(500).json({ error: 'Failed to list price alerts' });
  }
});

// ─── DELETE /price-alerts/:id ─────────────────────────────────────────────────

priceAlertsRouter.delete('/:id', requireAuth, async (req: AuthRequest, res) => {
  const parsed = uuidSchema.safeParse(req.params.id);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Invalid alert id' });
  }

  const userId = req.user!.userId;
  try {
    // The user_id filter is what makes this IDOR-safe — another user's id
    // simply matches zero rows.
    const result = await db.query(
      `UPDATE price_alerts SET active = FALSE
        WHERE id = $1 AND user_id = $2
        RETURNING id`,
      [parsed.data, userId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Alert not found' });
    }
    return res.json({ ok: true });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'price-alerts-delete-failed' }, '[price-alerts] DELETE error');
    return res.status(500).json({ error: 'Failed to delete price alert' });
  }
});
