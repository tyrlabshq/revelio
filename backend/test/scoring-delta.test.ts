/**
 * Personalization delta regression: a single IngredientFlag must produce
 *   1. A neutral base score when there are no priorities
 *   2. A lower score when the user prioritizes the matching category
 *   3. An F grade when kid-safe mode is on, regardless of score
 *
 * This exercises `scoreProduct` end-to-end against a mocked DB so we can
 * inject a controlled ingredient-flag row. No real Postgres is required.
 */

import { describe, it, beforeEach, expect, vi } from 'vitest';

const { dbQuery } = vi.hoisted(() => ({ dbQuery: vi.fn() }));
vi.mock('../src/db', () => ({
  db: { query: dbQuery },
  ensureAlternativesTable: vi.fn().mockResolvedValue(undefined),
}));

import { scoreProduct, invalidateFlagCache } from '../src/services/scorer';

beforeEach(() => {
  dbQuery.mockReset();
  invalidateFlagCache();
  // Every test gets the same synthetic flag table: one severity-2 artificial
  // additive that matches the ingredient name "red 40".
  dbQuery.mockResolvedValue({
    rows: [
      {
        ingredient_name: 'red 40',
        severity: 2,
        category: 'artificial_additives',
        reason: 'Linked to hyperactivity in children',
        citation_title: null,
        citation_url: null,
        citation_year: null,
        priorities: ['artificial_additives'],
      },
    ],
    rowCount: 1,
  });
});

describe('scoring personalization delta', () => {
  it('no priorities → baseline score X', async () => {
    const result = await scoreProduct(['red 40'], 'food', []);
    expect(result.flags).toHaveLength(1);
    // baseScore: 100 - 15 (severity-2 penalty) = 85; no personalization.
    expect(result.baseScore).toBe(85);
    expect(result.personalizedScore).toBe(85);
    expect(result.grade).toBe('A');
  });

  it('artificial_additives priority → score drops below baseline', async () => {
    const baseline = await scoreProduct(['red 40'], 'food', []);
    const prioritized = await scoreProduct(['red 40'], 'food', ['artificial_additives']);
    expect(prioritized.personalizedScore).toBeLessThan(baseline.personalizedScore);
  });

  it('kid-safe mode → grade F regardless of score', async () => {
    const result = await scoreProduct(['red 40'], 'food', [], { kidSafe: true });
    // Score is still computed — only the kidSafeGrade forces F.
    expect(result.kidSafeGrade).toBe('F');
    expect(result.kidSafeReason).toContain('red 40');
  });

  it('ingredient with no flag match is unchanged', async () => {
    const result = await scoreProduct(['water'], 'food', ['artificial_additives']);
    expect(result.flags).toHaveLength(0);
    expect(result.baseScore).toBe(100);
    expect(result.personalizedScore).toBe(100);
  });
});
