import express, { type Express } from 'express';
import cors from 'cors';
import jwt from 'jsonwebtoken';
import { randomUUID } from 'crypto';
import { db } from '../src/db';
import { scanRouter } from '../src/routes/scan';
import { productRouter } from '../src/routes/products';
import { ingredientRouter } from '../src/routes/ingredients';
import { alternativesRouter } from '../src/routes/alternatives';
import { pantryRouter } from '../src/routes/pantry';
import { profileRouter } from '../src/routes/profiles';
import { authRouter } from '../src/routes/auth';
import { accountRouter } from '../src/routes/account';
import { webhookRouter } from '../src/routes/webhooks';
import { referralsRouter } from '../src/routes/referrals';
import { scansRouter } from '../src/routes/scans';
import { privacyRouter } from '../src/routes/privacy';
import { contributionsRouter } from '../src/routes/contributions';
import { swapCartRouter } from '../src/routes/swap-cart';
import { mealPlanRouter } from '../src/routes/meal-plan';
import { communityRouter } from '../src/routes/community';
import { insightsRouter } from '../src/routes/insights';
import { pRouter } from '../src/routes/p';
import { wellKnownRouter } from '../src/routes/well-known';
import { recallsRouter } from '../src/routes/recalls';
import { streaksRouter } from '../src/routes/streaks';
import { familyPlanRouter } from '../src/routes/family-plan';
import { friendInvitesRouter } from '../src/routes/friend-invites';
import { receiptsRouter } from '../src/routes/receipts';
import { priceAlertsRouter } from '../src/routes/price-alerts';
import { adminRouter } from '../src/routes/admin';
import { statusRouter } from '../src/routes/status';
import { payoutsRouter } from '../src/routes/payouts';
import { stripeWebhookRouter } from '../src/routes/stripe-webhook';
import { brandsRouter } from '../src/routes/brands';

// Tests skip gracefully when no TEST_DATABASE_URL is configured so CI stays
// green until someone wires a postgres service container. Once it's set, all
// the assertions below become live.
export const hasTestDatabase = (): boolean => !!process.env.TEST_DATABASE_URL;

export async function buildApp(): Promise<Express> {
  const app = express();
  app.use(cors());

  // Stripe webhook receiver needs the raw body; mount BEFORE express.json() —
  // mirrors the production ordering in src/index.ts.
  app.use('/webhooks/stripe', stripeWebhookRouter);
  app.use(express.json());

  app.use('/auth', authRouter);
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
  app.use('/price-alerts', priceAlertsRouter);
  app.use('/brands', brandsRouter);
  app.use('/payouts', payoutsRouter);
  app.use('/admin', adminRouter);
  app.use('/status', statusRouter);
  app.use('/p', pRouter);
  app.use('/.well-known', wellKnownRouter);

  return app;
}

export interface TestUser {
  id: string;
  phone: string;
  token: string;
}

function signJwt(userId: string, phone: string, tier: string = 'free'): string {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('JWT_SECRET not set in test env');
  // jti lets the blacklist middleware treat each issued token independently.
  return jwt.sign({ userId, phone, tier, jti: randomUUID() }, secret, { expiresIn: '15m' });
}

export async function makeUser(tier: string = 'free'): Promise<TestUser> {
  const id = randomUUID();
  const phone = `+1555${Math.floor(1000000 + Math.random() * 9000000)}`;
  await db.query(
    `INSERT INTO user_profiles (id, phone, tier, created_at, updated_at)
     VALUES ($1, $2, $3, NOW(), NOW())
     ON CONFLICT (phone) DO UPDATE SET updated_at = NOW()`,
    [id, phone, tier]
  );
  return { id, phone, token: signJwt(id, phone, tier) };
}

/** Wipe every user-owned table so each test starts from a known state. */
export async function resetDb(): Promise<void> {
  // Order matters: children before parents to satisfy FK constraints.
  // TRUNCATE ... CASCADE keeps the statement short even as new tables land.
  await db.query(`
    TRUNCATE TABLE
      pantry_items,
      scans,
      scan_usage,
      family_members,
      family_plan_members,
      family_plan_invites,
      family_plans,
      friend_invites,
      pro_grants,
      refresh_tokens,
      referral_attributions,
      referral_earnings_log,
      referral_codes,
      recall_notifications,
      device_tokens,
      product_reviews,
      hall_of_shame_votes,
      swap_cart_clicks,
      price_alerts,
      price_history,
      user_streaks,
      product_contributions,
      user_profiles
    RESTART IDENTITY CASCADE
  `);
}
