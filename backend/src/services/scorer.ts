import { db } from '../db';
import {
  IngredientFlag,
  UserPriority,
  scoreToGrade,
  personalizeScore,
} from '../../../shared/scoring';

// ─── In-memory cache ────────────────────────────────────────────────────────

interface FlagCache {
  flags: IngredientFlag[];
  loadedAt: Date;
}

const CACHE_TTL_MS = 60 * 60 * 1000; // 60 minutes
let cache: FlagCache | null = null;

// ─── DB → IngredientFlag mapper ───────────────────────────────────────────────

function rowToFlag(row: Record<string, any>): IngredientFlag {
  return {
    ingredient: row.ingredient_name,
    severity: row.severity as 0 | 1 | 2 | 3,
    category: row.category,
    reason: row.reason,
    citation:
      row.citation_title
        ? {
            title: row.citation_title,
            url: row.citation_url ?? '',
            year: row.citation_year ?? 0,
          }
        : undefined,
    priorities: (row.priorities ?? []) as UserPriority[],
  };
}

// ─── Cache loader ─────────────────────────────────────────────────────────────

export async function getIngredientFlags(): Promise<IngredientFlag[]> {
  const now = new Date();

  if (cache && now.getTime() - cache.loadedAt.getTime() < CACHE_TTL_MS) {
    return cache.flags;
  }

  const result = await db.query(
    'SELECT * FROM ingredient_flags ORDER BY severity DESC'
  );
  const flags = result.rows.map(rowToFlag);

  cache = { flags, loadedAt: now };
  return flags;
}

// ─── Fuzzy matcher ─────────────────────────────────────────────────────────────

export function matchIngredient(
  parsedIngredient: string,
  flagIngredient: string
): boolean {
  const a = parsedIngredient.toLowerCase().trim();
  const b = flagIngredient.toLowerCase().trim();
  return a.includes(b) || b.includes(a);
}

// ─── Score result type ────────────────────────────────────────────────────────

export interface ScoreResult {
  baseScore: number;
  personalizedScore: number;
  grade: 'A' | 'B' | 'C' | 'D' | 'F';
  flags: IngredientFlag[];
}

// ─── Penalty map ──────────────────────────────────────────────────────────────

const SEVERITY_PENALTY: Record<number, number> = {
  0: 0,
  1: 5,
  2: 15,
  3: 25,
};

// ─── Main scorer ──────────────────────────────────────────────────────────────

export async function scoreProduct(
  ingredients: string[],
  category: string,
  priorities: UserPriority[]
): Promise<ScoreResult> {
  const allFlags = await getIngredientFlags();

  // Find which flags match any ingredient
  const matchedFlags: IngredientFlag[] = [];
  for (const flag of allFlags) {
    const hit = ingredients.some(ing =>
      matchIngredient(ing, flag.ingredient)
    );
    if (hit) {
      matchedFlags.push(flag);
    }
  }

  // Base score: 100 minus accumulated severity penalties, floor 20
  let penalty = 0;
  for (const flag of matchedFlags) {
    penalty += SEVERITY_PENALTY[flag.severity] ?? 0;
  }
  const baseScore = Math.max(20, Math.min(100, 100 - penalty));

  // Personalized score
  const personalizedScore = personalizeScore(baseScore, matchedFlags, priorities);

  // Grade
  const grade = scoreToGrade(personalizedScore);

  return { baseScore, personalizedScore, grade, flags: matchedFlags };
}

// ─── Cache invalidation (exported for tests / admin routes) ──────────────────

export function invalidateFlagCache(): void {
  cache = null;
}
