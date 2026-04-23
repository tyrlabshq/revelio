import rateLimit, { Options, Store } from 'express-rate-limit';
import RedisStore from 'rate-limit-redis';
import Redis from 'ioredis';
import { logger } from '../logger';

/**
 * Central rate-limit factory. Uses Redis when REDIS_URL is configured so
 * limits are enforced across multiple API instances; falls back to the
 * default in-memory store for single-process dev/test environments.
 */
let redis: Redis | null = null;
if (process.env.REDIS_URL) {
  try {
    redis = new Redis(process.env.REDIS_URL, {
      // Don't crash the process if Redis is briefly unavailable; individual
      // commands will error and the limiter will fall back to fail-open
      // behaviour (rate limits not enforced for that request).
      maxRetriesPerRequest: 2,
      enableOfflineQueue: false,
      lazyConnect: false,
    });
    redis.on('error', (err) => logger.warn({ err: err.message }, 'redis_error'));
  } catch (err: any) {
    logger.warn({ err: err?.message }, 'redis_init_failed');
    redis = null;
  }
}

export function getRedis(): Redis | null {
  return redis;
}

function buildStore(prefix: string): Store | undefined {
  if (!redis) return undefined;
  const r = redis;
  return new RedisStore({
    // rate-limit-redis expects `sendCommand(command, ...args)`. ioredis `.call`
    // is typed as a rest-spread so we dispatch through a tuple cast.
    // as any: ioredis `.call` signature is typed for statically-known command names; we forward a dynamic string.
    sendCommand: (command: string, ...args: string[]) =>
      (r.call as any)(command, ...args) as Promise<any>,
    prefix: `rl:${prefix}:`,
  }) as unknown as Store;
}

function make(prefix: string, opts: Partial<Options>) {
  return rateLimit({
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    store: buildStore(prefix),
    ...opts,
  });
}

/**
 * globalLimiter — 60 requests per minute per IP. Applied app-wide above all
 * routes in index.ts as a blanket DDOS backstop. Routes that need tighter
 * limits layer their own limiter on top.
 */
export const globalLimiter = make('global', {
  windowMs: 60 * 1000,
  limit: 60,
  message: { error: 'Too many requests, please retry in a minute.' },
});

/**
 * otpRequestLimiter — 5 OTP requests per hour per IP. Applied to
 * POST /auth/request-otp to bound SMS-cost abuse / enumeration.
 */
export const otpRequestLimiter = make('otp', {
  windowMs: 60 * 60 * 1000,
  limit: 5,
  message: { error: 'Too many OTP requests. Try again in an hour.' },
});

/**
 * scanLimiter — 60 scans per minute per IP. Exported for use on scan routes.
 * NOTE: scan.ts is owned by another agent; documented in API_CHANGES_v1.md so
 * they can wire it in when they touch the file.
 */
export const scanLimiter = make('scan', {
  windowMs: 60 * 1000,
  limit: 60,
  message: { error: 'Scan rate limit exceeded.' },
});
