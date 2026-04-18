import { db } from '../db';

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

/**
 * Queues a push notification for delivery to every device token the user
 * has registered.
 *
 * MVP strategy: write the payload to `push_outbox` so tests and CI can
 * assert delivery without requiring APNs/FCM credentials. A separate
 * worker drains the outbox in production.
 *
 * TODO(push): swap in real providers once creds are wired.
 *   - iOS: use `node-apn` or the HTTP/2 endpoint at
 *     `https://api.push.apple.com/3/device/<token>` with a JWT signed by
 *     the APNs auth key (APNS_KEY_ID, APNS_TEAM_ID, APNS_AUTH_KEY).
 *   - Android: `firebase-admin` → `messaging().send({ token, ... })`
 *     using FIREBASE_SERVICE_ACCOUNT_JSON.
 *   The worker should UPDATE push_outbox SET sent_at = NOW() on success,
 *   or SET error = '<message>' on failure so retries are observable.
 */
export async function sendPush(userId: string, payload: PushPayload): Promise<void> {
  const tokens = await db.query(
    `SELECT platform, token FROM device_tokens WHERE user_id = $1`,
    [userId]
  );

  if (tokens.rowCount === 0) {
    // Still useful to record that we wanted to notify — drop a rowless
    // entry keyed only to the user so operators can see the miss.
    // Using an empty-string platform/token keeps the NOT NULL constraint
    // honest without collapsing into a real device row.
    await db.query(
      `INSERT INTO push_outbox (user_id, platform, token, title, body, data)
       VALUES ($1, 'none', '', $2, $3, $4::jsonb)`,
      [userId, payload.title, payload.body, JSON.stringify(payload.data ?? {})]
    );
    return;
  }

  // Fan out — one row per device token.
  for (const row of tokens.rows as Array<{ platform: string; token: string }>) {
    await db.query(
      `INSERT INTO push_outbox (user_id, platform, token, title, body, data)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
      [
        userId,
        row.platform,
        row.token,
        payload.title,
        payload.body,
        JSON.stringify(payload.data ?? {}),
      ]
    );
  }
}
