import { Router, Request, Response } from 'express';
import { db } from '../db';
import { logger } from '../logger';

export const statusRouter = Router();

// Module-load timestamp — fine for "uptime" since the process restarts on
// every deploy. Not serialized across workers; adequate for a status page.
const STARTED_AT = new Date().toISOString();

// ─── Types ────────────────────────────────────────────────────────────────────

interface JobStatus {
  name: string;
  lastStartedAt: string | null;
  lastFinishedAt: string | null;
  lastStatus: string | null;
  lastError: string | null;
}

interface StatusPayload {
  ok: true;
  buildSha: string | null;
  startedAt: string;
  jobs: JobStatus[];
}

// ─── Data collection ──────────────────────────────────────────────────────────

async function collectJobStatus(): Promise<JobStatus[]> {
  // Latest row per job_name. DISTINCT ON is O(n log n) thanks to the
  // (job_name, started_at DESC) partial index from migration 021.
  try {
    const r = await db.query<{
      job_name: string;
      started_at: Date;
      finished_at: Date | null;
      status: string;
      error: string | null;
    }>(
      `SELECT DISTINCT ON (job_name)
              job_name, started_at, finished_at, status, error
         FROM job_runs
         ORDER BY job_name, started_at DESC`
    );
    return r.rows.map((row) => ({
      name: row.job_name,
      lastStartedAt: row.started_at ? row.started_at.toISOString() : null,
      lastFinishedAt: row.finished_at ? row.finished_at.toISOString() : null,
      lastStatus: row.status,
      // `error` may contain stack fragments; truncate so we never leak a
      // novella through the status page.
      lastError: row.error ? row.error.slice(0, 500) : null,
    }));
  } catch (err: any) {
    if (err?.code === '42P01') return []; // table not migrated
    logger.warn({ err: err?.message, event: 'status_job_query_failed' });
    return [];
  }
}

async function collectStatus(): Promise<StatusPayload> {
  const jobs = await collectJobStatus();
  return {
    ok: true,
    buildSha: process.env.GIT_SHA ?? null,
    startedAt: STARTED_AT,
    jobs,
  };
}

// ─── HTML rendering ───────────────────────────────────────────────────────────
// Tiny, escape-safe template. Same pattern as routes/p.ts + routes/admin.ts.

const ESCAPE_MAP: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
};
function escapeHtml(value: unknown): string {
  if (value == null) return '';
  return String(value).replace(/[&<>"']/g, (c) => ESCAPE_MAP[c] ?? c);
}

function renderStatusHtml(s: StatusPayload): string {
  const rows = s.jobs.length === 0
    ? `<tr><td colspan="4" class="empty">No job runs recorded yet.</td></tr>`
    : s.jobs
        .map((j) => {
          const statusClass = j.lastStatus === 'success' ? 'ok'
            : j.lastStatus === 'failed' ? 'err'
            : 'run';
          return `<tr>
            <td>${escapeHtml(j.name)}</td>
            <td class="${statusClass}">${escapeHtml(j.lastStatus ?? '—')}</td>
            <td>${escapeHtml(j.lastStartedAt ?? '—')}</td>
            <td>${escapeHtml(j.lastFinishedAt ?? '—')}</td>
          </tr>`;
        })
        .join('');

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Revelio · Status</title>
<style>
  :root { color-scheme: light dark; }
  body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f7f7f8; color: #111; }
  main { max-width: 720px; margin: 40px auto; padding: 24px; background: #fff; border-radius: 12px; box-shadow: 0 1px 4px rgba(0,0,0,.06); }
  h1 { margin: 0 0 8px; font-size: 20px; }
  .meta { color: #666; font-size: 13px; margin-bottom: 20px; }
  .meta code { background: #f0f0f2; padding: 2px 6px; border-radius: 4px; font-family: ui-monospace, monospace; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th, td { padding: 8px 10px; text-align: left; border-bottom: 1px solid #eee; }
  th { font-size: 11px; text-transform: uppercase; letter-spacing: 0.04em; color: #777; font-weight: 500; }
  td.empty { text-align: center; color: #888; padding: 20px; font-style: italic; }
  td.ok { color: #2e8b57; font-weight: 600; }
  td.err { color: #c62828; font-weight: 600; }
  td.run { color: #f9a825; font-weight: 600; }
  @media (prefers-color-scheme: dark) {
    body { background: #0b0b0c; color: #f0f0f2; }
    main { background: #161618; box-shadow: none; }
    .meta { color: #9a9aa2; }
    .meta code { background: #232327; }
    th { color: #9a9aa2; }
    th, td { border-bottom-color: #232327; }
  }
</style>
</head>
<body>
<main>
  <h1>Revelio API · ok</h1>
  <div class="meta">
    Build <code>${escapeHtml(s.buildSha ?? 'unknown')}</code>
    · started ${escapeHtml(s.startedAt)}
  </div>
  <table>
    <thead><tr><th>Job</th><th>Last status</th><th>Started</th><th>Finished</th></tr></thead>
    <tbody>${rows}</tbody>
  </table>
</main>
</body>
</html>`;
}

// ─── GET /status ──────────────────────────────────────────────────────────────
// Dual-format: respond with HTML when the client prefers it (browsers) and
// JSON otherwise (curl, Grafana synthetic probes, uptime checkers).

statusRouter.get('/', async (req: Request, res: Response) => {
  try {
    const payload = await collectStatus();
    res.setHeader('Cache-Control', 'no-store');

    // Treat explicit `?format=json` as a hard override — useful when a
    // dashboard can't be convinced to set a proper Accept header.
    const wantsJson = req.query.format === 'json' || req.accepts(['html', 'json']) === 'json';
    if (wantsJson) {
      res.json(payload);
      return;
    }
    res.type('text/html; charset=utf-8').send(renderStatusHtml(payload));
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'status_error' });
    res.status(500).json({ ok: false });
  }
});
