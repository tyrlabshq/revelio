import { Router } from 'express';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../db';
import { logger } from '../logger';
import { otpRequestLimiter, getRedis } from '../middleware/rateLimit';
import { requireAuth, AuthRequest } from '../middleware/requireAuth';
import {
  requestOtpSchema,
  verifyOtpSchema,
  refreshSchema,
} from '../lib/zod-schemas';

// Re-export for back-compat with existing callers (scans.ts, pantry.ts, etc.)
export { requireAuth, AuthRequest } from '../middleware/requireAuth';

export const authRouter = Router();

const JWT_SECRET: string = (() => {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('JWT_SECRET environment variable is required');
  return secret;
})();

// Short-lived access token; rotate via refresh token below.
const JWT_EXPIRY = '15m';
const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
const REFRESH_EXPIRY_DAYS = 30;
const REFRESH_EXPIRY_MS = REFRESH_EXPIRY_DAYS * 24 * 60 * 60 * 1000;

const TWILIO_ACCOUNT_SID = process.env.TWILIO_ACCOUNT_SID;
const TWILIO_AUTH_TOKEN = process.env.TWILIO_AUTH_TOKEN;
const TWILIO_VERIFY_SID = process.env.TWILIO_VERIFY_SID;

// ─── DB Setup ────────────────────────────────────────────────────────────────

async function ensureTables() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS user_profiles (
      id UUID PRIMARY KEY,
      phone VARCHAR(20) UNIQUE NOT NULL,
      tier VARCHAR(20) DEFAULT 'free',
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )
  `);
  await db.query(`
    CREATE TABLE IF NOT EXISTS scan_usage (
      user_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
      date DATE NOT NULL,
      count INTEGER DEFAULT 0,
      PRIMARY KEY (user_id, date)
    )
  `);
  // Mirror of migrations/006_refresh_tokens.sql so dev boxes without a
  // migration runner pick the table up automatically.
  await db.query(`
    CREATE TABLE IF NOT EXISTS refresh_tokens (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
      token_hash TEXT NOT NULL UNIQUE,
      expires_at TIMESTAMPTZ NOT NULL,
      revoked_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await db.query(`CREATE INDEX IF NOT EXISTS idx_refresh_user ON refresh_tokens(user_id)`);
}

// Run on startup (non-blocking)
ensureTables().catch(err => logger.error({ err: err?.message, event: 'auth_table_setup_error' }));

// ─── Twilio helpers ───────────────────────────────────────────────────────────

function twilioConfigured(): boolean {
  return !!(TWILIO_ACCOUNT_SID && TWILIO_AUTH_TOKEN && TWILIO_VERIFY_SID);
}

async function sendTwilioOTP(phone: string): Promise<void> {
  if (!twilioConfigured()) {
    // NB: do NOT include `phone` in the log payload — the redaction list
    // scrubs that path anyway but keep the code itself PII-free.
    logger.info({ event: 'otp_mock_skipped', twilioConfigured: false });
    return;
  }
  const url = `https://verify.twilio.com/v2/Services/${TWILIO_VERIFY_SID}/Verifications`;
  const body = new URLSearchParams({ To: phone, Channel: 'sms' });
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': 'Basic ' + Buffer.from(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`).toString('base64'),
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: body.toString(),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Twilio error: ${text}`);
  }
}

async function verifyTwilioOTP(phone: string, code: string): Promise<boolean> {
  if (!twilioConfigured()) {
    // Dev mode: accept any 6-digit code. We do not log phone or code.
    logger.info({ event: 'otp_mock_verify', twilioConfigured: false });
    return code.length === 6 && /^\d{6}$/.test(code);
  }
  const url = `https://verify.twilio.com/v2/Services/${TWILIO_VERIFY_SID}/VerificationCheck`;
  const body = new URLSearchParams({ To: phone, Code: code });
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': 'Basic ' + Buffer.from(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`).toString('base64'),
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: body.toString(),
  });
  if (!res.ok) return false;
  const data = await res.json() as any;
  return data.status === 'approved';
}

// ─── Token helpers ────────────────────────────────────────────────────────────

function hashRefreshToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function issueAccessToken(user: { id: string; phone: string; tier: string }): { token: string; jti: string } {
  const jti = uuidv4();
  const token = jwt.sign(
    { userId: user.id, phone: user.phone, tier: user.tier, jti },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRY }
  );
  return { token, jti };
}

