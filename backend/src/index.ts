// Observability MUST be initialized before any other module loads so that
// the OTel auto-instrumentation patches express / pg / ioredis on require.
import dotenv from 'dotenv';
dotenv.config();

import { initOtel, initSentry, Sentry } from './observability';
initOtel();
initSentry();

import express from 'express';
import cors from 'cors';
import { scanRouter } from './routes/scan';
import { productRouter } from './routes/products';
import { ingredientRouter } from './routes/ingredients';
import { alternativesRouter } from './routes/alternatives';
import { pantryRouter } from './routes/pantry';
import { profileRouter } from './routes/profiles';
import { authRouter } from './routes/auth';
import { accountRouter } from './routes/account';
import { webhookRouter } from './routes/webhooks';
import { referralsRouter } from './routes/referrals';
import { scansRouter } from './routes/scans';
import { privacyRouter } from './routes/privacy';
import { contributionsRouter } from './routes/contributions';
import { swapCartRouter } from './routes/swap-cart';
import { mealPlanRouter } from './routes/meal-plan';
import { communityRouter } from './routes/community';
import { insightsRouter } from './routes/insights';
import { pRouter } from './routes/p';
import { wellKnownRouter } from './routes/well-known';
import { recallsRouter } from './routes/recalls';
import { streaksRouter } from './routes/streaks';
import { familyPlanRouter } from './routes/family-plan';
import { friendInvitesRouter } from './routes/friend-invites';
import { receiptsRouter } from './routes/receipts';
import { brandsRouter } from './routes/brands';
import { requestIdMiddleware, errorHandler } from './middleware/errorHandler';
import { ensureAlternativesTable } from './db';
import { logger, httpLogger } from './logger';
import { globalLimiter } from './middleware/rateLimit';
import { startSchedulers } from './jobs/scheduler';

// ─── Production startup guard ─────────────────────────────────────────────────
const DEV_SECRET = 'dev-secret-change-in-prod';
if (process.env.NODE_ENV === 'production') {
  const secret = process.env.JWT_SECRET;
  if (!secret || secret === DEV_SECRET || secret.length < 32) {
    console.error('FATAL: JWT_SECRET must be set to a strong value (≥32 chars) in production. Exiting.');
    process.exit(1);
  }
  if (!process.env.OPENAI_API_KEY) {
    console.error('FATAL: OPENAI_API_KEY must be set in production. Exiting.');
    process.exit(1);
  }
  if (!process.env.REVENUECAT_WEBHOOK_SECRET) {
    console.error('FATAL: REVENUECAT_WEBHOOK_SECRET must be set in production. Exiting.');
    process.exit(1);
  }
}
// ─────────────────────────────────────────────────────────────────────────────

const app = express();
const PORT = process.env.PORT || 8430;

// CORS: explicit allowlist. No substring matches — origin.includes('revelio')
// would have allowed attacker-controlled hosts like revelio.evil.com.
const defaultOrigins = [
  'https://revelio.app',
  'https://www.revelio.app',
  'https://api.revelio.app',
];
const extraOrigins = process.env.CORS_EXTRA_ORIGINS?.split(',').map(s => s.trim()).filter(Boolean) ?? [];
const devOrigins = process.env.NODE_ENV !== 'production' ? ['http://localhost:3000', 'http://localhost:8430'] : [];
const corsOrigins = new Set([...defaultOrigins, ...extraOrigins, ...devOrigins]);

app.use(cors({
  origin: (origin, callback) => {
    // Mobile apps (iOS URLSession, Android OkHttp) omit Origin. Allow, but
    // require auth middleware to protect state-changing endpoints.
    if (!origin) return callback(null, true);
    if (corsOrigins.has(origin) || origin.startsWith('capacitor://') || origin.startsWith('ionic://')) {
      return callback(null, true);
    }
    callback(new Error('Not allowed by CORS'));
  },
  credentials: true
}));

// Structured request logging with PII redaction. Mounts above routes so every
// request/response gets a correlated log line; health checks are filtered out.
app.use(httpLogger);

// /.well-known/* endpoints must be reachable by Apple's CDN and Google's
// verifier on every install/launch. Apple in particular hammers the AASA file
// and will permanently disable universal links if we 429 it. Mount BEFORE the
// global limiter so those requests bypass rate limiting entirely.
app.use('/.well-known', wellKnownRouter);

// Global rate limit: 60 req/min per IP. Must run after CORS (so OPTIONS
// preflights don't burn quota for the real request) and before express.json so
// rejected requests don't pay JSON parse cost.
app.use(globalLimiter);

app.use(express.json());
app.use(requestIdMiddleware);

app.get('/health', (_, res) => res.json({ ok: true, service: 'revelio-api', version: '1.0.0' }));

app.use('/auth', authRouter);
// GDPR endpoints (DELETE /auth/account, GET /auth/export) live under /auth so
// the public surface groups all authenticated-user actions together.
app.use('/auth', accountRouter);
app.use('/webhooks', webhookRouter);
app.use('/scan', scanRouter);
app.use('/products', productRouter);
app.use('/ingredients', ingredientRouter);
app.use('/alternatives', alternativesRouter);
app.use('/pantry', pantryRouter);
app.use('/profiles', profileRouter);
app.use('/referrals', referralsRouter);
app.use('/scans', scansRouter);
app.use('/privacy', privacyRouter);
app.use('/contributions', contributionsRouter);
app.use('/swap-cart', swapCartRouter);
app.use('/meal-plan', mealPlanRouter);
app.use('/community', communityRouter);
app.use('/insights', insightsRouter);
app.use('/recalls', recallsRouter);
app.use('/streaks', streaksRouter);
app.use('/family-plan', familyPlanRouter);
app.use('/friend-invites', friendInvitesRouter);
app.use('/receipts', receiptsRouter);
app.use('/brands', brandsRouter);
// Public SSR preview pages for shareable links (TikTok/bio/etc). No auth —
// these render minimal OG-tagged HTML and trigger the iOS/Android universal
// link handoff into the app when installed.
app.use('/p', pRouter);

// ─── Error handling ───────────────────────────────────────────────────────────
// Sentry error handler (attached if the current @sentry/node exposes it —
// removed from v8's ESM API but left on the namespace for compat).
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const sentryErrHandler = (Sentry as any).Handlers?.errorHandler?.();
if (typeof sentryErrHandler === 'function') {
  app.use(sentryErrHandler);
}
app.use(errorHandler);

// Bootstrap DB tables then start
ensureAlternativesTable()
  .then(() => {
    app.listen(PORT, () => logger.info({ event: 'server_started', port: PORT }));
    startSchedulers();
  })
  .catch(err => {
    logger.error({ err: err?.message, event: 'db_bootstrap_failed' });
    process.exit(1);
  });
