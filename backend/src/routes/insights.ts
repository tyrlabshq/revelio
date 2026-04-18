// ─── backend/src/routes/insights.ts ──────────────────────────────────────────
// Track 3.9 — on-demand insights digest trigger.
//
// POST /insights/send-now  (requireAuth)
//   Generates and (if a provider is configured) sends the weekly digest for
//   the authenticated user. Always returns the rendered body, making it safe
//   for debugging / preview and for "email me my weekly insights" UX.

import { Router } from 'express';
import { requireAuth, AuthRequest } from './auth';
import { buildDigestForUser } from '../jobs/weeklyInsights';

export const insightsRouter = Router();

insightsRouter.post('/send-now', requireAuth, async (req: AuthRequest, res) => {
  const userId = req.user!.userId;
  try {
    const result = await buildDigestForUser(userId);
    res.json({
      ok: true,
      userId: result.userId,
      sent: result.sent,
      provider: result.provider,
      email: result.email,
      subject: result.subject,
      insights: result.insights,
      text: result.text,
      html: result.html,
    });
  } catch (err) {
    console.error('POST /insights/send-now error:', err);
    res.status(500).json({ error: 'Failed to build digest' });
  }
});
