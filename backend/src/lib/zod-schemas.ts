import { z } from 'zod';

/**
 * Shared validation schemas. Import these from route handlers rather than
 * reimplementing regex per file — keeps phone/barcode rules in lock-step.
 */

// E.164: optional '+', leading 1-9, total 8–15 digits.
export const phoneSchema = z
  .string()
  .trim()
  .min(8)
  .max(20)
  .regex(/^\+?[1-9]\d{7,14}$/, 'Invalid phone number (E.164 required)');

// 6-digit numeric OTP.
export const otpCodeSchema = z
  .string()
  .trim()
  .regex(/^\d{6}$/, 'OTP must be 6 digits');

// EAN-8, UPC-A (12), EAN-13, ITF-14.
export const barcodeSchema = z
  .string()
  .trim()
  .regex(/^\d{8}$|^\d{12}$|^\d{13}$|^\d{14}$/, 'Barcode must be 8, 12, 13, or 14 digits');

// Standard RFC 4122 UUID (any version).
export const uuidSchema = z.string().uuid();

// Refresh tokens are base64url-encoded 64 random bytes → 86 url-safe chars.
// Accept 40–512 to stay forward compatible if length changes.
export const refreshTokenSchema = z
  .string()
  .min(40)
  .max(512)
  .regex(/^[A-Za-z0-9_\-]+$/, 'Invalid refresh token format');

/**
 * Upper bounds for free-text user inputs. Not a schema — a convenience
 * constants object callers can reference.
 */
export const bodyLimits = {
  name: 100,
  handle: 64,
  platform: 32,
  reason: 500,
  textBlock: 4000,
} as const;

// ── Composite schemas for auth routes ─────────────────────────────────────────

export const requestOtpSchema = z.object({
  phone: phoneSchema,
});

export const verifyOtpSchema = z.object({
  phone: phoneSchema,
  code: otpCodeSchema,
});

export const refreshSchema = z.object({
  refreshToken: refreshTokenSchema,
});

// ── Webhook schemas ───────────────────────────────────────────────────────────

/**
 * RevenueCat payloads carry many optional fields; only assert the subset the
 * handler actually reads. `passthrough()` preserves unknowns so we don't drop
 * data we log.
 */
export const revenueCatWebhookSchema = z.object({
  event: z.object({
    type: z.string().min(1).max(64),
    app_user_id: z.string().max(256).optional(),
    aliases: z.array(z.string().max(256)).optional(),
    id: z.string().max(256).optional(),
    price: z.number().nonnegative().optional(),
  }).passthrough(),
}).passthrough();
