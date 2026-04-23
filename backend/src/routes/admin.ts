import { Router, Response } from 'express';
import { db } from '../db';
import { logger } from '../logger';
import { requireAuth, AuthRequest } from '../middleware/requireAuth';
import { requireAdmin } from '../middleware/requireAdmin';

export const adminRouter = Router();

// ─── HTML helpers (mirrors backend/src/routes/p.ts) ───────────────────────────
// Same tagged-template pattern — every interpolation is HTML-escaped by
// default. Anything that needs to be rendered verbatim (nested HTML) goes
// through `raw()`. We intentionally duplicate the ~20 lines instead of
// exporting from p.ts so the two routes can evolve independently.

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

class SafeHtml {
  constructor(readonly value: string) {}
}

function raw(value: string): SafeHtml {
  return new SafeHtml(value);
}

function html(strings: TemplateStringsArray, ...values: unknown[]): SafeHtml {
  let out = strings[0];
  for (let i = 0; i < values.length; i++) {
    const v = values[i];
    if (v instanceof SafeHtml) {
      out += v.value;
    } else if (Array.isArray(v)) {
      out += v
        .map((item) => (item instanceof SafeHtml ? item.value : escapeHtml(item)))
        .join('');
    } else {
      out += escapeHtml(v);
    }
    out += strings[i + 1];
  }
  return new SafeHtml(out);
}

// ─── Data collection ──────────────────────────────────────────────────────────
// All queries are defensive: tables that landed in later migrations (brand_trends,
// creator_payouts, logs) may not exist yet in every environment. We swallow
// "relation does not exist" so the dashboard degrades gracefully rather than
// 500'ing when a dev forgets to run a migration.

interface SystemMetrics {
  usersTotal: number;
  usersNew7d: number;
  scansToday: number;
  scans7d: number;
  scansAllTime: number;
  recalls7d: number;
  pendingPayoutCents: number;
}

interface BrandTrendRow {
  brand: string;
  scan_count: number;
  avg_score: number | null;
}

interface PendingContribution {
  id: string;
  barcode: string;
  name: string | null;
  brand: string | null;
  category: string | null;
  created_at: string;
}

interface LogRow {
  level: string;
  message: string;
  created_at: string;
}

async function queryOrZero<T = unknown>(sql: string, params: unknown[] = []): Promise<T[]> {
  try {
    const r = await db.query(sql, params);
    return r.rows as T[];
  } catch (err: any) {
    // Postgres "undefined_table" — table not migrated yet. Treat as empty.
    if (err?.code === '42P01') return [];
    throw err;
  }
}

async function collectSystemMetrics(): Promise<SystemMetrics> {
  const [users, scansToday, scans7d, scansAll, recalls, payouts] = await Promise.all([
    queryOrZero<{ total: string; new7d: string }>(
      `SELECT COUNT(*)::bigint AS total,
              COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')::bigint AS new7d
         FROM user_profiles`
    ),
    queryOrZero<{ c: string }>(
      `SELECT COUNT(*)::bigint AS c FROM scans WHERE scanned_at >= date_trunc('day', NOW())`
    ),
    queryOrZero<{ c: string }>(
      `SELECT COUNT(*)::bigint AS c FROM scans WHERE scanned_at >= NOW() - INTERVAL '7 days'`
    ),
    queryOrZero<{ c: string }>(`SELECT COUNT(*)::bigint AS c FROM scans`),
    queryOrZero<{ c: string }>(
      `SELECT COUNT(*)::bigint AS c FROM recall_notifications
         WHERE notified_at >= NOW() - INTERVAL '7 days'`
    ),
    queryOrZero<{ total: string | null }>(
      `SELECT COALESCE(SUM(amount_cents), 0)::bigint AS total
         FROM creator_payouts WHERE status = 'pending'`
    ),
  ]);

  return {
    usersTotal: Number(users[0]?.total ?? 0),
    usersNew7d: Number(users[0]?.new7d ?? 0),
    scansToday: Number(scansToday[0]?.c ?? 0),
    scans7d: Number(scans7d[0]?.c ?? 0),
    scansAllTime: Number(scansAll[0]?.c ?? 0),
    recalls7d: Number(recalls[0]?.c ?? 0),
    pendingPayoutCents: Number(payouts[0]?.total ?? 0),
  };
}

async function collectBrandTrends(): Promise<BrandTrendRow[]> {
  return queryOrZero<BrandTrendRow>(
    `SELECT brand, scan_count, avg_score
       FROM brand_trends
       WHERE week_start = date_trunc('week', NOW())
       ORDER BY scan_count DESC
       LIMIT 20`
  );
}

async function collectPendingContributions(): Promise<PendingContribution[]> {
  return queryOrZero<PendingContribution>(
    `SELECT id, barcode, name, brand, category, created_at
       FROM product_contributions
       WHERE status = 'pending'
       ORDER BY created_at DESC
       LIMIT 20`
  );
}

