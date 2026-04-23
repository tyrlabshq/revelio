/**
 * Contract tests for /.well-known/apple-app-site-association and
 * /.well-known/assetlinks.json. These files are fetched by Apple's CDN and
 * Google's verifier; the format is prescribed by Apple + Google specs.
 */

import { describe, it, beforeAll, expect, vi } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';

const { wkDbQuery } = vi.hoisted(() => ({ wkDbQuery: vi.fn() }));
vi.mock('../src/db', () => ({
  db: { query: wkDbQuery },
  ensureAlternativesTable: vi.fn().mockResolvedValue(undefined),
}));

async function makeApp(): Promise<Express> {
  const helpers = await import('./helpers');
  return helpers.buildApp();
}

describe('GET /.well-known/apple-app-site-association', () => {
  let app: Express;
  beforeAll(async () => { app = await makeApp(); });

  it('200 with Content-Type application/json (NOT application/json-ld)', async () => {
    const res = await request(app).get('/.well-known/apple-app-site-association');
    expect(res.status).toBe(200);
    // `toMatch` tolerates charset suffixes; `not.toMatch(json-ld)` locks
    // the strict format Apple's fetcher expects.
    expect(res.headers['content-type']).toMatch(/application\/json/);
    expect(res.headers['content-type']).not.toMatch(/json-ld/);
  });

  it('body contains applinks.details[0].appIDs + appclips.apps', async () => {
    const res = await request(app).get('/.well-known/apple-app-site-association');
    expect(res.body).toHaveProperty('applinks.details');
    expect(Array.isArray(res.body.applinks.details)).toBe(true);
    expect(res.body.applinks.details[0].appIDs).toBeDefined();
    expect(Array.isArray(res.body.applinks.details[0].appIDs)).toBe(true);
    expect(res.body.applinks.details[0].appIDs[0]).toContain('app.revelio.Revelio');

    expect(res.body.appclips).toBeDefined();
    expect(Array.isArray(res.body.appclips.apps)).toBe(true);
    expect(res.body.appclips.apps[0]).toContain('app.revelio.Revelio.Clip');
  });

  it('components include the /p/* path pattern', async () => {
    const res = await request(app).get('/.well-known/apple-app-site-association');
    const components = res.body.applinks.details[0].components;
    expect(Array.isArray(components)).toBe(true);
    expect(components.some((c: { '/'?: string }) => c['/'] === '/p/*')).toBe(true);
  });
});

describe('GET /.well-known/assetlinks.json', () => {
  let app: Express;
  beforeAll(async () => { app = await makeApp(); });

  it('200 with Content-Type application/json', async () => {
    const res = await request(app).get('/.well-known/assetlinks.json');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/application\/json/);
  });

  it('matches the Digital Asset Links schema', async () => {
    const res = await request(app).get('/.well-known/assetlinks.json');
    // Root must be an array per Google's spec.
    expect(Array.isArray(res.body)).toBe(true);
    const first = res.body[0];
    expect(first.relation).toEqual(expect.arrayContaining([
      'delegate_permission/common.handle_all_urls',
    ]));
    expect(first.target.namespace).toBe('android_app');
    expect(first.target.package_name).toBe('app.revelio');
    expect(Array.isArray(first.target.sha256_cert_fingerprints)).toBe(true);
    expect(first.target.sha256_cert_fingerprints[0]).toMatch(/^[A-F0-9:]+$/i);
  });
});
