import { db } from '../db';
import {
  IngredientFlag,
  UserPriority,
  scoreToGrade,
  personalizeScore,
  computeNutriScore,
  classifyNovaGroup,
  normalizeEcoScore,
  kidSafeScore,
  NutriScore,
  NovaGroup,
  EcoScore,
  Nutriments,
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
  nutriScore?: NutriScore;
  novaGroup?: NovaGroup;
  ecoScore?: EcoScore;
  kidSafeGrade?: 'A' | 'B' | 'C' | 'D' | 'F';
  kidSafeReason?: string;
}

export interface ScoreOptions {
  // Nutri/Nova/Eco inputs. When null/undefined the engine tries to compute
  // Nutri from `nutriments`, falls back to nothing.
  nutriments?: Nutriments;
  offNutriScoreGrade?: NutriScore;
  offNovaGroup?: NovaGroup;
  offEcoGrade?: EcoScore | string;
  // Kid-safe mode: when true, a severity ≥2 flag in the kid-safe category set
  // forces the kidSafeGrade to F with a reason string.
  kidSafe?: boolean;
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
  priorities: UserPriority[],
  options: ScoreOptions = {}
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

  // Prefer OFF-provided Nutri-Score when available; otherwise compute.
  let nutriScore: NutriScore | undefined = options.offNutriScoreGrade;
  if (!nutriScore && options.nutriments) {
    const ns = computeNutriScore(options.nutriments);
    if (ns) nutriScore = ns.grade;
  }

  const novaGroup = classifyNovaGroup(options.offNovaGroup, matchedFlags);
  const ecoScore = normalizeEcoScore(options.offEcoGrade ?? undefined);

  const result: ScoreResult = {
    baseScore,
    personalizedScore,
    grade,
    flags: matchedFlags,
    nutriScore,
    novaGroup,
    ecoScore,
  };

  if (options.kidSafe) {
    const ks = kidSafeScore(matchedFlags, personalizedScore, { kidSafe: true });
    result.kidSafeGrade = ks.grade;
    result.kidSafeReason = ks.reason;
  }

  return result;
}

// ─── Convenience: score directly from a cached product row ───────────────────
//
// Most callers have a barcode and a priorities[] array — this wrapper loads the
// cached row (written by productLookup.lookupProduct) and forwards the OFF
// fields (nutriscore_grade, nova_group, ecoscore_grade, nutriments) into the
// main scorer. It is NOT a replacement for scoreProduct — existing callers that
// pass pre-parsed ingredient arrays continue to work unchanged.

export async function scoreBarcode(
  barcode: string,
  priorities: UserPriority[],
  opts: { kidSafe?: boolean } = {}
): Promise<ScoreResult | null> {
  const { rows } = await db.query('SELECT * FROM products WHERE barcode = $1', [barcode]);
  if (rows.length === 0) return null;
  const row = rows[0];
  const ingredients = typeof row.ingredients === 'string' ? JSON.parse(row.ingredients) : (row.ingredients ?? []);
  const raw = row.off_data || {};
  const { parseNutriments } = await import('./productLookup');
  const nutriments = parseNutriments(raw);
  const offNutri = (typeof row.nutri_score_grade === 'string' ? row.nutri_score_grade.toUpperCase() : null);
  const offNutriScoreGrade = offNutri && ['A','B','C','D','E'].includes(offNutri) ? (offNutri as NutriScore) : undefined;
  const offNova = typeof row.nova_group === 'number' ? row.nova_group : parseInt(row.nova_group, 10);
  const offNovaGroup = Number.isFinite(offNova) && offNova >= 1 && offNova <= 4 ? (offNova as NovaGroup) : undefined;
  const offEcoGrade = typeof row.ecoscore_grade === 'string' ? row.ecoscore_grade : undefined;

  return scoreProduct(ingredients, row.category || 'food', priorities, {
    nutriments,
    offNutriScoreGrade,
    offNovaGroup,
    offEcoGrade,
    kidSafe: opts.kidSafe,
  });
}

// ─── Cache invalidation (exported for tests / admin routes) ──────────────────

export function invalidateFlagCache(): void {
  cache = null;
}
