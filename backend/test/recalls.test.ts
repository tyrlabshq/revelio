/**
 * FDA recall matching + notification insertion (jobs/fdaRecalls.ts).
 *
 * Strategy: mock `services/push.sendPush` so tests don't try to reach APNs.
 * Seed a user profile, a scan for barcode X, and a recalls row whose
 * upc_codes column contains X. Running matchAndNotify should insert a
 * recall_notifications row AND enqueue a push. Running it again must NOT
 * duplicate (the ON CONFLICT DO NOTHING clause).
 *
 * DB-gated — skips without TEST_DATABASE_URL.
 */

import { describe, it, beforeAll, beforeEach, expect, vi } from 'vitest';
import { hasTestDatabase, makeUser, resetDb } from './helpers';
import { db } from '../src/db';

// Mock sendPush BEFORE importing matchAndNotify. Hoist the spy so the mock
// factory (which runs before top-level code) can reach it.
const { sendPush } = vi.hoisted(() => ({
  sendPush: vi.fn().mockResolvedValue(undefined),
}));
vi.mock('../src/services/push', () => ({
  sendPush,
}));

// Import AFTER the mock is registered so the job sees the mocked module.
import { matchAndNotify, extractUpcCodes } from '../src/jobs/fdaRecalls';

const describeIfDb = hasTestDatabase() ? describe : describe.skip;

describeIfDb('fdaRecalls.matchAndNotify', () => {
  beforeEach(async () => {
    await resetDb();
    sendPush.mockClear();
  });

  it('inserts a recall_notifications row + enqueues a push for matching scan', async () => {
    const alice = await makeUser();

    // Seed a scan whose barcode matches a synthetic recall.
    await db.query(
      `INSERT INTO scans (id, user_id, barcode, scanned_at)
         VALUES (gen_random_uuid(), $1, $2, NOW())`,
      [alice.id, '0123456789012']
    );

    const recallInsert = await db.query(
      `INSERT INTO recalls
         (recall_number, classification, product_description, reason_for_recall,
          recalling_firm, product_type, upc_codes, recall_initiation_date)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING id`,
      [
        'TEST-001',
        'Class II',
        'Test Food Product',
        'Undeclared allergen',
        'ACME Foods',
        'food',
        ['0123456789012'],
        '2025-01-01',
      ]
    );
    const recallId: string = recallInsert.rows[0].id;

    const firstRun = await matchAndNotify(recallId);
    expect(firstRun).toBe(1);
    expect(sendPush).toHaveBeenCalledTimes(1);

    const notifications = await db.query(
      `SELECT id FROM recall_notifications WHERE recall_id = $1 AND user_id = $2`,
      [recallId, alice.id]
    );
    expect(notifications.rowCount).toBe(1);

    // Running a second time must NOT duplicate the notification.
    sendPush.mockClear();
    const secondRun = await matchAndNotify(recallId);
    expect(secondRun).toBe(0);
    expect(sendPush).not.toHaveBeenCalled();
  });

  it('returns 0 when the recall has no upc_codes', async () => {
    const recallInsert = await db.query(
      `INSERT INTO recalls
         (recall_number, classification, product_description, reason_for_recall,
          recalling_firm, product_type, upc_codes)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id`,
      ['EMPTY-01', 'Class III', 'No-UPC recall', 'reason', 'firm', 'food', []]
    );
    const n = await matchAndNotify(recallInsert.rows[0].id);
    expect(n).toBe(0);
  });
});

// Pure-function unit test — runs without a DB.
describe('fdaRecalls.extractUpcCodes', () => {
  it('extracts 12- and 13-digit runs from free text', () => {
    const text = 'Lot 12345 / UPC 0123456789012 also 9780201379624';
    const codes = extractUpcCodes(text);
    expect(codes).toContain('0123456789012');
    expect(codes).toContain('9780201379624');
    expect(codes).not.toContain('12345');
  });

  it('dedupes repeated codes', () => {
    const codes = extractUpcCodes('0123456789012 and again 0123456789012');
    expect(codes).toEqual(['0123456789012']);
  });

  it('returns [] for empty / undefined input', () => {
    expect(extractUpcCodes(undefined)).toEqual([]);
    expect(extractUpcCodes('')).toEqual([]);
  });
});
