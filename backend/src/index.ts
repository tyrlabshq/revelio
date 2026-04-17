import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
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
import { ensureAlternativesTable } from './db';

dotenv.config();

// ─── Production startup guards ────────────────────────────────────────────────
const DEV_SECRET = 'dev-secret-change-in-prod';
const isProd = process.env.NODE_ENV === 'production';

if (isProd) {
  const required: Record<string, string | undefined> = {
    JWT_SECRET: process.env.JWT_SECRET,
    DATABASE_URL: process.env.DATABASE_URL,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
    REVENUECAT_WEBHOOK_SECRET: process.env.REVENUECAT_WEBHOOK_SECRET,
    TWILIO_ACCOUNT_SID: process.env.TWILIO_ACCOUNT_SID,
    TWILIO_AUTH_TOKEN: process.env.TWILIO_AUTH_TOKEN,
    TWILIO_VERIFY_SID: process.env.TWILIO_VERIFY_SID,
    CORS_ORIGINS: process.env.CORS_ORIGINS,
  };
  const missing = Object.entries(required).filter(([, v]) => !v).map(([k]) => k);
  if (missing.length) {
    console.error(`FATAL: missing required env vars in production: ${missing.join(', ')}`);
    process.exit(1);
  }
  if (process.env.JWT_SECRET === DEV_SECRET) {
    console.error('FATAL: JWT_SECRET must not use the dev placeholder in production.');
    process.exit(1);
  }
}

const app = express();
const PORT = process.env.PORT || 8430;

// ─── CORS ─────────────────────────────────────────────────────────────────────
// Exact allowlist only. Native mobile requests have no Origin header and
// are permitted (cannot forge CSRF — no cookies, token-based auth).
const corsOrigins = (process.env.CORS_ORIGINS?.split(',').map(s => s.trim()).filter(Boolean))
  || (isProd ? [] : ['http://localhost:3000', 'https://revelio.app', 'https://www.revelio.app']);

app.use(cors({
  origin: (origin, callback) => {
    if (!origin) return callback(null, true); // native app, curl, server-to-server
    if (corsOrigins.includes(origin)) return callback(null, true);
    return callback(new Error('Not allowed by CORS'));
  },
  credentials: true,
}));

// ─── Body parser with explicit size cap ───────────────────────────────────────
// Skip the JSON middleware for the RevenueCat webhook — it needs the raw body
// to verify the HMAC signature.
app.use((req, res, next) => {
  if (req.path === '/webhooks/revenuecat') return next();
  return express.json({ limit: '64kb' })(req, res, next);
});

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

ensureAlternativesTable()
  .then(() => {
    app.listen(PORT, () => console.log(`Revelio API on :${PORT}`));
  })
  .catch(err => {
    console.error('DB bootstrap failed:', err);
    process.exit(1);
  });
