// REV-T3.3: Pro-only 7-day meal plan endpoint.
// TODO: assumes OPENAI_API_KEY is set in prod (enforced by the
// backend-security startup guard in index.ts).

import { Router } from 'express';
import { requireAuth, AuthRequest } from './auth';
import { generate7DayPlan } from '../services/mealPlanner';
import { logger } from '../logger';

export const mealPlanRouter = Router();

mealPlanRouter.get('/', requireAuth, async (req: AuthRequest, res) => {
  if (req.user?.tier !== 'pro') {
    return res.status(402).json({
      error: 'Pro subscription required',
      upgradeRequired: true,
    });
  }
  try {
    const plan = await generate7DayPlan({ userId: req.user.userId });
    return res.json(plan);
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'meal-plan-failed' }, '[meal-plan] error');
    return res.status(500).json({ error: 'Failed to generate meal plan' });
  }
});
