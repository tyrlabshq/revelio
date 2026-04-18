// Shared ioredis client. Reused across services so we do not open a new
// TCP connection per request. When REDIS_URL is unset (local dev, CI,
// migrations job) we return null and every caller no-ops gracefully —
// Redis is a performance layer, never the source of truth.

import Redis from 'ioredis';

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
      console.error('[redis] client error:', err.message);
    });
  } catch (err) {
    console.error('[redis] failed to construct client:', (err as Error).message);
    client = null;
  }

  return client;
}
