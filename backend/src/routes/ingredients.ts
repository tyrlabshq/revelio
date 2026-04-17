import { Router } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { db } from '../db';
import { explainIngredient } from '../services/ingredientAI';

export const ingredientRouter = Router();

// Free tier: 3 AI explain calls/day. Pro: unlimited. Persisted in Postgres so
// the limit survives restarts and works across replicas.

const FREE_TIER_AI_LIMIT = 3;

async function ensureAiUsageTable(): Promise<void> {
  await db.query(`
    CREATE TABLE IF NOT EXISTS ai_usage (
      user_id UUID NOT NULL,
      date    DATE NOT NULL,
      count   INTEGER DEFAULT 0,
      PRIMARY KEY (user_id, date)
    )
  `);
}

ensureAiUsageTable().catch(err => console.error('[ingredients] ai_usage setup:', err));

async function checkAndIncrementAIUsage(
  userId: string,
  tier: string
): Promise<{ allowed: boolean; used: number; limit: number | null }> {
  if (tier === 'pro') {
    return { allowed: true, used: 0, limit: null };
  }

  const today = new Date().toISOString().slice(0, 10);

  const result = await db.query(
    `INSERT INTO ai_usage (user_id, date, count)
     VALUES ($1, $2, 1)
     ON CONFLICT (user_id, date) DO UPDATE
       SET count = ai_usage.count + 1
       WHERE ai_usage.count < $3
     RETURNING count`,
    [userId, today, FREE_TIER_AI_LIMIT]
  );

  if (result.rowCount === 0) {
    const usage = await db.query(
      'SELECT count FROM ai_usage WHERE user_id = $1 AND date = $2',
      [userId, today]
    );
    const used = usage.rows[0]?.count ?? FREE_TIER_AI_LIMIT;
    return { allowed: false, used, limit: FREE_TIER_AI_LIMIT };
  }

  return { allowed: true, used: result.rows[0].count, limit: FREE_TIER_AI_LIMIT };
}

// ─── GET /ingredients/:name ───────────────────────────────────────────────────

ingredientRouter.get('/:name', async (_, res) => res.json({ ok: true }));

// ─── GET /ingredients/:name/explain ──────────────────────────────────────────

ingredientRouter.get('/:name/explain', requireAuth, async (req: AuthRequest, res) => {
  const { name } = req.params;
  const { priorities, category } = req.query as { priorities?: string; category?: string };

  if (!name || name.trim().length === 0) {
    return res.status(400).json({ error: 'Ingredient name is required' });
  }

  const userId = req.user!.userId;
  const tier = req.user!.tier;

  const rateCheck = await checkAndIncrementAIUsage(userId, tier);
  if (!rateCheck.allowed) {
    return res.status(429).json({
      error: 'Daily AI explain limit reached',
      limit: rateCheck.limit,
      used: rateCheck.used,
      upgradeRequired: true,
    });
  }

  const ingredientName = decodeURIComponent(name).trim().slice(0, 100);
  const productCategory = (category?.trim() || 'general').slice(0, 40);
  const userPriorities = priorities
    ? priorities.split(',').map(p => p.trim()).filter(p => p.length > 0 && p.length <= 40).slice(0, 20)
    : [];

  try {
    const result = await explainIngredient(ingredientName, productCategory, userPriorities);
    return res.json({
      explanation: result.explanation,
      cached: result.cached,
    });
  } catch (err: any) {
    console.error('[ingredients/explain] error:', err.message);
    return res.status(500).json({ error: 'Failed to generate explanation' });
  }
});
