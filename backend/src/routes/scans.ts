import { Router } from 'express';
import { db } from '../db';

export const scansRouter = Router();

// ─── GET /scans — Paginated history with filters ──────────────────────────────
//   ?userId=<uuid>&page=1&limit=20&category=food&grade=F&from=2025-01-01&to=2025-12-31&q=cheerios

scansRouter.get('/', async (req, res) => {
  const {
    userId,
    page = '1',
    limit = '20',
    category,
    grade,
    from,
    to,
    q,
  } = req.query as Record<string, string | undefined>;

  if (!userId) return res.status(400).json({ error: 'userId is required' });

  const pageNum  = Math.max(1, parseInt(page  ?? '1',  10));
  const limitNum = Math.min(100, Math.max(1, parseInt(limit ?? '20', 10)));
  const offset   = (pageNum - 1) * limitNum;

  const conditions: string[] = ['s.user_id = $1'];
  const params: unknown[]    = [userId];
  let p = 2;

  if (category) { conditions.push(`s.category = $${p++}`); params.push(category); }
  if (grade)    { conditions.push(`UPPER(s.grade) = $${p++}`); params.push(grade.toUpperCase()); }
  if (from)     { conditions.push(`s.scanned_at >= $${p++}`); params.push(new Date(from)); }
  if (to)       { conditions.push(`s.scanned_at <= $${p++}`); params.push(new Date(to)); }
  if (q)        {
    conditions.push(`(s.product_name ILIKE $${p} OR s.brand ILIKE $${p})`);
    params.push(`%${q}%`); p++;
  }

  const where = conditions.join(' AND ');

  try {
    const [rows, countRow] = await Promise.all([
      db.query(
        `SELECT s.id, s.barcode, s.product_name, s.brand, s.category,
                s.image_url, s.score, s.grade, s.scanned_at
         FROM scans s
         WHERE ${where}
         ORDER BY s.scanned_at DESC
         LIMIT $${p} OFFSET $${p + 1}`,
        [...params, limitNum, offset]
      ),
      db.query(`SELECT COUNT(*)::int AS total FROM scans s WHERE ${where}`, params),
    ]);

    const total = countRow.rows[0]?.total ?? 0;
    res.json({
      data: rows.rows,
      page: pageNum,
      limit: limitNum,
      total,
      hasMore: offset + rows.rows.length < total,
    });
  } catch (err) {
    console.error('GET /scans error:', err);
    res.status(500).json({ error: 'Failed to fetch scan history' });
  }
});

// ─── GET /scans/insights — Weekly stats ──────────────────────────────────────

scansRouter.get('/insights', async (req, res) => {
  const { userId } = req.query as { userId?: string };
  if (!userId) return res.status(400).json({ error: 'userId is required' });

  try {
    // Weekly average score (current week Mon–Sun)
    const weekStatsQuery = await db.query(
      `SELECT
         AVG(score)::numeric(5,1)  AS avg_score,
         COUNT(*)::int              AS scan_count
       FROM scans
       WHERE user_id = $1
         AND scanned_at >= date_trunc('week', NOW())`,
      [userId]
    );

    // Last week average
    const lastWeekQuery = await db.query(
      `SELECT AVG(score)::numeric(5,1) AS avg_score
       FROM scans
       WHERE user_id = $1
         AND scanned_at >= date_trunc('week', NOW()) - INTERVAL '1 week'
         AND scanned_at <  date_trunc('week', NOW())`,
      [userId]
    );

    // Most scanned category (last 7 days)
    const categoryQuery = await db.query(
      `SELECT category, COUNT(*)::int AS cnt
       FROM scans
       WHERE user_id = $1
         AND scanned_at >= NOW() - INTERVAL '7 days'
       GROUP BY category
       ORDER BY cnt DESC
       LIMIT 1`,
      [userId]
    );

    // Total scans last 7 days (for category %)
    const totalWeekQuery = await db.query(
      `SELECT COUNT(*)::int AS total
       FROM scans
       WHERE user_id = $1
         AND scanned_at >= NOW() - INTERVAL '7 days'`,
      [userId]
    );

    // Most avoided flag (flag category appearing most in scans via flags JSONB)
    const flagQuery = await db.query(
      `SELECT flag->>'category' AS flag_cat, COUNT(*)::int AS cnt
       FROM scans s, jsonb_array_elements(s.flags) AS flag
       WHERE s.user_id = $1
         AND s.scanned_at >= NOW() - INTERVAL '7 days'
         AND (flag->>'severity')::int >= 2
       GROUP BY flag_cat
       ORDER BY cnt DESC
       LIMIT 1`,
      [userId]
    );

    // Top clean product (highest score in last 7 days)
    const topProductQuery = await db.query(
      `SELECT product_name, grade, score
       FROM scans
       WHERE user_id = $1
         AND scanned_at >= NOW() - INTERVAL '7 days'
         AND grade = 'A'
       ORDER BY score DESC
       LIMIT 1`,
      [userId]
    );

    const thisWeekAvg  = parseFloat(weekStatsQuery.rows[0]?.avg_score ?? '0');
    const lastWeekAvg  = parseFloat(lastWeekQuery.rows[0]?.avg_score ?? '0');
    const improvement  = Math.round(thisWeekAvg - lastWeekAvg);
    const gradeForAvg  = scoreToGrade(Math.round(thisWeekAvg));

    const topCategory  = categoryQuery.rows[0]?.category ?? null;
    const totalScans   = totalWeekQuery.rows[0]?.total ?? 0;
    const categoryPct  = topCategory && totalScans > 0
      ? Math.round((categoryQuery.rows[0].cnt / totalScans) * 100)
      : 0;

    const mostAvoided  = flagQuery.rows[0]?.flag_cat ?? null;
    const topProduct   = topProductQuery.rows[0] ?? null;

    res.json({
      weekAvgScore:     Math.round(thisWeekAvg),
      weekAvgGrade:     gradeForAvg,
      lastWeekAvgScore: Math.round(lastWeekAvg),
      improvement,
      scanCountThisWeek: weekStatsQuery.rows[0]?.scan_count ?? 0,
      topCategory:       topCategory
        ? { name: topCategory, pct: categoryPct }
        : null,
      mostAvoidedIngredient: mostAvoided,
      topCleanProduct: topProduct
        ? { name: topProduct.product_name, grade: topProduct.grade, score: topProduct.score }
        : null,
    });
  } catch (err) {
    console.error('GET /scans/insights error:', err);
    res.status(500).json({ error: 'Failed to compute insights' });
  }
});

// ─── DELETE /scans/:id ────────────────────────────────────────────────────────

scansRouter.delete('/:id', async (req, res) => {
  const { id } = req.params;
  const { userId } = req.query as { userId?: string };

  if (!userId) return res.status(400).json({ error: 'userId is required' });

  try {
    const result = await db.query(
      `DELETE FROM scans WHERE id = $1 AND user_id = $2 RETURNING id`,
      [id, userId]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Scan not found or not owned by user' });
    }
    res.json({ ok: true, deleted: id });
  } catch (err) {
    console.error('DELETE /scans/:id error:', err);
    res.status(500).json({ error: 'Failed to delete scan' });
  }
});

// ─── Helper ───────────────────────────────────────────────────────────────────

function scoreToGrade(score: number): string {
  if (score >= 85) return 'A';
  if (score >= 70) return 'B';
  if (score >= 55) return 'C';
  if (score >= 40) return 'D';
  return 'F';
}
