// Vitest setup: called once per test process, before any test file loads.
// Forces a predictable JWT secret + test DB URL so the helpers module can
// build an Express app and sign tokens without depending on a real .env.

process.env.NODE_ENV = 'test';
process.env.JWT_SECRET =
  process.env.JWT_SECRET ?? 'test-jwt-secret-that-is-at-least-thirty-two-chars-long';

if (!process.env.DATABASE_URL && process.env.TEST_DATABASE_URL) {
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
}
