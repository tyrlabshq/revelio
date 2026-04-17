import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  scoreToGrade,
  personalizeScore,
  IngredientFlag,
  UserPriority,
} from '../../shared/scoring';

test('scoreToGrade boundaries match documented thresholds', () => {
  assert.equal(scoreToGrade(100), 'A');
  assert.equal(scoreToGrade(80), 'A');
  assert.equal(scoreToGrade(79), 'B');
  assert.equal(scoreToGrade(65), 'B');
  assert.equal(scoreToGrade(64), 'C');
  assert.equal(scoreToGrade(50), 'C');
  assert.equal(scoreToGrade(49), 'D');
  assert.equal(scoreToGrade(35), 'D');
  assert.equal(scoreToGrade(34), 'F');
  assert.equal(scoreToGrade(0), 'F');
});

function flag(overrides: Partial<IngredientFlag> = {}): IngredientFlag {
  return {
    ingredient: 'canola oil',
    severity: 2,
    category: 'SEED OIL',
    reason: 'high omega-6',
    priorities: ['seed_oils'],
    ...overrides,
  };
}

test('personalizeScore returns baseScore when user has no priorities', () => {
  const score = personalizeScore(80, [flag()], []);
  assert.equal(score, 80);
});

test('personalizeScore penalizes matching priorities', () => {
  const prios: UserPriority[] = ['seed_oils'];
  const score = personalizeScore(80, [flag({ severity: 2, priorities: ['seed_oils'] })], prios);
  // penalty = severity(2) * 5 * overlap(1) = 10
  assert.equal(score, 70);
});

test('personalizeScore ignores non-matching priorities', () => {
  const prios: UserPriority[] = ['vegan'];
  const score = personalizeScore(80, [flag({ priorities: ['seed_oils'] })], prios);
  assert.equal(score, 80);
});

test('personalizeScore floors at 0 and caps at 100', () => {
  const prios: UserPriority[] = ['seed_oils'];
  const many = Array.from({ length: 10 }, () =>
    flag({ severity: 3, priorities: ['seed_oils'] })
  );
  const score = personalizeScore(50, many, prios);
  assert.equal(score, 0);
});

test('personalizeScore handles multi-priority overlap correctly', () => {
  const prios: UserPriority[] = ['paraben_free', 'endocrine_disruptors'];
  const f = flag({
    ingredient: 'butylparaben',
    severity: 3,
    priorities: ['paraben_free', 'endocrine_disruptors'],
  });
  // overlap = 2, severity = 3 → penalty = 3 * 5 * 2 = 30
  const score = personalizeScore(90, [f], prios);
  assert.equal(score, 60);
});