async function collectRecentErrors(): Promise<LogRow[] | null> {
  // Pino is stdout-only by default. If ops wires a `logs` table later
  // (e.g. via pino-pg), this query will start returning rows. Until
  // then we signal "not wired" by returning null so the renderer can
  // show a placeholder instead of an empty list.
  try {
    const r = await db.query(
      `SELECT level, message, created_at
         FROM logs
         WHERE level IN ('error', 'fatal')
         ORDER BY created_at DESC
         LIMIT 20`
    );
    return r.rows as LogRow[];
  } catch (err: any) {
    if (err?.code === '42P01') return null;
    throw err;
  }
}

// ─── GET /admin — HTML dashboard ──────────────────────────────────────────────

adminRouter.get('/', requireAuth, requireAdmin, async (_req: AuthRequest, res: Response) => {
  try {
    const [metrics, brands, pending, errors] = await Promise.all([
      collectSystemMetrics(),
      collectBrandTrends(),
      collectPendingContributions(),
      collectRecentErrors(),
    ]);
    const page = renderDashboard({ metrics, brands, pending, errors });
    res
      .status(200)
      .type('text/html; charset=utf-8')
      .setHeader('Cache-Control', 'no-store')
      .send(page.value);
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'admin_dashboard_error' });
    res.status(500).type('text/html; charset=utf-8').send('<h1>Dashboard error</h1>');
  }
});

// ─── Contribution review (POST approve / reject) ──────────────────────────────
// HTML-friendly: return 303 so clicking the form link in the dashboard
// redirects back to /admin. JSON clients also get a sensible response via
// the Accept header check.

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

adminRouter.post(
  '/contributions/:id/approve',
  requireAuth,
  requireAdmin,
  async (req: AuthRequest, res: Response) => {
    const { id } = req.params;
    if (!UUID_RE.test(id)) {
      return res.status(400).json({ error: 'Invalid contribution id' });
    }
    try {
      const result = await db.query(
        `UPDATE product_contributions
            SET status = 'approved', reviewed_at = NOW()
          WHERE id = $1 AND status = 'pending'
          RETURNING id`,
        [id]
      );
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'Contribution not found or already reviewed' });
      }
      // TODO: push approved contribution to OpenFoodFacts. Existing submission
      // helper is not present in the current codebase; wire this when the
      // upstream-submission service lands.
      if (req.accepts('html')) {
        return res.redirect(303, '/admin');
      }
      return res.json({ ok: true, id, status: 'approved' });
    } catch (err: any) {
      logger.error({ err: err?.message, event: 'admin_contribution_approve_failed' });
      return res.status(500).json({ error: 'Failed to approve contribution' });
    }
  }
);

adminRouter.post(
  '/contributions/:id/reject',
  requireAuth,
  requireAdmin,
  async (req: AuthRequest, res: Response) => {
    const { id } = req.params;
    if (!UUID_RE.test(id)) {
      return res.status(400).json({ error: 'Invalid contribution id' });
    }
    try {
      const result = await db.query(
        `UPDATE product_contributions
            SET status = 'rejected', reviewed_at = NOW()
          WHERE id = $1 AND status = 'pending'
          RETURNING id`,
        [id]
      );
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'Contribution not found or already reviewed' });
      }
      if (req.accepts('html')) {
        return res.redirect(303, '/admin');
      }
      return res.json({ ok: true, id, status: 'rejected' });
    } catch (err: any) {
      logger.error({ err: err?.message, event: 'admin_contribution_reject_failed' });
      return res.status(500).json({ error: 'Failed to reject contribution' });
    }
  }
);

// ─── Rendering ────────────────────────────────────────────────────────────────

interface DashboardArgs {
  metrics: SystemMetrics;
  brands: BrandTrendRow[];
  pending: PendingContribution[];
  errors: LogRow[] | null;
}

