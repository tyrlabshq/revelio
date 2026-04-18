import { ErrorRequestHandler, RequestHandler } from 'express';
import { v4 as uuidv4 } from 'uuid';
import pino from 'pino';
import { Sentry } from '../observability';

/**
 * Shared pino logger — redacts common PII keys by default. Reused by
 * this middleware and available for import elsewhere.
 */
export const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      '*.password',
      '*.token',
      '*.otp',
      '*.phone',
      '*.email',
      '*.userId',
    ],
    censor: '[redacted]',
  },
});

/**
 * Pulls the request id from `X-Request-Id` or generates one. Attaches
 * it to `res.locals.requestId` and to the response header so clients
 * can correlate failures.
 */
export const requestIdMiddleware: RequestHandler = (req, res, next) => {
  const incoming = req.header('x-request-id');
  const id = incoming && incoming.length > 0 ? incoming : uuidv4();
  res.locals.requestId = id;
  res.setHeader('X-Request-Id', id);
  next();
};

/**
 * Terminal error handler. Logs via pino, forwards to Sentry (no-op when
 * DSN unset), and returns a sanitized 500 to the client.
 *
 * IMPORTANT: Express only recognizes this as an error handler when it
 * has the full 4-arg signature, which is why `_next` is declared even
 * though we don't call it.
 */
export const errorHandler: ErrorRequestHandler = (err, req, res, _next) => {
  const requestId = (res.locals.requestId as string | undefined) ?? uuidv4();

  logger.error(
    {
      requestId,
      method: req.method,
      path: req.path,
      err: {
        name: err?.name,
        message: err?.message,
        stack: err?.stack,
      },
    },
    'unhandled request error'
  );

  try {
    Sentry.captureException(err, { tags: { requestId } });
  } catch {
    // fail-soft — never let telemetry crash the response
  }

  if (res.headersSent) return;
  res.status(500).json({ error: 'Internal server error', requestId });
};
