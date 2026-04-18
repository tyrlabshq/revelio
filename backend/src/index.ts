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
import { webhookRouter } from './routes/webhooks';
import { referralsRouter } from './routes/referrals';
import { scansRouter } from './routes/scans';
import { privacyRouter } from './routes/privacy';
import { receiptsRouter } from './routes/receipts';
import { requestIdMiddleware, errorHandler, logger } from './middleware/errorHandler';
import { ensureAlternativesTable } from './db';

// ─── Production startup guard ─────────────────────────────────────────────────
const DEV_SECRET = 'dev-secret-change-in-prod';
if (process.env.NODE_ENV === 'production') {
  if (!process.env.JWT_SECRET || process.env.JWT_SECRET === DEV_SECRET) {
    console.error('FATAL: JWT_SECRET must be set in production. Exiting.');
    process.exit(1);
  }
}
// ─────────────────────────────────────────────────────────────────────────────

const app = express();
const PORT = process.env.PORT || 8430;

// CORS configuration - allow iOS app and web frontend
const corsOrigins = process.env.CORS_ORIGINS?.split(',') || ['http://localhost:3000', 'https://revelio.app', 'https://www.revelio.app'];
app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, curl, etc.)
    if (!origin) return callback(null, true);
    if (corsOrigins.includes(origin) || origin.startsWith('capacitor://') || origin.startsWith('ionic://') || origin.includes('revelio')) {
      return callback(null, true);
    }
    callback(new Error('Not allowed by CORS'));
  },
  credentials: true
}));
app.use(express.json());
app.use(requestIdMiddleware);

app.get('/health', (_, res) => res.json({ ok: true, service: 'revelio-api', version: '1.0.0' }));

app.use('/auth', authRouter);
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
app.use('/receipts', receiptsRouter);

// ─── Error handling ───────────────────────────────────────────────────────────
// Sentry request/error handlers are wired via the auto-instrumentation when
// OTel is active; we additionally attach Sentry.Handlers.errorHandler() if the
// current @sentry/node version exposes it (it was removed in v8's ESM API but
// left on the namespace for compat). Fail-soft if not present.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const sentryErrHandler = (Sentry as any).Handlers?.errorHandler?.();
if (typeof sentryErrHandler === 'function') {
  app.use(sentryErrHandler);
}
app.use(errorHandler);

// Bootstrap DB tables then start
ensureAlternativesTable()
  .then(() => {
    app.listen(PORT, () => logger.info({ port: PORT }, 'Revelio API listening'));
  })
  .catch(err => {
    logger.error({ err }, 'DB bootstrap failed');
    process.exit(1);
  });
