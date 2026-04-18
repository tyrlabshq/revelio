import { Router } from 'express';
import { lookupProduct } from '../services/productLookup';
import { scoreProduct } from '../services/scorer';
import { logger } from '../logger';

export const pRouter = Router();

// ─── HTML helpers ─────────────────────────────────────────────────────────────
// We deliberately avoid adding a template engine (Handlebars/EJS) just for one
// SSR page — the tagged template below escapes every interpolation by default,
// so consumers never need to remember to call escapeHtml themselves. "Safe"
// chunks (e.g. nested templates that are already escaped) use the `raw()`
// wrapper to opt out.

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

// ─── Canonical URLs ───────────────────────────────────────────────────────────
// Kept in one place so the OG/Twitter tags and the App Store fallback stay in
// sync. The iOS App Store link is a placeholder until the app ships; Android
// uses the Play Store URL scheme.

const CANONICAL_HOST = 'https://revelio.app';
const APP_STORE_URL = 'https://apps.apple.com/app/revelio/id0000000000';
const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=app.revelio';

// Barcodes are GTIN-8/12/13/14 (digits only). We allow 6–14 to be forgiving for
// UPC-E / EAN-8, but reject anything that could be a path traversal or XSS
// payload. 404s for non-numeric input avoid leaking OFF error messages.
const BARCODE_RE = /^\d{6,14}$/;

// ─── GET /p/:barcode ──────────────────────────────────────────────────────────
pRouter.get('/:barcode', async (req, res) => {
  const { barcode } = req.params;

  if (!BARCODE_RE.test(barcode)) {
    res.status(400).type('text/html; charset=utf-8').send(renderError('Invalid barcode', 400).value);
    return;
  }

  try {
    const product = await lookupProduct(barcode);
    if (!product) {
      res.status(404).type('text/html; charset=utf-8').send(renderError('Product not found', 404).value);
      return;
    }

    // Score with no personalization — this is a public preview, we don't know
    // who the viewer is until they open the app.
    const score = await scoreProduct(
      product.ingredients,
      product.category,
      [],
      {
        nutriments: product.nutriments,
        offNutriScoreGrade: product.nutriScoreGrade,
        offNovaGroup: product.novaGroup,
        offEcoGrade: product.ecoScoreGrade,
      }
    );

    const page = renderProductPage({
      barcode,
      name: product.name,
      brand: product.brand,
      imageUrl: product.imageUrl,
      grade: score.grade,
      personalizedScore: score.personalizedScore,
      topFlags: score.flags
        .slice()
        .sort((a, b) => b.severity - a.severity)
        .slice(0, 3)
        .map((f) => ({ ingredient: f.ingredient, reason: f.reason, severity: f.severity })),
    });

    res
      .status(200)
      .type('text/html; charset=utf-8')
      .setHeader('Cache-Control', 'public, max-age=300, s-maxage=3600')
      .send(page.value);
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'p_route_error', barcode });
    res.status(500).type('text/html; charset=utf-8').send(renderError('Something went wrong', 500).value);
  }
});

// ─── Renderers ────────────────────────────────────────────────────────────────

interface RenderArgs {
  barcode: string;
  name: string;
  brand: string;
  imageUrl?: string;
  grade: 'A' | 'B' | 'C' | 'D' | 'F';
  personalizedScore: number;
  topFlags: Array<{ ingredient: string; reason: string; severity: number }>;
}

const GRADE_COLORS: Record<string, string> = {
  A: '#2e8b57',
  B: '#7cb342',
  C: '#f9a825',
  D: '#ef6c00',
  F: '#c62828',
};

