import { Router, Response, NextFunction } from 'express';
import { db } from '../db';
import { requireAuth, AuthRequest } from './auth';
import { LIFE_MODE_VALUES } from '../../../shared/scoring';
import { logger } from '../logger';

export const profileRouter = Router();

// Enum for the life_mode column. null = no life mode; anything else must
// match one of shared/scoring's LIFE_MODE_VALUES. Validated at PATCH time.
const LIFE_MODE_ALLOWED: readonly (string | null)[] = [...LIFE_MODE_VALUES, null];

// Every profile route is owner-scoped: reject if the authenticated user
// is not the owner of :id. This prevents IDOR across profiles.
function requireOwner(req: AuthRequest, res: Response, next: NextFunction) {
  const ownerId = req.params.id;
  if (!req.user || req.user.userId !== ownerId) {
    return res.status(403).json({ error: 'Forbidden' });
  }
  next();
}

// GET /profiles/:id — fetch a profile with goals + allergies
profileRouter.get('/:id', requireAuth, requireOwner, async (req: AuthRequest, res) => {
  try {
    const { id } = req.params;
    const result = await db.query(
      'SELECT id, name, phone, tier, priorities, allergies, goals, life_mode FROM user_profiles WHERE id = $1',
      [id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Profile not found' });
    res.json({ profile: result.rows[0] });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'profiles-get-failed' }, 'GET /profiles/:id error');
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PATCH /profiles/:id — update priorities, allergies, goals
profileRouter.patch('/:id', requireAuth, requireOwner, async (req: AuthRequest, res) => {
  try {
    const { id } = req.params;
    const { priorities, allergies, goals, life_mode } = req.body as {
      priorities?: string[];
      allergies?: string[];
      goals?: string[];
      life_mode?: string | null;
    };

    const setClauses: string[] = [];
    const values: unknown[] = [];
    let idx = 1;

    if (priorities !== undefined) {
      setClauses.push(`priorities = $${idx++}`);
      values.push(priorities);
    }
    if (allergies !== undefined) {
      setClauses.push(`allergies = $${idx++}`);
      values.push(allergies);
    }
    if (goals !== undefined) {
      setClauses.push(`goals = $${idx++}`);
      values.push(goals);
    }
    // life_mode: null clears the mode; otherwise must be one of the
    // LIFE_MODE_VALUES from shared/scoring. Anything else is a 400.
    if (life_mode !== undefined) {
      if (!LIFE_MODE_ALLOWED.includes(life_mode as string | null)) {
        return res.status(400).json({ error: 'invalid life_mode' });
      }
      setClauses.push(`life_mode = $${idx++}`);
      values.push(life_mode);
    }

    if (setClauses.length === 0) {
      return res.status(400).json({ error: 'Nothing to update' });
    }

    setClauses.push(`updated_at = NOW()`);
    values.push(id);

    const result = await db.query(
      `UPDATE user_profiles SET ${setClauses.join(', ')} WHERE id = $${idx} RETURNING *`,
      values
    );

    if (result.rows.length === 0) return res.status(404).json({ error: 'Profile not found' });
    res.json({ profile: result.rows[0] });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'profiles-patch-failed' }, 'PATCH /profiles/:id error');
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /profiles/:id/members — list family members
profileRouter.get('/:id/members', requireAuth, requireOwner, async (req: AuthRequest, res) => {
  try {
    const { id } = req.params;
    const result = await db.query(
      'SELECT * FROM family_members WHERE owner_id = $1 ORDER BY created_at ASC',
      [id]
    );
    res.json({ members: result.rows });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'profiles-members-get-failed' }, 'GET /profiles/:id/members error');
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /profiles/:id/members — add a family member
profileRouter.post('/:id/members', requireAuth, requireOwner, async (req: AuthRequest, res) => {
  try {
    const { id } = req.params;
    const { name, is_child, goals, allergies, avatar_color } = req.body as {
      name: string;
      is_child?: boolean;
      goals?: string[];
      allergies?: string[];
      avatar_color?: string;
    };

    if (!name) return res.status(400).json({ error: 'name is required' });

    const result = await db.query(
      `INSERT INTO family_members (owner_id, name, is_child, goals, allergies, avatar_color)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [
        id,
        name,
        is_child ?? false,
        goals ?? [],
        allergies ?? [],
        avatar_color ?? '#00B87C',
      ]
    );
    res.status(201).json({ member: result.rows[0] });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'profiles-members-post-failed' }, 'POST /profiles/:id/members error');
    res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /profiles/:id/members/:memberId — remove a family member
profileRouter.delete('/:id/members/:memberId', requireAuth, requireOwner, async (req: AuthRequest, res) => {
  try {
    const { id, memberId } = req.params;
    const result = await db.query(
      'DELETE FROM family_members WHERE id = $1 AND owner_id = $2 RETURNING id',
      [memberId, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Member not found' });
    res.json({ deleted: true });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'profiles-members-delete-failed' }, 'DELETE /profiles/:id/members/:memberId error');
    res.status(500).json({ error: 'Internal server error' });
  }
});
