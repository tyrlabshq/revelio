import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

const JWT_SECRET: string = (() => {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('JWT_SECRET environment variable is required');
  return secret;
})();

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

/**
 * Populate req.user if a valid Bearer token is provided; otherwise proceed
 * without user context. Use for endpoints that accept both anonymous and
 * authenticated callers (e.g. product catalog lookups).
 */
export function optionalAuth(req: AuthRequest, _res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) return next();
  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, JWT_SECRET) as any;
    req.user = { userId: payload.userId, phone: payload.phone, tier: payload.tier };
  } catch {
    // Ignore invalid tokens; treat as anonymous.
  }
  next();
}

export function signToken(
  payload: { userId: string; phone: string; tier: string },
  expiresIn: string = '7d'
): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn } as jwt.SignOptions);
}
