import { Router } from 'express';
import { requireAuth, AuthRequest } from './auth';
import { explainIngredient } from '../services/ingredientAI';

export const ingredientRouter = Router();

// ─── In-Memory Rate Limiter ───────────────────────────────────────────────────
// Free tier: 3 AI explain calls/day. Pro: unlimited.

interface RateLimitEntry {
  count: number;
  date: string; // YYYY-MM-DD
}

const FREE_TIER_AI_LIMIT = 3;
const aiRateLimit = new Map<string, RateLimitEntry>();

function getTodayDate(): string {
  return new Date().toISOString().slice(0, 10);
}

function checkAndIncrementAIUsage(userId: string, tier: string): { allowed: boolean; used: number; limit: number | null } {
  if (tier === 'pro') {
    return { allowed: true, used: 0, limit: null };
  }

  const today = getTodayDate();
  const existing = aiRateLimit.get(userId);

  if (!existing || existing.date !== today) {
    // Fresh day (or new user)
    aiRateLimit.set(userId, { count: 1, date: today });
    return { allowed: true, used: 1, limit: FREE_TIER_AI_LIMIT };
  }

  if (existing.count >= FREE_TIER_AI_LIMIT) {
    return { allowed: false, used: existing.count, limit: FREE_TIER_AI_LIMIT };
  }

  existing.count += 1;
  aiRateLimit.set(userId, existing);
  return { allowed: true, used: existing.count, limit: FREE_TIER_AI_LIMIT };
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

  // Rate limit check
  const rateCheck = checkAndIncrementAIUsage(userId, tier);
  if (!rateCheck.allowed) {
    return res.status(429).json({
      error: 'Daily AI explain limit reached',
      limit: rateCheck.limit,
      used: rateCheck.used,
      upgradeRequired: true,
    });
  }

  const ingredientName = decodeURIComponent(name).trim();
  const productCategory = category?.trim() || 'general';
  const userPriorities = priorities
    ? priorities.split(',').map(p => p.trim()).filter(p => p.length > 0)
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
