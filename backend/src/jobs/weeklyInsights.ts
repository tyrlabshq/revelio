// ─── backend/src/jobs/weeklyInsights.ts ──────────────────────────────────────
// Track 3.9 — weekly insights digest.
//
// sendWeeklyDigest({ userId? })
//  - If userId is provided: compute + send / return one digest.
//  - If not: iterate all active users in batches, compute + send each.
//
// The SQL is duplicated from GET /scans/insights by design — this job must not
// import from routes/scans.ts (another agent's territory). The helper lives
// here so the job is self-contained.
//
// Email provider resolution:
//  - SENDGRID_API_KEY  → sendgrid REST
//  - RESEND_API_KEY    → resend REST
//  - neither           → log and return the rendered body (useful for tests)
// Uses native fetch; no new npm dependency is introduced.

import { db } from '../db';
import { logger } from '../logger';

// ─── Types ───────────────────────────────────────────────────────────────────

export interface WeeklyInsights {
  userId: string;
  weekAvgScore: number;
  weekAvgGrade: string;
  lastWeekAvgScore: number;
  improvement: number; // delta vs last week, points
  scanCountThisWeek: number;
  topCategory: { name: string; pct: number } | null;
  mostAvoidedIngredient: string | null;
  topCleanProduct: { name: string; grade: string; score: number } | null;
}

export interface DigestResult {
  userId: string;
  email: string | null;   // null if we do not have an email to send to
  insights: WeeklyInsights;
  subject: string;
  text: string;
  html: string;
  sent: boolean;           // true iff the email provider accepted the send
  provider: 'sendgrid' | 'resend' | 'none';
}

// ─── Insights SQL — duplicated from routes/scans.ts::GET /scans/insights ─────

function scoreToGrade(score: number): string {
  if (score >= 85) return 'A';
  if (score >= 70) return 'B';
  if (score >= 55) return 'C';
  if (score >= 40) return 'D';
  return 'F';
}

async function computeInsights(userId: string): Promise<WeeklyInsights> {
  const weekStatsQuery = await db.query(
    `SELECT AVG(score)::numeric(5,1) AS avg_score, COUNT(*)::int AS scan_count
     FROM scans
     WHERE user_id = $1
       AND scanned_at >= date_trunc('week', NOW())`,
    [userId]
  );

  const lastWeekQuery = await db.query(
    `SELECT AVG(score)::numeric(5,1) AS avg_score
     FROM scans
     WHERE user_id = $1
       AND scanned_at >= date_trunc('week', NOW()) - INTERVAL '1 week'
       AND scanned_at <  date_trunc('week', NOW())`,
    [userId]
  );

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

  const totalWeekQuery = await db.query(
    `SELECT COUNT(*)::int AS total
     FROM scans
     WHERE user_id = $1
       AND scanned_at >= NOW() - INTERVAL '7 days'`,
    [userId]
  );

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

  const thisWeekAvg = parseFloat(weekStatsQuery.rows[0]?.avg_score ?? '0');
  const lastWeekAvg = parseFloat(lastWeekQuery.rows[0]?.avg_score ?? '0');
  const improvement = Math.round(thisWeekAvg - lastWeekAvg);
  const gradeForAvg = scoreToGrade(Math.round(thisWeekAvg));

  const topCategory = categoryQuery.rows[0]?.category ?? null;
  const totalScans  = totalWeekQuery.rows[0]?.total ?? 0;
  const categoryPct = topCategory && totalScans > 0
    ? Math.round((categoryQuery.rows[0].cnt / totalScans) * 100)
    : 0;

  const mostAvoided = flagQuery.rows[0]?.flag_cat ?? null;
  const topProduct  = topProductQuery.rows[0] ?? null;

  return {
    userId,
    weekAvgScore: Math.round(thisWeekAvg),
    weekAvgGrade: gradeForAvg,
    lastWeekAvgScore: Math.round(lastWeekAvg),
    improvement,
    scanCountThisWeek: weekStatsQuery.rows[0]?.scan_count ?? 0,
    topCategory: topCategory ? { name: topCategory, pct: categoryPct } : null,
    mostAvoidedIngredient: mostAvoided,
    topCleanProduct: topProduct
      ? { name: topProduct.product_name, grade: topProduct.grade, score: topProduct.score }
      : null,
  };
}

