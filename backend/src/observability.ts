/**
 * Observability wiring — OpenTelemetry + Sentry. Both are fail-soft:
 * if required env vars are missing we skip them so the app still boots
 * in dev / CI without any creds.
 *
 * Call order matters: `initOtel()` must run BEFORE `express` is imported
 * so the auto-instrumentation hooks catch every outgoing require.
 */

import * as Sentry from '@sentry/node';

let otelStarted = false;

/**
 * Start the OpenTelemetry NodeSDK with HTTP/Express/PG/IORedis auto-instrumentation.
 * No-op if OTEL_EXPORTER_OTLP_ENDPOINT is not set.
 */
export function initOtel(): void {
  if (otelStarted) return;
  const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
  if (!endpoint) return;

  try {
    // Lazy-require so nothing gets imported when the env isn't set.
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { NodeSDK } = require('@opentelemetry/sdk-node');
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const {
      getNodeAutoInstrumentations,
    } = require('@opentelemetry/auto-instrumentations-node');
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');

    const sdk = new NodeSDK({
      traceExporter: new OTLPTraceExporter({ url: endpoint }),
      instrumentations: [getNodeAutoInstrumentations()],
    });

    // as any: NodeSDK.start() signature changed from Promise<void> to void across
    // @opentelemetry/sdk-node versions; cast keeps us compatible with both.
    // NodeSDK.start() is synchronous in @opentelemetry/sdk-node ≥0.50.
    // It used to return a Promise<void> — cast to any to stay compatible
    // with both signatures without tripping strict mode.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (sdk as any).start();
    otelStarted = true;

    const shutdown = () => {
      // as any: NodeSDK.shutdown() return type skews across SDK versions — Promise.resolve normalizes both.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      Promise.resolve((sdk as any).shutdown()).catch(() => {}).finally(() => process.exit(0));
    };
    process.once('SIGTERM', shutdown);
    process.once('SIGINT', shutdown);
  } catch (err) {
    // Fail-soft: surface, but don't crash the server.
    // eslint-disable-next-line no-console
    console.error('[otel] failed to initialize:', err);
  }
}

/**
 * Initialize Sentry for error / performance tracking.
 * No-op if SENTRY_DSN is not set.
 */
export function initSentry(): void {
  const dsn = process.env.SENTRY_DSN;
  if (!dsn) return;

  try {
    Sentry.init({
      dsn,
      tracesSampleRate: 0.1,
      environment: process.env.NODE_ENV ?? 'development',
    });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[sentry] failed to initialize:', err);
  }
}

export { Sentry };
