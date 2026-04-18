import { Router } from 'express';
import { requireAuth, AuthRequest } from './auth';
import { explainIngredient, streamIngredientChat } from '../services/ingredientAI';
import { hasProAccess } from '../middleware/familyTier';

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
  // hasProAccess covers JWT tier + family plan membership + active pro_grants.
  const tier = (await hasProAccess(req)) ? 'pro' : 'free';

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

// ─── POST /ingredients/:name/chat (SSE) ───────────────────────────────────────
// REV-T3.1: Conversational follow-ups about a specific ingredient.
// Body: { question: string, history?: Array<{role, content}>, priorities?: string[] }
// TODO: assumes OPENAI_API_KEY is set in prod (enforced by the backend-security
// agent's startup guard in index.ts).

ingredientRouter.post('/:name/chat', requireAuth, async (req: AuthRequest, res) => {
  const { name } = req.params;
  const { question, history, priorities } = req.body as {
    question?: string;
    history?: Array<{ role: 'user' | 'assistant'; content: string }>;
    priorities?: string[];
  };

  if (!name || !question || question.trim().length === 0) {
    return res.status(400).json({ error: 'ingredient name and question are required' });
  }

  const userId = req.user!.userId;
  const tier = req.user!.tier;

  // Same rate limit as /explain for the free tier.
  const rateCheck = checkAndIncrementAIUsage(userId, tier);
  if (!rateCheck.allowed) {
    return res.status(429).json({
      error: 'Daily AI limit reached',
      limit: rateCheck.limit,
      used: rateCheck.used,
      upgradeRequired: true,
    });
  }

  // SSE headers.
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  res.flushHeaders?.();

  const ingredient = decodeURIComponent(name).trim();
  const safeHistory = Array.isArray(history)
    ? history
        .filter(h => (h.role === 'user' || h.role === 'assistant') && typeof h.content === 'string')
        .slice(-10)
    : [];
  const safePriorities = Array.isArray(priorities) ? priorities.filter(p => typeof p === 'string') : [];

  try {
    for await (const chunk of streamIngredientChat({
      ingredient,
      priorities: safePriorities,
      history: safeHistory,
      question: question.trim(),
    })) {
      // Encode safely for SSE: each newline in the payload must be prefixed
      // with `data: ` per the spec, so replace raw newlines first.
      const safe = chunk.replace(/\r?\n/g, '\ndata: ');
      res.write(`data: ${safe}\n\n`);
    }
    res.write(`event: done\ndata: [DONE]\n\n`);
    res.end();
  } catch (err: any) {
    console.error('[ingredients/chat] stream error:', err?.message || err);
    try {
      res.write(`event: error\ndata: ${JSON.stringify({ error: 'stream failed' })}\n\n`);
    } catch { /* noop */ }
    res.end();
  }
});