async function issueRefreshToken(userId: string): Promise<string> {
  const raw = crypto.randomBytes(64).toString('base64url');
  const hash = hashRefreshToken(raw);
  const expiresAt = new Date(Date.now() + REFRESH_EXPIRY_MS);
  await db.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)`,
    [userId, hash, expiresAt]
  );
  return raw;
}

// ─── POST /auth/request-otp ───────────────────────────────────────────────────

authRouter.post('/request-otp', otpRequestLimiter, async (req, res) => {
  const parsed = requestOtpSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'Valid phone number required (E.164 format)' });
  }
  const { phone } = parsed.data;
  const normalizedPhone = phone.startsWith('+') ? phone : `+1${phone.replace(/\D/g, '')}`;

  try {
    await sendTwilioOTP(normalizedPhone);
    // Structured, PII-free log. Phone/code never hit disk.
    logger.info({ event: 'otp_requested' });
    return res.json({ ok: true, message: 'OTP sent' });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'otp_request_failed' });
    return res.status(500).json({ error: 'Failed to send OTP' });
  }
});

// ─── POST /auth/verify-otp ────────────────────────────────────────────────────

authRouter.post('/verify-otp', async (req, res) => {
  const parsed = verifyOtpSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'phone and code are required (E.164 phone, 6-digit code)' });
  }
  const { phone, code } = parsed.data;
  const normalizedPhone = phone.startsWith('+') ? phone : `+1${phone.replace(/\D/g, '')}`;

  try {
    const valid = await verifyTwilioOTP(normalizedPhone, code);
    if (!valid) {
      return res.status(401).json({ error: 'Invalid or expired OTP' });
    }

    // Upsert user_profile
    let userRow = await db.query('SELECT * FROM user_profiles WHERE phone = $1', [normalizedPhone]);
    let user = userRow.rows[0];

    if (!user) {
      const id = uuidv4();
      const result = await db.query(
        `INSERT INTO user_profiles (id, phone, tier, created_at, updated_at)
         VALUES ($1, $2, 'free', NOW(), NOW())
         ON CONFLICT (phone) DO UPDATE SET updated_at = NOW()
         RETURNING *`,
        [id, normalizedPhone]
      );
      user = result.rows[0];
    }

    const { token } = issueAccessToken(user);
    const refreshToken = await issueRefreshToken(user.id);

    logger.info({ event: 'otp_verified' });

    return res.json({
      ok: true,
      token,
      refreshToken,
      expiresIn: ACCESS_TOKEN_TTL_SECONDS,
      user: { id: user.id, phone: user.phone, tier: user.tier },
    });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'verify_otp_failed' });
    return res.status(500).json({ error: 'Authentication failed' });
  }
});

// ─── POST /auth/refresh — rotate token pair ───────────────────────────────────

authRouter.post('/refresh', async (req, res) => {
  const parsed = refreshSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: 'refreshToken is required' });
  }
  const { refreshToken } = parsed.data;
  const hash = hashRefreshToken(refreshToken);

  try {
    const row = await db.query(
      `SELECT rt.id, rt.user_id, rt.expires_at, rt.revoked_at,
              u.id AS uid, u.phone, u.tier
       FROM refresh_tokens rt
       JOIN user_profiles u ON u.id = rt.user_id
       WHERE rt.token_hash = $1`,
      [hash]
    );
    const record = row.rows[0];
    if (!record) {
      return res.status(401).json({ error: 'Invalid refresh token' });
    }
    if (record.revoked_at) {
      // Token reuse after revocation: likely theft. Revoke all tokens for the
      // user as a defensive measure.
      await db.query(
        `UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL`,
        [record.user_id]
      );
      logger.warn({ event: 'refresh_reuse_detected' });
      return res.status(401).json({ error: 'Refresh token revoked' });
    }
    if (new Date(record.expires_at).getTime() < Date.now()) {
      return res.status(401).json({ error: 'Refresh token expired' });
    }

    // Rotate: revoke old, issue new.
    await db.query(`UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = $1`, [record.id]);
    const user = { id: record.uid, phone: record.phone, tier: record.tier };
    const { token } = issueAccessToken(user);
    const newRefresh = await issueRefreshToken(user.id);

    logger.info({ event: 'token_refreshed' });

    return res.json({
      ok: true,
      token,
      refreshToken: newRefresh,
      expiresIn: ACCESS_TOKEN_TTL_SECONDS,
      user,
    });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'refresh_failed' });
    return res.status(500).json({ error: 'Failed to refresh token' });
  }
});

// ─── POST /auth/logout ────────────────────────────────────────────────────────

authRouter.post('/logout', requireAuth, async (req: AuthRequest, res) => {
  const userId = req.user!.userId;
  const jti = req.user!.jti;
  const exp = req.user!.exp;

  try {
    // Revoke every outstanding refresh token for this user.
    await db.query(
      `UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL`,
      [userId]
    );

    // Blacklist the current access JWT until its natural expiry. If Redis is
    // unavailable the access token will still expire on its own in ≤15m.
    if (jti && exp) {
      const ttl = Math.max(1, exp - Math.floor(Date.now() / 1000));
      const redis = getRedis();
      if (redis) {
        try {
          await redis.set(`blacklist:jwt:${jti}`, '1', 'EX', ttl);
        } catch (err: any) {
          logger.warn({ err: err?.message, event: 'blacklist_set_failed' });
        }
      }
    }

    logger.info({ event: 'logout' });
    return res.status(204).send();
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'logout_failed' });
    return res.status(500).json({ error: 'Failed to log out' });
  }
});

// ─── GET /auth/me ─────────────────────────────────────────────────────────────

authRouter.get('/me', requireAuth, async (req: AuthRequest, res) => {
  try {
    const userId = req.user!.userId;
    const userRow = await db.query('SELECT * FROM user_profiles WHERE id = $1', [userId]);
    const user = userRow.rows[0];

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const today = new Date().toISOString().slice(0, 10);
    const usageRow = await db.query(
      'SELECT count FROM scan_usage WHERE user_id = $1 AND date = $2',
      [userId, today]
    );
    const dailyScansUsed = usageRow.rows[0]?.count ?? 0;
    const dailyScansLimit = user.tier === 'pro' ? null : 10;

    return res.json({
      userId: user.id,
      phone: user.phone,
      tier: user.tier,
      dailyScansUsed,
      dailyScansLimit,
    });
  } catch (err: any) {
    logger.error({ err: err?.message, event: 'me_failed' });
    return res.status(500).json({ error: 'Failed to fetch user' });
  }
});