function formatCents(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

function renderDashboard(a: DashboardArgs): SafeHtml {
  const m = a.metrics;

  const metricCards = html`
    <div class="grid">
      <div class="metric"><div class="label">Users (total)</div><div class="value">${m.usersTotal}</div><div class="sub">+${m.usersNew7d} last 7d</div></div>
      <div class="metric"><div class="label">Scans today</div><div class="value">${m.scansToday}</div><div class="sub">${m.scans7d} last 7d · ${m.scansAllTime} all-time</div></div>
      <div class="metric"><div class="label">Recalls fired</div><div class="value">${m.recalls7d}</div><div class="sub">last 7d</div></div>
      <div class="metric"><div class="label">Pending payouts</div><div class="value">${formatCents(m.pendingPayoutCents)}</div><div class="sub">creators awaiting transfer</div></div>
    </div>`;

  const brandRows = a.brands.length === 0
    ? html`<tr><td colspan="3" class="empty">No brand trend data for this week yet.</td></tr>`
    : html`${a.brands.map(
        (b) => html`<tr>
          <td>${b.brand}</td>
          <td>${b.scan_count}</td>
          <td>${b.avg_score == null ? raw('—') : Math.round(Number(b.avg_score))}</td>
        </tr>`
      )}`;

  const pendingRows = a.pending.length === 0
    ? html`<tr><td colspan="5" class="empty">No pending contributions.</td></tr>`
    : html`${a.pending.map(
        (c) => html`<tr>
          <td><code>${c.barcode}</code></td>
          <td>${c.name ?? raw('<em class="muted">unnamed</em>')}</td>
          <td>${c.brand ?? raw('—')}</td>
          <td>${c.category ?? raw('—')}</td>
          <td class="actions">
            <form method="post" action="/admin/contributions/${c.id}/approve" style="display:inline">
              <button class="btn btn-approve" type="submit">Approve</button>
            </form>
            <form method="post" action="/admin/contributions/${c.id}/reject" style="display:inline">
              <button class="btn btn-reject" type="submit">Reject</button>
            </form>
          </td>
        </tr>`
      )}`;

  const errorsBlock = a.errors == null
    ? html`<p class="muted">Enable log aggregation (write to a <code>logs</code> table) to surface errors here.</p>`
    : a.errors.length === 0
    ? html`<p class="muted">No errors in the most recent window.</p>`
    : html`<ul class="errors">${a.errors.map(
        (e) => html`<li><span class="badge-${e.level}">${e.level}</span> ${e.message} <span class="muted">${e.created_at}</span></li>`
      )}</ul>`;

  return html`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Revelio · Admin</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f7f7f8; color: #111; }
  header { background: #111; color: #fff; padding: 16px 24px; }
  header h1 { margin: 0; font-size: 18px; font-weight: 600; letter-spacing: 0.02em; }
  main { max-width: 1100px; margin: 0 auto; padding: 24px 16px 48px; }
  section { background: #fff; border-radius: 12px; padding: 20px; margin-bottom: 20px; box-shadow: 0 1px 4px rgba(0,0,0,.05); }
  section h2 { margin: 0 0 14px; font-size: 15px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; color: #444; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 12px; }
  .metric { background: #f7f7f8; border-radius: 10px; padding: 14px; }
  .metric .label { font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 0.04em; }
  .metric .value { font-size: 28px; font-weight: 700; margin: 4px 0 2px; }
  .metric .sub { font-size: 12px; color: #888; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th, td { padding: 8px 10px; text-align: left; border-bottom: 1px solid #eee; vertical-align: middle; }
  th { font-size: 11px; text-transform: uppercase; letter-spacing: 0.04em; color: #777; font-weight: 500; }
  td.empty { text-align: center; color: #888; padding: 20px; font-style: italic; }
  td.actions { white-space: nowrap; text-align: right; }
  code { font-family: ui-monospace, SFMono-Regular, monospace; font-size: 12px; background: #f0f0f2; padding: 2px 5px; border-radius: 4px; }
  .btn { border: 0; padding: 6px 12px; border-radius: 6px; font-size: 13px; font-weight: 500; cursor: pointer; margin-left: 4px; }
  .btn-approve { background: #2e8b57; color: #fff; }
  .btn-reject { background: #c62828; color: #fff; }
  .muted { color: #888; font-size: 13px; }
  .errors { padding-left: 18px; font-size: 13px; }
  .errors li { margin: 4px 0; }
  .badge-error, .badge-fatal { background: #c62828; color: #fff; padding: 1px 6px; border-radius: 4px; font-size: 11px; text-transform: uppercase; margin-right: 4px; }
  @media (prefers-color-scheme: dark) {
    body { background: #0b0b0c; color: #f0f0f2; }
    section { background: #161618; box-shadow: none; }
    section h2 { color: #b3b3bb; }
    .metric { background: #1d1d21; }
    .metric .label, .metric .sub, .muted { color: #9a9aa2; }
    th { color: #9a9aa2; }
    th, td { border-bottom-color: #232327; }
    code { background: #232327; }
  }
</style>
</head>
<body>
<header><h1>Revelio · Admin dashboard</h1></header>
<main>

<section>
  <h2>System metrics</h2>
  ${metricCards}
</section>

<section>
  <h2>Top brands this week</h2>
  <table>
    <thead><tr><th>Brand</th><th>Scans</th><th>Avg score</th></tr></thead>
    <tbody>${brandRows}</tbody>
  </table>
</section>

<section>
  <h2>Pending contributions</h2>
  <table>
    <thead><tr><th>Barcode</th><th>Name</th><th>Brand</th><th>Category</th><th></th></tr></thead>
    <tbody>${pendingRows}</tbody>
  </table>
</section>

<section>
  <h2>Recent errors</h2>
  ${errorsBlock}
</section>

</main>
</body>
</html>`;
}
