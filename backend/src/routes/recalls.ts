import { Router, Response } from 'express';
import { db } from '../db';
import { requireAuth, AuthRequest } from './auth';
import { logger } from '../logger';

export const recallsRouter = Router();

// ─── GET /recalls/mine — user's recall notifications ─────────────────────────
//   Returns newest-first, joined with recall details so the client can
//   render cards without a second round-trip.

recallsRouter.get('/mine', requireAuth, async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;
  try {
    const result = await db.query(
      `SELECT
         n.id                       AS notification_id,
         n.barcode,
         n.notified_at,
         n.opened_at,
         r.id                       AS recall_id,
         r.recall_number,
         r.classification,
         r.product_description,
         r.reason_for_recall,
         r.recalling_firm,
         r.product_type,
         r.recall_initiation_date
       FROM recall_notifications n
       JOIN recalls r ON r.id = n.recall_id
       WHERE n.user_id = $1
       ORDER BY n.notified_at DESC
       LIMIT 100`,
      [userId]
    );
    const unreadCount = result.rows.filter(r => r.opened_at === null).length;
    res.json({ data: result.rows, unreadCount });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'recalls-mine-failed' }, '[recalls] GET /mine error');
    res.status(500).json({ error: 'Failed to fetch recalls' });
  }
});

// ─── POST /recalls/:id/opened — mark as read ─────────────────────────────────
//   :id is the RECALL id (matches the iOS client's data model). We update
//   every notification this user has for that recall.

recallsRouter.post('/:id/opened', requireAuth, async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;
  const recallId = req.params.id;

  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(recallId)) {
    return res.status(400).json({ error: 'invalid recall id' });
  }

  try {
    const result = await db.query(
      `UPDATE recall_notifications
         SET opened_at = COALESCE(opened_at, NOW())
       WHERE user_id = $1 AND recall_id = $2
       RETURNING id`,
      [userId, recallId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'notification not found' });
    }
    res.json({ ok: true, updated: result.rowCount });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'recalls-opened-failed' }, '[recalls] POST /:id/opened error');
    res.status(500).json({ error: 'Failed to mark recall opened' });
  }
});

// ─── POST /recalls/device-token — register APNs / FCM token ──────────────────

recallsRouter.post('/device-token', requireAuth, async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;
  const { platform, token } = (req.body ?? {}) as { platform?: string; token?: string };

  if (platform !== 'ios' && platform !== 'android') {
    return res.status(400).json({ error: 'platform must be "ios" or "android"' });
  }
  if (!token || typeof token !== 'string' || token.length < 8 || token.length > 4096) {
    return res.status(400).json({ error: 'token required' });
  }

  try {
    await db.query(
      `INSERT INTO device_tokens (user_id, platform, token)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, platform, token)
         DO UPDATE SET last_seen_at = NOW()`,
      [userId, platform, token]
    );
    res.json({ ok: true });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'recalls-device-token-failed' }, '[recalls] POST /device-token error');
    res.status(500).json({ error: 'Failed to register device token' });
  }
});
