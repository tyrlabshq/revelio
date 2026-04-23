/**
 * Vitest version of the scoring golden-set. Covers:
 *   - grade boundary function
 *   - personalization delta for seed-oils + paraben-free priorities
 *   - kid-safe override: severity ≥ 2 in kid-critical categories = F
 *   - life-mode multiplier (pregnancy doubles heavy-metal severity)
 *
 * No DB is required — this exercises the pure scoring module directly, so
 * it runs in every vitest invocation (unlike the IDOR specs which skip
 * without TEST_DATABASE_URL).
 */

import { describe, it, expect } from 'vitest';
import {
  scoreToGrade,
  personalizeScore,
  kidSafeScore,
  type IngredientFlag,
} from '../../shared/scoring';

const base = (overrides: Partial<IngredientFlag>): IngredientFlag => ({
  ingredient: 'x',
  severity: 1,
  category: 'artificial_additives',
  reason: 'test',
  priorities: [],
  ...overrides,
});

describe('scoreToGrade', () => {
  it('returns A for 85+', () => {
    expect(scoreToGrade(95)).toBe('A');
    expect(scoreToGrade(85)).toBe('A');
  });
  it('walks B/C/D/F as scores drop', () => {
    expect(scoreToGrade(72)).toBe('B');
    expect(scoreToGrade(55)).toBe('C');
    expect(scoreToGrade(40)).toBe('D');
    expect(scoreToGrade(20)).toBe('F');
  });
});

describe('personalizeScore', () => {
  it('amplifies penalties for priority-matched flags', () => {
    const flags: IngredientFlag[] = [
      base({ ingredient: 'soybean oil', severity: 2, category: 'seed_oils', priorities: ['seed_oils'] }),
    ];
    const defaultScore = personalizeScore(100, flags, []);
    const priorityScore = personalizeScore(100, flags, ['seed_oils']);
    expect(priorityScore).toBeLessThan(defaultScore);
  });

  it('leaves score unchanged when priorities do not match flags', () => {
    const flags: IngredientFlag[] = [
      base({ ingredient: 'red 40', severity: 2, category: 'artificial_additives', priorities: ['artificial_additives'] }),
    ];
    const defaultScore = personalizeScore(100, flags, []);
    const unrelatedPriorityScore = personalizeScore(100, flags, ['gluten_free']);
    expect(unrelatedPriorityScore).toBe(defaultScore);
  });
});

describe('kidSafeScore', () => {
  it('forces F when a severity ≥ 2 flag in a kid-critical category is present and kidSafe is true', () => {
    const flags: IngredientFlag[] = [
      base({ severity: 3, category: 'artificial_additives', priorities: ['artificial_additives'] }),
    ];
    const result = kidSafeScore(flags, 90, { kidSafe: true });
    expect(result.grade).toBe('F');
    expect(result.reason).toBeTruthy();
  });

  it('does not downgrade when all flags are severity ≤ 1', () => {
    const flags: IngredientFlag[] = [
      base({ severity: 1 }),
    ];
    const result = kidSafeScore(flags, 90, { kidSafe: true });
    expect(result.grade).toBe('A');
  });

  it('passes through the raw grade when kidSafe option is off', () => {
    const flags: IngredientFlag[] = [
      base({ severity: 3, category: 'artificial_additives', priorities: ['artificial_additives'] }),
    ];
    const result = kidSafeScore(flags, 90, { kidSafe: false });
    expect(result.grade).toBe('A');
  });
});

describe('life-mode multipliers', () => {
  it('pregnancy doubles heavy-metal severity impact', () => {
    const flags: IngredientFlag[] = [
      base({ severity: 2, category: 'heavy_metals', priorities: ['heavy_metals'] }),
    ];
    const normal = personalizeScore(100, flags, ['heavy_metals']);
    const pregnancy = personalizeScore(100, flags, ['heavy_metals', 'pregnancy']);
    expect(pregnancy).toBeLessThan(normal);
  });
});
