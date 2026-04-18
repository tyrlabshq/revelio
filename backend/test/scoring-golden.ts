// Scoring golden-set regression fixture.
//
// This is a minimal, DB-free smoke test that locks in the grade boundaries
// and the personalization math in `shared/scoring.ts`. Expand this file with
// real product fixtures (Nutella -> E, San Pellegrino -> A, etc.) as the
// scoring algorithm matures. The CI workflow `scoring-regression.yml` runs
// this on every PR that touches `shared/scoring.ts` or
// `backend/src/services/scorer.ts`.

import {
  scoreToGrade,
  personalizeScore,
  type IngredientFlag,
  type UserPriority,
} from '../../shared/scoring';

type Case = {
  name: string;
  actual: unknown;
  expected: unknown;
};

const cases: Case[] = [];

// ─── Grade boundary cases ────────────────────────────────────────────────────
cases.push({ name: 'score 85 -> A', actual: scoreToGrade(85), expected: 'A' });
cases.push({ name: 'score 70 -> B', actual: scoreToGrade(70), expected: 'B' });
cases.push({ name: 'score 55 -> C', actual: scoreToGrade(55), expected: 'C' });
cases.push({ name: 'score 40 -> D', actual: scoreToGrade(40), expected: 'D' });
cases.push({ name: 'score 10 -> F', actual: scoreToGrade(10), expected: 'F' });

// ─── Nutella-shaped fixture: palm oil + sugar flagged at severity 3 ──────────
// When user has no priorities, the base score passes through.
// When user flags `seed_oils`, the penalty amplifies and the grade drops.
const nutellaFlags: IngredientFlag[] = [
  {
    ingredient: 'palm oil',
    severity: 3,
    category: 'seed oil',
    reason: 'linked to saturated fat load',
    priorities: ['seed_oils'],
  },
  {
    ingredient: 'sugar',
    severity: 2,
    category: 'added sugar',
    reason: 'high glycemic load',
    priorities: [],
  },
];

// Simulate: backend/src/services/scorer.ts computes baseScore = 100 - (25 + 15) = 60.
const nutellaBase = 60;
const noPriorities: UserPriority[] = [];
const seedOilPriority: UserPriority[] = ['seed_oils'];

cases.push({
  name: 'Nutella no-priorities keeps base score',
  actual: personalizeScore(nutellaBase, nutellaFlags, noPriorities),
  expected: 60,
});

// personalizeScore penalty: flag.severity (3) * 5 * overlap (1) = 15. 60 - 15 = 45.
cases.push({
  name: 'Nutella + seed_oils priority drops to D range',
  actual: personalizeScore(nutellaBase, nutellaFlags, seedOilPriority),
  expected: 45,
});

cases.push({
  name: 'Nutella personalized grade is D for seed-oil avoider',
  actual: scoreToGrade(personalizeScore(nutellaBase, nutellaFlags, seedOilPriority)),
  expected: 'D',
});

// ─── Runner ──────────────────────────────────────────────────────────────────

let failed = 0;
for (const c of cases) {
  const ok = c.actual === c.expected;
  const mark = ok ? 'PASS' : 'FAIL';
  const tail = ok ? '' : ` (got ${JSON.stringify(c.actual)}, want ${JSON.stringify(c.expected)})`;
  console.log(`[${mark}] ${c.name}${tail}`);
  if (!ok) failed++;
}

if (failed > 0) {
  console.error(`\n${failed} scoring regression(s) failed.`);
  process.exit(1);
}
console.log(`\n${cases.length} scoring regression checks passed.`);
