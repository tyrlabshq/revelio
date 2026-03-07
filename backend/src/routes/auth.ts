import { Router, Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../db';

export const authRouter = Router();

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-in-prod';
const JWT_EXPIRY = '30d';
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
}

// Run on startup (non-blocking)
ensureTables().catch(err => console.error('[auth] table setup error:', err));

// ─── Twilio helpers ───────────────────────────────────────────────────────────

function twilioConfigured(): boolean {
  return !!(TWILIO_ACCOUNT_SID && TWILIO_AUTH_TOKEN && TWILIO_VERIFY_SID);
}

async function sendTwilioOTP(phone: string): Promise<void> {
  if (!twilioConfigured()) {
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
    // In dev mode, accept any 6-digit code or "123456"
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

    const token = jwt.sign(
      { userId: user.id, phone: user.phone, tier: user.tier },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
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

// ─── JWT Middleware ───────────────────────────────────────────────────────────

export interface AuthRequest extends Request {
  user?: { userId: string; phone: string; tier: string };
}

export function requireAuth(req: AuthRequest, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Authorization required' });
  }
  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, JWT_SECRET) as any;
    req.user = { userId: payload.userId, phone: payload.phone, tier: payload.tier };
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}
