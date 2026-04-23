// Shared ioredis client. Reused across services so we do not open a new
// TCP connection per request. When REDIS_URL is unset (local dev, CI,
// migrations job) we return null and every caller no-ops gracefully —
// Redis is a performance layer, never the source of truth.

import Redis from 'ioredis';
import { logger } from '../logger';

let client: Redis | null = null;
let initialized = false;

export function getRedis(): Redis | null {
  if (initialized) return client;
  initialized = true;

  const url = process.env.REDIS_URL;
  if (!url) {
    client = null;
    return null;
  }

  try {
    client = new Redis(url, {
      // Do not block app startup if Redis is down; we fall through to
      // Postgres + OFF on every miss.
      lazyConnect: false,
      maxRetriesPerRequest: 2,
      enableOfflineQueue: false,
    });

    client.on('error', (err) => {
      // Single error listener to avoid unhandled 'error' events crashing
      // the process. Do not log PII — barcode keys only.
      logger.error({ err: err.message, event: 'redis-client-error' }, '[redis] client error');
    });
  } catch (err) {
    logger.error({ err: (err as Error).message, event: 'redis-client-init-failed' }, '[redis] failed to construct client');
    client = null;
  }

  return client;
}