function renderProductPage(a: RenderArgs): SafeHtml {
  const title = `${a.brand} — ${a.name} (Grade ${a.grade})`;
  const description = a.topFlags.length > 0
    ? `Revelio grade ${a.grade}. Flagged: ${a.topFlags.map((f) => f.ingredient).join(', ')}.`
    : `Revelio grade ${a.grade}. Scan more products with Revelio.`;
  const canonical = `${CANONICAL_HOST}/p/${a.barcode}`;
  const universalLink = canonical;
  const deepLink = `revelio://scan/${a.barcode}`;
  const gradeColor = GRADE_COLORS[a.grade] ?? '#555';
  const imageUrl = a.imageUrl && /^https?:\/\//.test(a.imageUrl) ? a.imageUrl : '';

  const flagsList = a.topFlags.length === 0
    ? raw('')
    : html`<ul class="flags">${a.topFlags.map(
        (f) => html`<li><strong>${f.ingredient}</strong> — ${f.reason}</li>`
      )}</ul>`;

  const ogImageTag = imageUrl
    ? html`<meta property="og:image" content="${imageUrl}" />
      <meta name="twitter:image" content="${imageUrl}" />`
    : raw('');

  // Inline redirect script: try the custom scheme first; if the user is still
  // on the page after 1.5s (no app handler), send them to the app store. The
  // 100ms initial delay lets Safari/Chrome finish their universal-link probe
  // so we don't fight the native handoff.
  const redirectScript = raw(`
    (function () {
      var deepLink = ${JSON.stringify(deepLink)};
      var storeUrl = ${JSON.stringify(APP_STORE_URL)};
      var playUrl = ${JSON.stringify(PLAY_STORE_URL)};
      var ua = navigator.userAgent || '';
      var isAndroid = /android/i.test(ua);
      var fallback = isAndroid ? playUrl : storeUrl;
      var opened = false;
      setTimeout(function () {
        var start = Date.now();
        window.location.href = deepLink;
        setTimeout(function () {
          if (!opened && Date.now() - start < 2000 && !document.hidden) {
            window.location.href = fallback;
          }
        }, 1500);
      }, 100);
      document.addEventListener('visibilitychange', function () {
        if (document.hidden) { opened = true; }
      });
    })();
  `);

  return html`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${title}</title>
<link rel="canonical" href="${canonical}" />
<meta property="og:type" content="product" />
<meta property="og:title" content="${title}" />
<meta property="og:description" content="${description}" />
<meta property="og:url" content="${canonical}" />
<meta property="og:site_name" content="Revelio" />
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="${title}" />
<meta name="twitter:description" content="${description}" />
${ogImageTag}
<meta name="apple-itunes-app" content="app-id=0000000000, app-argument=${deepLink}" />
<style>
  :root { color-scheme: light dark; }
  body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f7f7f8; color: #111; }
  .wrap { max-width: 480px; margin: 0 auto; padding: 24px 16px 48px; }
  .card { background: #fff; border-radius: 16px; padding: 20px; box-shadow: 0 2px 8px rgba(0,0,0,.06); }
  .hero { display: flex; align-items: center; gap: 16px; }
  .hero img { width: 84px; height: 84px; object-fit: contain; border-radius: 12px; background: #f0f0f2; }
  .brand { font-size: 13px; color: #666; text-transform: uppercase; letter-spacing: .04em; }
  .name { font-size: 20px; font-weight: 600; margin: 4px 0 0; line-height: 1.25; }
  .badge { display: inline-flex; align-items: center; justify-content: center; width: 72px; height: 72px; border-radius: 36px; color: #fff; font-size: 36px; font-weight: 700; margin: 16px 0; }
  .score { font-size: 14px; color: #555; margin-left: 12px; }
  .flags { padding-left: 20px; margin: 8px 0 0; }
  .flags li { margin: 4px 0; font-size: 14px; }
  .cta { display: block; text-align: center; padding: 14px 16px; border-radius: 12px; font-weight: 600; text-decoration: none; margin-top: 12px; }
  .cta-primary { background: #111; color: #fff; }
  .cta-secondary { background: #eef0f3; color: #111; }
  .foot { margin-top: 20px; font-size: 12px; color: #888; text-align: center; }
  @media (prefers-color-scheme: dark) {
    body { background: #0b0b0c; color: #f0f0f2; }
    .card { background: #161618; box-shadow: none; }
    .brand { color: #9a9aa2; }
    .score { color: #b3b3bb; }
    .cta-primary { background: #fff; color: #111; }
    .cta-secondary { background: #232327; color: #f0f0f2; }
    .hero img { background: #232327; }
    .foot { color: #6a6a72; }
  }
</style>
</head>
<body>
<div class="wrap">
  <div class="card">
    <div class="hero">
      ${imageUrl ? html`<img src="${imageUrl}" alt="" />` : raw('')}
      <div>
        <div class="brand">${a.brand}</div>
        <div class="name">${a.name}</div>
      </div>
    </div>
    <div>
      <span class="badge" style="background:${gradeColor}">${a.grade}</span>
      <span class="score">Score ${a.personalizedScore} / 100</span>
    </div>
    ${flagsList}
    <a class="cta cta-primary" href="${universalLink}">Open in Revelio</a>
    <a class="cta cta-secondary" href="${APP_STORE_URL}">Scan more products</a>
  </div>
  <div class="foot">Revelio — barcode ${a.barcode}</div>
</div>
<script>${redirectScript}</script>
</body>
</html>`;
}

function renderError(message: string, status: number): SafeHtml {
  return html`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Revelio — ${message}</title>
<style>
  body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f7f7f8; color: #111; display: flex; align-items: center; justify-content: center; min-height: 100vh; }
  .box { text-align: center; padding: 32px; }
  .code { font-size: 48px; font-weight: 700; margin-bottom: 8px; }
  a { color: #111; }
</style>
</head>
<body>
<div class="box">
  <div class="code">${status}</div>
  <div>${message}</div>
  <p><a href="${APP_STORE_URL}">Get Revelio</a></p>
</div>
</body>
</html>`;
}
