import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../db';
import { requireAuth, AuthRequest, signToken } from '../middleware/auth';

export const authRouter = Router();

// Re-export for routes that still import from here
export { requireAuth, AuthRequest } from '../middleware/auth';

const JWT_EXPIRY = '7d';
const TWILIO_ACCOUNT_SID = process.env.TWILIO_ACCOUNT_SID;
const TWILIO_AUTH_TOKEN = process.env.TWILIO_AUTH_TOKEN;
const TWILIO_VERIFY_SID = process.env.TWILIO_VERIFY_SID;

// Brute-force protection: 5 failed OTP attempts per phone per 15 min,
// and 5 OTP requests per phone per 15 min.
const OTP_VERIFY_MAX_ATTEMPTS = 5;
const OTP_REQUEST_MAX = 5;
const OTP_WINDOW_MS = 15 * 60 * 1000;

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
  await db.query(`
    CREATE TABLE IF NOT EXISTS otp_attempts (
      phone VARCHAR(20) PRIMARY KEY,
      request_count INTEGER DEFAULT 0,
      verify_count INTEGER DEFAULT 0,
      window_start TIMESTAMPTZ DEFAULT NOW()
    )
  `);
}

ensureTables().catch(err => console.error('[auth] table setup error:', err));

// ─── OTP rate-limit helpers (atomic) ──────────────────────────────────────────

async function bumpOtpCounter(
  phone: string,
  column: 'request_count' | 'verify_count',
  max: number
): Promise<{ allowed: boolean; count: number }> {
  const reqInc = column === 'request_count' ? 1 : 0;
  const verInc = column === 'verify_count' ? 1 : 0;
  const result = await db.query(
    `INSERT INTO otp_attempts (phone, request_count, verify_count, window_start)
     VALUES ($1, $2, $3, NOW())
     ON CONFLICT (phone) DO UPDATE SET
       request_count = CASE
         WHEN otp_attempts.window_start < NOW() - INTERVAL '${OTP_WINDOW_MS} milliseconds'
           THEN $2
         ELSE otp_attempts.request_count + $2
       END,
       verify_count = CASE
         WHEN otp_attempts.window_start < NOW() - INTERVAL '${OTP_WINDOW_MS} milliseconds'
           THEN $3
         ELSE otp_attempts.verify_count + $3
       END,
       window_start = CASE
         WHEN otp_attempts.window_start < NOW() - INTERVAL '${OTP_WINDOW_MS} milliseconds'
           THEN NOW()
         ELSE otp_attempts.window_start
       END
     RETURNING ${column} AS count`,
    [phone, reqInc, verInc]
  );
  const count = result.rows[0]?.count ?? 1;
  return { allowed: count <= max, count };
}

async function resetOtpCounters(phone: string): Promise<void> {
  await db.query(
    `UPDATE otp_attempts
     SET request_count = 0, verify_count = 0, window_start = NOW()
     WHERE phone = $1`,
    [phone]
  );
}

// ─── Twilio helpers ───────────────────────────────────────────────────────────

function twilioConfigured(): boolean {
  return !!(TWILIO_ACCOUNT_SID && TWILIO_AUTH_TOKEN && TWILIO_VERIFY_SID);
}

async function sendTwilioOTP(phone: string): Promise<void> {
  if (!twilioConfigured()) {
    if (process.env.NODE_ENV === 'production') {
      throw new Error('Twilio not configured in production');
    }
    console.log(`[auth/mock] OTP requested for ${phone} — Twilio not configured, skipping`);
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
    if (process.env.NODE_ENV === 'production') {
      throw new Error('Twilio not configured in production');
    }
    console.log(`[auth/mock] OTP verify for ${phone} code=${code} — mock accepting`);
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

// ─── POST /auth/request-otp ───────────────────────────────────────────────────

authRouter.post('/request-otp', async (req, res) => {
  const { phone } = req.body as { phone?: string };

  if (!phone || !/^\+?[1-9]\d{7,14}$/.test(phone.replace(/\s/g, ''))) {
    return res.status(400).json({ error: 'Valid phone number required (E.164 format)' });
  }

  const normalizedPhone = phone.startsWith('+') ? phone : `+1${phone.replace(/\D/g, '')}`;

  const rate = await bumpOtpCounter(normalizedPhone, 'request_count', OTP_REQUEST_MAX);
  if (!rate.allowed) {
    return res.status(429).json({ error: 'Too many OTP requests. Try again later.' });
  }

  try {
    await sendTwilioOTP(normalizedPhone);
    return res.json({ ok: true, message: 'OTP sent' });
  } catch (err: any) {
    console.error('[auth] request-otp error:', err.message);
    return res.status(500).json({ error: 'Failed to send OTP' });
  }
});

// ─── POST /auth/verify-otp ────────────────────────────────────────────────────

authRouter.post('/verify-otp', async (req, res) => {
  const { phone, code } = req.body as { phone?: string; code?: string };

  if (!phone || !code) {
    return res.status(400).json({ error: 'phone and code are required' });
  }
  if (!/^\d{6}$/.test(code)) {
    return res.status(400).json({ error: 'OTP must be 6 digits' });
  }

  const normalizedPhone = phone.startsWith('+') ? phone : `+1${phone.replace(/\D/g, '')}`;

  const rate = await bumpOtpCounter(normalizedPhone, 'verify_count', OTP_VERIFY_MAX_ATTEMPTS);
  if (!rate.allowed) {
    return res.status(429).json({ error: 'Too many OTP attempts. Try again later.' });
  }

  try {
    const valid = await verifyTwilioOTP(normalizedPhone, code);
    if (!valid) {
      return res.status(401).json({ error: 'Invalid or expired OTP' });
    }

    // Successful verification — reset counters so a legitimate user isn't
    // penalized on their next login.
    await resetOtpCounters(normalizedPhone);

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

    const token = signToken(
      { userId: user.id, phone: user.phone, tier: user.tier },
      JWT_EXPIRY
    );

    return res.json({ ok: true, token, user: { id: user.id, phone: user.phone, tier: user.tier } });
  } catch (err: any) {
    console.error('[auth] verify-otp error:', err.message);
    return res.status(500).json({ error: 'Authentication failed' });
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
    console.error('[auth] me error:', err.message);
    return res.status(500).json({ error: 'Failed to fetch user' });
  }
});
