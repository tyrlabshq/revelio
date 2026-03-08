import { Router } from 'express';
import { db } from '../db';

export const profileRouter = Router();

// GET /profiles/:id — fetch a profile with goals + allergies
profileRouter.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await db.query(
      'SELECT id, name, phone, tier, priorities, allergies, goals FROM user_profiles WHERE id = $1',
      [id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Profile not found' });
    res.json({ profile: result.rows[0] });
  } catch (err) {
    console.error('GET /profiles/:id error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PATCH /profiles/:id — update priorities, allergies, goals
profileRouter.patch('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { priorities, allergies, goals } = req.body as {
      priorities?: string[];
      allergies?: string[];
      goals?: string[];
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
    console.error('PATCH /profiles/:id error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /profiles/:id/members — list family members
profileRouter.get('/:id/members', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await db.query(
      'SELECT * FROM family_members WHERE owner_id = $1 ORDER BY created_at ASC',
      [id]
    );
    res.json({ members: result.rows });
  } catch (err) {
    console.error('GET /profiles/:id/members error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /profiles/:id/members — add a family member
profileRouter.post('/:id/members', async (req, res) => {
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
    console.error('POST /profiles/:id/members error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /profiles/:id/members/:memberId — remove a family member
profileRouter.delete('/:id/members/:memberId', async (req, res) => {
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
