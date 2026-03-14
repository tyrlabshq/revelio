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
import { ensureAlternativesTable } from './db';

dotenv.config();

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

// Bootstrap DB tables then start
ensureAlternativesTable()
  .then(() => {
    app.listen(PORT, () => console.log(`Revelio API on :${PORT}`));
  })
  .catch(err => {
    console.error('DB bootstrap failed:', err);
    process.exit(1);
  });
