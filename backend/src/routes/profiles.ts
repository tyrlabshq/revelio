import { Router } from 'express';
import { db } from '../db';
import { requireAuth, AuthRequest } from '../middleware/auth';

export const profileRouter = Router();

const MAX_ARRAY_LEN = 50;
const MAX_STRING_LEN = 60;

function ensureOwnsProfile(req: AuthRequest, res: any): boolean {
  if (req.user!.userId !== req.params.id) {
    res.status(403).json({ error: 'Forbidden' });
    return false;
  }
  return true;
}

function sanitizeStringArray(input: unknown): string[] | null {
  if (!Array.isArray(input)) return null;
  if (input.length > MAX_ARRAY_LEN) return null;
  const out: string[] = [];
  for (const item of input) {
    if (typeof item !== 'string') return null;
    const trimmed = item.trim();
    if (trimmed.length === 0 || trimmed.length > MAX_STRING_LEN) return null;
    out.push(trimmed);
  }
  return out;
}

// GET /profiles/:id
profileRouter.get('/:id', requireAuth, async (req: AuthRequest, res) => {
  if (!ensureOwnsProfile(req, res)) return;
  try {
    const result = await db.query(
      'SELECT id, name, phone, tier, priorities, allergies, goals FROM user_profiles WHERE id = $1',
      [req.params.id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Profile not found' });
    res.json({ profile: result.rows[0] });
  } catch (err) {
    console.error('GET /profiles/:id error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PATCH /profiles/:id
profileRouter.patch('/:id', requireAuth, async (req: AuthRequest, res) => {
  if (!ensureOwnsProfile(req, res)) return;
  try {
    const { priorities, allergies, goals } = req.body as {
      priorities?: unknown;
      allergies?: unknown;
      goals?: unknown;
    };

    const setClauses: string[] = [];
    const values: unknown[] = [];
    let idx = 1;

    if (priorities !== undefined) {
      const clean = sanitizeStringArray(priorities);
      if (clean === null) return res.status(400).json({ error: 'invalid priorities' });
      setClauses.push(`priorities = $${idx++}`);
      values.push(clean);
    }
    if (allergies !== undefined) {
      const clean = sanitizeStringArray(allergies);
      if (clean === null) return res.status(400).json({ error: 'invalid allergies' });
      setClauses.push(`allergies = $${idx++}`);
      values.push(clean);
    }
    if (goals !== undefined) {
      const clean = sanitizeStringArray(goals);
      if (clean === null) return res.status(400).json({ error: 'invalid goals' });
      setClauses.push(`goals = $${idx++}`);
      values.push(clean);
    }

    if (setClauses.length === 0) {
      return res.status(400).json({ error: 'Nothing to update' });
    }

    setClauses.push(`updated_at = NOW()`);
    values.push(req.params.id);

    const result = await db.query(
      `UPDATE user_profiles SET ${setClauses.join(', ')} WHERE id = $${idx} RETURNING *`,
      values
    );

    if (result.rows.length === 0) return res.status(404).json({ error: 'Profile not found' });
    res.json({ profile: result.rows[0] });
  } catch (err) {
    console.error('PATCH /profiles/:id error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /profiles/:id/members
profileRouter.get('/:id/members', requireAuth, async (req: AuthRequest, res) => {
  if (!ensureOwnsProfile(req, res)) return;
  try {
    const result = await db.query(
      'SELECT * FROM family_members WHERE owner_id = $1 ORDER BY created_at ASC',
      [req.params.id]
    );
    res.json({ members: result.rows });
  } catch (err) {
    console.error('GET /profiles/:id/members error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /profiles/:id/members
profileRouter.post('/:id/members', requireAuth, async (req: AuthRequest, res) => {
  if (!ensureOwnsProfile(req, res)) return;
  try {
    const { name, is_child, goals, allergies, avatar_color } = req.body as {
      name?: unknown;
      is_child?: unknown;
      goals?: unknown;
      allergies?: unknown;
      avatar_color?: unknown;
    };

    if (typeof name !== 'string' || name.trim().length === 0 || name.length > MAX_STRING_LEN) {
      return res.status(400).json({ error: 'name required (1-60 chars)' });
    }

    const goalsArr = goals === undefined ? [] : sanitizeStringArray(goals);
    const allergiesArr = allergies === undefined ? [] : sanitizeStringArray(allergies);
    if (goalsArr === null) return res.status(400).json({ error: 'invalid goals' });
    if (allergiesArr === null) return res.status(400).json({ error: 'invalid allergies' });

    const color = typeof avatar_color === 'string' && /^#[0-9A-Fa-f]{6}$/.test(avatar_color)
      ? avatar_color
      : '#00B87C';

    // Cap family size to prevent abuse.
    const countRow = await db.query(
      'SELECT COUNT(*)::int AS n FROM family_members WHERE owner_id = $1',
      [req.params.id]
    );
    if ((countRow.rows[0]?.n ?? 0) >= 20) {
      return res.status(400).json({ error: 'family member limit reached' });
    }

    const result = await db.query(
      `INSERT INTO family_members (owner_id, name, is_child, goals, allergies, avatar_color)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [req.params.id, name.trim(), is_child === true, goalsArr, allergiesArr, color]
    );
    res.status(201).json({ member: result.rows[0] });
  } catch (err) {
    console.error('POST /profiles/:id/members error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /profiles/:id/members/:memberId
profileRouter.delete('/:id/members/:memberId', requireAuth, async (req: AuthRequest, res) => {
  if (!ensureOwnsProfile(req, res)) return;
  try {
    const { id, memberId } = req.params;
    const result = await db.query(
      'DELETE FROM family_members WHERE id = $1 AND owner_id = $2 RETURNING id',
      [memberId, id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Member not found' });
    res.json({ deleted: true });
  } catch (err) {
    console.error('DELETE /profiles/:id/members/:memberId error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});