// ─── Template rendering ──────────────────────────────────────────────────────

function escape(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function formatDelta(delta: number): string {
  if (delta === 0) return 'steady, no change';
  return delta > 0 ? `up ${delta} points vs last week` : `down ${Math.abs(delta)} points vs last week`;
}

export function renderDigest(insights: WeeklyInsights): { subject: string; text: string; html: string } {
  const subject = `Your Revelio week: ${insights.weekAvgGrade} (${insights.weekAvgScore})`;

  const topCat  = insights.topCategory ? `${insights.topCategory.name} (${insights.topCategory.pct}% of scans)` : 'no clear leader';
  const avoided = insights.mostAvoidedIngredient ?? 'nothing flagged repeatedly — nice';
  const clean   = insights.topCleanProduct
    ? `${insights.topCleanProduct.name} (${insights.topCleanProduct.grade}, ${insights.topCleanProduct.score})`
    : 'no A-graded scans this week';

  const text = [
    `Your Revelio week`,
    ``,
    `You scanned ${insights.scanCountThisWeek} items.`,
    `Weekly average: ${insights.weekAvgScore} (${insights.weekAvgGrade}) — ${formatDelta(insights.improvement)}.`,
    `Top category: ${topCat}.`,
    `Most-avoided ingredient category: ${avoided}.`,
    `Top clean product: ${clean}.`,
    ``,
    `Open Revelio to see more and keep the streak going.`,
  ].join('\n');

  const html = `<!doctype html>
<html><body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0d0d0d;color:#e8e8e8;padding:32px;">
  <div style="max-width:560px;margin:0 auto;background:#1a1a1a;border:1px solid #2a2a2a;border-radius:16px;padding:28px;">
    <h1 style="margin:0 0 8px;color:#fff;font-size:22px;">Your Revelio week</h1>
    <p style="color:#888;margin:0 0 20px;">${insights.scanCountThisWeek} scans &middot; ${formatDelta(insights.improvement)}</p>

    <div style="display:flex;align-items:baseline;gap:12px;margin-bottom:24px;">
      <div style="font-size:56px;font-weight:800;color:#00B87C;line-height:1;">${escape(insights.weekAvgGrade)}</div>
      <div style="color:#cccccc;">avg score <strong>${insights.weekAvgScore}</strong></div>
    </div>

    <h2 style="color:#fff;font-size:15px;margin:20px 0 6px;">Top category</h2>
    <p style="margin:0 0 14px;color:#cccccc;">${escape(topCat)}</p>

    <h2 style="color:#fff;font-size:15px;margin:20px 0 6px;">Most-avoided</h2>
    <p style="margin:0 0 14px;color:#cccccc;">${escape(avoided)}</p>

    <h2 style="color:#fff;font-size:15px;margin:20px 0 6px;">Top clean product</h2>
    <p style="margin:0 0 14px;color:#cccccc;">${escape(clean)}</p>

    <p style="margin-top:28px;color:#888;font-size:12px;">
      You're receiving this because you enabled weekly insights in Revelio.
    </p>
  </div>
</body></html>`;

  return { subject, text, html };
}

// ─── Email providers ─────────────────────────────────────────────────────────

type SendResult = { sent: boolean; provider: 'sendgrid' | 'resend' | 'none' };

async function sendViaSendGrid(
  to: string,
  subject: string,
  text: string,
  html: string
): Promise<boolean> {
  const key = process.env.SENDGRID_API_KEY;
  if (!key) return false;
  const from = process.env.EMAIL_FROM || 'Revelio <hello@revelio.app>';
  try {
    const res = await fetch('https://api.sendgrid.com/v3/mail/send', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        personalizations: [{ to: [{ email: to }] }],
        from: { email: from.replace(/^.*<|>.*$/g, '') || from },
        subject,
        content: [
          { type: 'text/plain', value: text },
          { type: 'text/html', value: html },
        ],
      }),
    });
    return res.ok;
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'weekly-insights-sendgrid-failed' }, '[weeklyInsights] sendgrid error');
    return false;
  }
}

