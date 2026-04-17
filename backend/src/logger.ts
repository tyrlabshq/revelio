import pino from 'pino';
import pinoHttp from 'pino-http';

/**
 * PII-safe redaction list. Pino applies this to every log record so structured
 * event fields cannot accidentally leak phone numbers, OTP codes, JWTs, or
 * user identifiers even when a developer passes them in.
 *
 * Paths use pino's bracketed wildcards so both top-level and nested fields
 * (e.g. req.headers.authorization, req.body.phone) are redacted.
 */
const REDACT_PATHS: string[] = [
  'phone',
  'phoneNumber',
  'email',
  'otp',
  'code',
  'token',
  'jwt',
  'password',
  'authorization',
  'user_id',
  'userId',
  '*.phone',
  '*.phoneNumber',
  '*.email',
  '*.otp',
  '*.code',
  '*.token',
  '*.jwt',
  '*.password',
  '*.authorization',
  '*.user_id',
  '*.userId',
  'req.headers.authorization',
  'req.headers.cookie',
  'req.body.phone',
  'req.body.phoneNumber',
  'req.body.code',
  'req.body.otp',
  'req.body.token',
  'req.body.refreshToken',
  'req.body.password',
  'req.query.phone',
  'req.query.code',
  'req.query.token',
  'res.headers["set-cookie"]',
];

export const logger = pino({
  level: process.env.LOG_LEVEL ?? (process.env.NODE_ENV === 'production' ? 'info' : 'debug'),
  redact: {
    paths: REDACT_PATHS,
    censor: '[REDACTED]',
  },
  base: { service: 'revelio-api' },
  timestamp: pino.stdTimeFunctions.isoTime,
});

/**
 * Express middleware. Logs every request/response with redaction applied to
 * headers, body, and query. Mount ABOVE route handlers in index.ts.
 */
export const httpLogger = pinoHttp({
  logger,
  // Don't spam health checks to the log.
  autoLogging: {
    ignore: (req) => req.url === '/health',
  },
  customLogLevel: (_req, res, err) => {
    if (err || res.statusCode >= 500) return 'error';
    if (res.statusCode >= 400) return 'warn';
    return 'info';
  },
});
