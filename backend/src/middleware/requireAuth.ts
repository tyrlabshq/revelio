import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { getRedis } from './rateLimit';
import { logger } from '../logger';

export interface AuthRequest extends Request {
  user?: { userId: string; phone: string; tier: string; jti?: string; exp?: number };
}

const JWT_SECRET: string = (() => {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('JWT_SECRET environment variable is required');
  return secret;
})();

/**
 * Express middleware. Verifies the Bearer JWT, enforces the Redis revocation
 * list, and attaches a typed `req.user`.
 *
 * Fail-open on Redis errors: if the blacklist lookup throws (Redis down or
 * misconfigured) we let the request through. A short outage should not lock
 * out every user; stolen tokens still expire naturally within 15 minutes.
 */
export async function requireAuth(
  req: AuthRequest,
  res: Response,
  next: NextFunction
): Promise<void | Response> {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Authorization required' });
  }
  const token = header.slice(7);
  let payload: any;
  try {
    payload = jwt.verify(token, JWT_SECRET);
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }

  const jti: string | undefined = payload.jti;
  if (jti) {
    const redis = getRedis();
    if (redis) {
      try {
        const blacklisted = await redis.get(`blacklist:jwt:${jti}`);
        if (blacklisted) {
          return res.status(401).json({ error: 'Token has been revoked' });
        }
      } catch (err: any) {
        // Fail-open: log and continue. See the ADR in API_CHANGES_v1.md.
        logger.warn({ err: err?.message, event: 'blacklist_lookup_failed' });
      }
    }
  }

  req.user = {
    userId: payload.userId,
    phone: payload.phone,
    tier: payload.tier,
    jti: payload.jti,
    exp: payload.exp,
  };
  next();
}