async function sendViaResend(
  to: string,
  subject: string,
  text: string,
  html: string
): Promise<boolean> {
  const key = process.env.RESEND_API_KEY;
  if (!key) return false;
  const from = process.env.EMAIL_FROM || 'Revelio <hello@revelio.app>';
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ from, to: [to], subject, text, html }),
    });
    return res.ok;
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'weekly-insights-resend-failed' }, '[weeklyInsights] resend error');
    return false;
  }
}

async function deliver(
  to: string | null,
  subject: string,
  text: string,
  html: string
): Promise<SendResult> {
  if (!to) return { sent: false, provider: 'none' };

  if (process.env.SENDGRID_API_KEY) {
    const ok = await sendViaSendGrid(to, subject, text, html);
    return { sent: ok, provider: 'sendgrid' };
  }
  if (process.env.RESEND_API_KEY) {
    const ok = await sendViaResend(to, subject, text, html);
    return { sent: ok, provider: 'resend' };
  }

  logger.info({ event: 'weekly-insights-no-provider', subject }, '[weeklyInsights] no provider configured');
  return { sent: false, provider: 'none' };
}

// ─── Email resolution ────────────────────────────────────────────────────────
// user_profiles may not carry an email column across all deployments; probe at
// runtime so the job degrades gracefully (returns rendered body, sent=false).

let emailColumnChecked = false;
let hasEmailColumn = false;
async function resolveEmail(userId: string): Promise<string | null> {
  if (!emailColumnChecked) {
    try {
      const r = await db.query(
        `SELECT column_name FROM information_schema.columns
         WHERE table_name = 'user_profiles' AND column_name = 'email'`
      );
      hasEmailColumn = r.rowCount ? r.rowCount > 0 : false;
    } catch {
      hasEmailColumn = false;
    }
    emailColumnChecked = true;
  }
  if (!hasEmailColumn) return null;
  try {
    const r = await db.query('SELECT email FROM user_profiles WHERE id = $1', [userId]);
    const email = r.rows[0]?.email as string | undefined;
    return email && email.includes('@') ? email : null;
  } catch {
    return null;
  }
}

// ─── Public API ──────────────────────────────────────────────────────────────

export async function buildDigestForUser(userId: string): Promise<DigestResult> {
  const insights = await computeInsights(userId);
  const { subject, text, html } = renderDigest(insights);
  const email = await resolveEmail(userId);
  const { sent, provider } = await deliver(email, subject, text, html);
  return { userId, email, insights, subject, text, html, sent, provider };
}

/**
 * Send weekly digest.
 *  - If opts.userId is set, sends for that user only.
 *  - Otherwise iterates all users in batches.
 * Returns the list of DigestResult rows processed.
 */
export async function sendWeeklyDigest(
  opts: { userId?: string } = {}
): Promise<DigestResult[]> {
  if (opts.userId) {
    const one = await buildDigestForUser(opts.userId);
    return [one];
  }

  const results: DigestResult[] = [];
  const batchSize = 100;
  let offset = 0;

  // Paginate through user_profiles so we don't blow up memory on large DBs.
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const { rows } = await db.query(
      `SELECT id FROM user_profiles ORDER BY created_at ASC LIMIT $1 OFFSET $2`,
      [batchSize, offset]
    );
    if (rows.length === 0) break;

    for (const row of rows) {
      try {
        const r = await buildDigestForUser(row.id as string);
        results.push(r);
      } catch (err) {
        logger.error({ err: (err as Error)?.message, event: 'weekly-insights-user-failed' }, '[weeklyInsights] failed for user');
      }
    }

    if (rows.length < batchSize) break;
    offset += batchSize;
  }

  return results;
}
