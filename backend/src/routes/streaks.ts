import { Router } from 'express';
import { requireAuth, AuthRequest } from './auth';
import { getStreak, setWeeklyGoal, weeklyScanCount } from '../services/streaks';
import { logger } from '../logger';

export const streaksRouter = Router();

const MAX_WEEKLY_GOAL = 20;
const MIN_WEEKLY_GOAL = 1;

// ─── GET /streaks/me ──────────────────────────────────────────────────────────

streaksRouter.get('/me', requireAuth, async (req: AuthRequest, res) => {
  const userId = req.user!.userId;
  try {
    const [streak, weeklyProgress] = await Promise.all([
      getStreak(userId),
      weeklyScanCount(userId),
    ]);
    return res.json({
      currentStreakDays: streak.currentStreakDays,
      longestStreakDays: streak.longestStreakDays,
      lastScanDate: streak.lastScanDate,
      weeklyGoal: streak.weeklyGoal,
      weeklyProgress,
      remainingToGoal: Math.max(0, streak.weeklyGoal - weeklyProgress),
    });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'streaks-me-failed' }, '[streaks] me error');
    return res.status(500).json({ error: 'Failed to fetch streak' });
  }
});

// ─── PATCH /streaks/goal ──────────────────────────────────────────────────────

streaksRouter.patch('/goal', requireAuth, async (req: AuthRequest, res) => {
  const userId = req.user!.userId;
  const { weeklyGoal } = req.body as { weeklyGoal?: number };

  if (typeof weeklyGoal !== 'number' || !Number.isInteger(weeklyGoal)) {
    return res.status(400).json({ error: 'weeklyGoal must be an integer' });
  }
  if (weeklyGoal < MIN_WEEKLY_GOAL || weeklyGoal > MAX_WEEKLY_GOAL) {
    return res.status(400).json({
      error: `weeklyGoal must be between ${MIN_WEEKLY_GOAL} and ${MAX_WEEKLY_GOAL}`,
    });
  }

  try {
    const streak = await setWeeklyGoal(userId, weeklyGoal);
    return res.json({
      currentStreakDays: streak.currentStreakDays,
      longestStreakDays: streak.longestStreakDays,
      lastScanDate: streak.lastScanDate,
      weeklyGoal: streak.weeklyGoal,
    });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'streaks-goal-failed' }, '[streaks] goal error');
    return res.status(500).json({ error: 'Failed to update weekly goal' });
  }
});
