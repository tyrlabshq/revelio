// Revelio Scoring Engine — Shared Logic
// Scoring is personalized. Each ingredient has a base severity (0-10),
// but the final score re-weights based on user profile priorities.

export type Category = 'food' | 'cosmetics' | 'cleaning' | 'supplements';

export type UserPriority =
  | 'seed_oils'
  | 'artificial_additives'
  | 'heavy_metals'
  | 'endocrine_disruptors'
  | 'gluten_free'
  | 'keto'
  | 'vegan'
  | 'fragrance_free'
  | 'paraben_free'
  | 'sulfate_free'
  // ─── Life-mode pseudo-priorities (REV-17) ──────────────────────────────────
  // Kid-safe already lives behind its own options flag; the four below gate
  // extra severity math in `personalizeScore` + optional grade overrides.
  // They're part of UserPriority because the scorer's existing plumbing
  // (profile.priorities[]) is the natural carrier — a profile can only ever
  // be in one life mode at a time, enforced at write time in routes/profiles.
  | 'pregnancy'
  | 'teen'
  | 'senior'
  | 'menstrual_cycle';

// Life-mode values that are mutually exclusive per profile/family member.
// null / undefined / absent = no life mode.
export type LifeMode = 'pregnancy' | 'teen' | 'senior' | 'menstrual_cycle';

export const LIFE_MODE_VALUES: readonly LifeMode[] = [
  'pregnancy',
  'teen',
  'senior',
  'menstrual_cycle',
] as const;

export interface IngredientFlag {
  ingredient: string;
  severity: 0 | 1 | 2 | 3; // 0=fine, 1=watch, 2=concerning, 3=avoid
  category: string; // "seed oil" | "artificial dye" | "preservative" | etc.
  reason: string; // short human-readable reason
  citation?: {
    title: string;
    url: string;
    year: number;
  };
  priorities: UserPriority[]; // which user priorities this triggers
}

// ─── Nutri-Score / Nova / Eco-Score types ────────────────────────────────────

export type NutriScore = 'A' | 'B' | 'C' | 'D' | 'E';
export type NovaGroup = 1 | 2 | 3 | 4;
export type EcoScore = 'A' | 'B' | 'C' | 'D' | 'E';

export interface Nutriments {
  // Per 100g / 100ml. All optional — the OFF API is inconsistent.
  energyKj?: number;
  saturatedFatG?: number;
  sugarsG?: number;
  sodiumMg?: number;
  fiberG?: number;
  proteinG?: number;
  fruitsVegNutsPercent?: number;
}

export interface NutriScoreResult {
  grade: NutriScore;
  points: number; // final Nutri-Score points (negative - positive)
  negativePoints: number;
  positivePoints: number;
}

export interface ScanResult {
  barcode: string;
  productName: string;
  brand: string;
  category: Category;
  imageUrl?: string;
  ingredients: string[];
  flags: IngredientFlag[];
  baseScore: number; // 0-100, higher = cleaner
  personalizedScore: number; // re-weighted for user priorities
  grade: 'A' | 'B' | 'C' | 'D' | 'F';
  alternatives?: AlternativeProduct[];
  nutriScore?: NutriScore;
  novaGroup?: NovaGroup;
  ecoScore?: EcoScore;
  kidSafeGrade?: 'A' | 'B' | 'C' | 'D' | 'F';
}

export interface AlternativeProduct {
  name: string;
  brand: string;
  score: number;
  imageUrl?: string;
  purchaseUrl: string; // affiliate link
  affiliateNetwork: 'amazon' | 'thrive_market' | 'iherb';
  priceCents?: number;
}

export interface UserProfile {
  id: string;
  name: string;
  isChild: boolean;
  priorities: UserPriority[];
  allergies: string[];
  dietaryRestrictions: string[];
}

// Grade thresholds
export const scoreToGrade = (score: number): ScanResult['grade'] => {
  if (score >= 80) return 'A';
  if (score >= 65) return 'B';
  if (score >= 50) return 'C';
  if (score >= 35) return 'D';
  return 'F';
};

// ─── Life-mode helpers (REV-17) ──────────────────────────────────────────────
//
// Each life mode defines (a) a set of concern categories whose matched flags
// get their severity multiplied and (b) optional overrides used to force a
// bad grade when a high-severity flag is present in one of those categories.
// We keep the modes data-driven so the iOS client and the backend agree.

const LIFE_MODE_FLAG_MULTIPLIER: Record<LifeMode, { categories: UserPriority[]; multiplier: number }> = {
  pregnancy: {
    // Pregnancy: double-weight heavy metals / endocrine disruptors /
    // artificial additives / fragrance (absorbed via skin + inhalation).
    categories: ['heavy_metals', 'endocrine_disruptors', 'artificial_additives', 'fragrance_free'],
    multiplier: 2,
  },
  teen: {
    // Teens: similar to kid-safe, slightly relaxed. Severity 3 flags in the
    // kid-safe categories downgrade to F; severity 2 drops by one grade.
    categories: ['heavy_metals', 'endocrine_disruptors', 'artificial_additives'],
    multiplier: 1.5,
  },
  senior: {
    // Seniors: sodium + sugar are handled via nutriments (see
    // applyLifeModeNutriPenalty). No additional flag multiplier.
    categories: [],
    multiplier: 1,
  },
  menstrual_cycle: {
    // Endocrine-disruptor sensitivity (parabens, phthalates, BPA).
    categories: ['endocrine_disruptors', 'paraben_free'],
    multiplier: 2,
  },
};

/**
 * Pull the first life-mode value present in `priorities`. A profile is only
 * ever in one mode at a time (enforced at PATCH time), so taking the first
 * match is safe.
 */
export function resolveLifeMode(priorities: UserPriority[]): LifeMode | null {
  for (const p of priorities) {
    if ((LIFE_MODE_VALUES as readonly string[]).includes(p)) {
      return p as LifeMode;
    }
  }
  return null;
}

// Personalized scoring: amplify flags that match user priorities
export const personalizeScore = (
  baseScore: number,
  flags: IngredientFlag[],
  priorities: UserPriority[]
): number => {
  if (priorities.length === 0) return baseScore;
  const lifeMode = resolveLifeMode(priorities);
  const lifeModeCfg = lifeMode ? LIFE_MODE_FLAG_MULTIPLIER[lifeMode] : null;

  let penalty = 0;
  for (const flag of flags) {
    const overlap = flag.priorities.filter(p => priorities.includes(p)).length;
    if (overlap > 0) {
      penalty += flag.severity * 5 * overlap;
    }
    // Life-mode multiplier applies on top of the base overlap math. This
    // intentionally stacks — e.g. a paraben flag on a menstrual_cycle
    // profile that also has `paraben_free` selected gets both bumps.
    if (lifeModeCfg && lifeModeCfg.categories.length > 0) {
      const hits = flag.priorities.filter(p => lifeModeCfg.categories.includes(p)).length;
      if (hits > 0) {
        penalty += flag.severity * 5 * hits * (lifeModeCfg.multiplier - 1);
      }
    }
  }
  return Math.max(0, Math.min(100, baseScore - penalty));
};

// ─── Life-mode nutrition-based penalty (senior) ──────────────────────────────
//
// Applied on top of personalizeScore when the profile is in `senior` mode and
// we have nutriments. >20% DV sodium (DV = 2300mg) → 10pt penalty; combined
// with >10g sugar → another 10pt. Returns the adjusted score.

export function applyLifeModeNutriPenalty(
  score: number,
  lifeMode: LifeMode | null,
  n?: Nutriments
): number {
  if (lifeMode !== 'senior' || !n) return score;
  let penalty = 0;
  // FDA DV for sodium is 2300mg. 20% DV on the Nutrition Facts panel is
  // generally considered "high" — we apply an additive 10pt hit per 100g/ml.
  if (typeof n.sodiumMg === 'number' && n.sodiumMg > 460) {
    penalty += 10;
  }
  if (typeof n.sugarsG === 'number' && n.sugarsG > 10) {
    penalty += 10;
  }
  return Math.max(0, Math.min(100, score - penalty));
}

// ─── Life-mode grade override (pregnancy / teen) ─────────────────────────────
//
// Some modes can force a bad grade regardless of score — e.g. pregnancy with a
// severity ≥2 flag in a pregnancy-concern category. Returns { grade, reason }
// when an override fires; otherwise undefined.

export interface LifeModeOverride {
  grade: 'A' | 'B' | 'C' | 'D' | 'F';
  reason: string;
  triggeringFlag?: IngredientFlag;
}

const PREGNANCY_CONCERN_CATEGORIES: UserPriority[] = [
  'heavy_metals',
  'endocrine_disruptors',
  'artificial_additives',
  'fragrance_free',
];

const TEEN_CONCERN_CATEGORIES: UserPriority[] = [
  'heavy_metals',
  'endocrine_disruptors',
  'artificial_additives',
];

export function lifeModeGradeOverride(
  lifeMode: LifeMode | null,
  flags: IngredientFlag[],
  currentGrade: 'A' | 'B' | 'C' | 'D' | 'F'
): LifeModeOverride | undefined {
  if (!lifeMode) return undefined;

  if (lifeMode === 'pregnancy') {
    const trigger = flags.find(f =>
      f.severity >= 2 &&
      f.priorities.some(p => PREGNANCY_CONCERN_CATEGORIES.includes(p))
    );
    if (trigger) {
      return {
        grade: 'F',
        triggeringFlag: trigger,
        reason: `Pregnancy mode: ${trigger.ingredient} — ${trigger.reason}`,
      };
    }
  }

  if (lifeMode === 'teen') {
    const severe = flags.find(f =>
      f.severity >= 3 &&
      f.priorities.some(p => TEEN_CONCERN_CATEGORIES.includes(p))
    );
    if (severe) {
      return {
        grade: 'F',
        triggeringFlag: severe,
        reason: `Teen mode: ${severe.ingredient} — ${severe.reason}`,
      };
    }
    const moderate = flags.find(f =>
      f.severity >= 2 &&
      f.priorities.some(p => TEEN_CONCERN_CATEGORIES.includes(p))
    );
    if (moderate) {
      const order: Array<'A' | 'B' | 'C' | 'D' | 'F'> = ['A', 'B', 'C', 'D', 'F'];
      const idx = order.indexOf(currentGrade);
      const dropped = order[Math.min(order.length - 1, idx + 1)];
      return {
        grade: dropped,
        triggeringFlag: moderate,
        reason: `Teen mode: flagged ${moderate.category} in ${moderate.ingredient}`,
      };
    }
  }

  return undefined;
}

// ─── Nutri-Score v2 (2023 official algorithm) ────────────────────────────────
//
// Implementation notes / approximations (documented inline per the 2023 update):
//
// NEGATIVE POINTS (lower = cleaner):
//   energy  — per 100g/ml kJ: step = 335 kJ → 0 points at ≤335, +1 per additional
//             335 kJ up to a cap of 10. (Solid-food table from official doc.)
//   satfat  — g per 100g: step 1g → +1 per +1g up to 10.
//   sugars  — g per 100g: 2023 update uses a steeper, non-uniform curve.
//             Approximation: 0pts ≤4.5g, thresholds at
//             {9, 13.5, 18, 22.5, 27, 31, 36, 41, 46, 51} g → capped at 15 pts.
//             This approximation is within ±1 pt of the official table for most
//             products; precise boundaries are documented at
//             https://world.openfoodfacts.org/nutriscore
//   sodium  — mg per 100g: step 90 mg → +1 per +90 mg up to 10.
//             (Official range 0–20 pts; we clamp at 10 which matches v1 and
//             matches OFF's implementation for solid products.)
//
// POSITIVE POINTS (higher = cleaner):
//   fiber   — g per 100g: step 0.9g → +1 per +0.9g up to 5.
//   protein — g per 100g: step 1.6g → +1 per +1.6g up to 5.
//   fvn %   — fruits/vegetables/nuts/legumes %: +1 per +20% up to 5.
//
// FINAL: points = negative - positive.
// General (solid) food thresholds (from OFF):
//   A ≤ -1, B ≤ 2, C ≤ 10, D ≤ 18, else E.
// Beverage thresholds differ; we use the general one here and flag beverages
// separately in the caller. Link for reference:
//   https://world.openfoodfacts.org/files/nutriscore-2023-algorithm.pdf

function pointsStep(value: number, step: number, cap: number): number {
  if (!Number.isFinite(value) || value <= 0) return 0;
  const pts = Math.floor(value / step);
  return Math.max(0, Math.min(cap, pts));
}

function sugarsPoints(sugarsG: number): number {
  // 2023 algorithm: steeper scale. Thresholds below are grams per 100g.
  // See inline notes above for the approximation rationale.
  if (!Number.isFinite(sugarsG) || sugarsG <= 4.5) return 0;
  const thresholds = [4.5, 9, 13.5, 18, 22.5, 27, 31, 36, 41, 46, 51, 56, 61, 66, 71];
  let pts = 0;
  for (const t of thresholds) {
    if (sugarsG > t) pts++;
    else break;
  }
  return Math.min(15, pts);
}

export function computeNutriScore(n: Nutriments): NutriScoreResult | null {
  // Require at least energy + satfat + sugars + sodium to compute. Fiber /
  // protein / fvn default to 0 positive points when missing.
  if (
    n.energyKj == null ||
    n.saturatedFatG == null ||
    n.sugarsG == null ||
    n.sodiumMg == null
  ) {
    return null;
  }

  const energyPts = pointsStep(n.energyKj - 335, 335, 10) + (n.energyKj > 335 ? 1 : 0);
  // The +1 at boundary above matches: 0pts ≤335, +1 per 335 up to 10.
  // Simpler form: floor(energy/335) capped at 10 (but 335 itself → 1 pt).
  const energyPtsSimple = Math.max(0, Math.min(10, Math.floor(n.energyKj / 335)));

  const satFatPts = pointsStep(n.saturatedFatG - 1, 1, 10) + (n.saturatedFatG > 1 ? 1 : 0);
  const satFatPtsSimple = Math.max(0, Math.min(10, Math.floor(n.saturatedFatG / 1)));

  const sugarsPts = sugarsPoints(n.sugarsG);

  const sodiumPts = Math.max(0, Math.min(10, Math.floor(n.sodiumMg / 90)));

  // Use the simpler ceil-based forms for stability (they match the commonly
  // implemented OFF version for solid foods).
  const neg = energyPtsSimple + satFatPtsSimple + sugarsPts + sodiumPts;

  const fiberPts = n.fiberG != null
    ? Math.max(0, Math.min(5, Math.floor(n.fiberG / 0.9)))
    : 0;
  const proteinPts = n.proteinG != null
    ? Math.max(0, Math.min(5, Math.floor(n.proteinG / 1.6)))
    : 0;
  const fvnPts = n.fruitsVegNutsPercent != null
    ? Math.max(0, Math.min(5, Math.floor(n.fruitsVegNutsPercent / 20)))
    : 0;

  // OFF rule: if negative points >= 11, don't count protein unless fvn is 5.
  const proteinCountable = neg < 11 || fvnPts === 5 ? proteinPts : 0;
  const pos = fiberPts + proteinCountable + fvnPts;

  const points = neg - pos;
  // Silence unused-var warnings for the alternate energy/satfat computations;
  // they're kept inline as reference for reviewers comparing to the OFF code.
  void energyPts;
  void satFatPts;

  let grade: NutriScore;
  if (points <= -1) grade = 'A';
  else if (points <= 2) grade = 'B';
  else if (points <= 10) grade = 'C';
  else if (points <= 18) grade = 'D';
  else grade = 'E';

  return { grade, points, negativePoints: neg, positivePoints: pos };
}

// ─── Nova Group classification ───────────────────────────────────────────────
//
// Prefers the OFF-provided nova_group. Fallback heuristic counts flagged
// additives (category tag starts with "additive" — check is
// case-insensitive).
//   0 additives  → 1 (unprocessed / minimally processed)
//   1–2          → 2 (processed culinary)
//   3–5          → 3 (processed)
//   6+           → 4 (ultra-processed)

export function classifyNovaGroup(
  offNovaGroup: number | null | undefined,
  flags: IngredientFlag[]
): NovaGroup | undefined {
  if (offNovaGroup != null && offNovaGroup >= 1 && offNovaGroup <= 4) {
    return offNovaGroup as NovaGroup;
  }
  const additiveCount = flags.filter(f =>
    f.category?.toLowerCase?.().includes('additive') ||
    f.category?.toLowerCase?.().includes('preservative') ||
    f.category?.toLowerCase?.().includes('sweetener') ||
    f.category?.toLowerCase?.().includes('dye') ||
    f.category?.toLowerCase?.().includes('emulsifier') ||
    f.category?.toLowerCase?.().includes('thickener') ||
    f.category?.toLowerCase?.().includes('flavor enhancer')
  ).length;
  if (additiveCount === 0) return 1;
  if (additiveCount <= 2) return 2;
  if (additiveCount <= 5) return 3;
  return 4;
}

// ─── Eco-Score (pass-through from OFF) ───────────────────────────────────────

export function normalizeEcoScore(offEcoGrade: string | null | undefined): EcoScore | undefined {
  if (!offEcoGrade) return undefined;
  const g = offEcoGrade.toUpperCase();
  if (g === 'A' || g === 'B' || g === 'C' || g === 'D' || g === 'E') return g as EcoScore;
  return undefined;
}

// ─── Kid-safe scoring ────────────────────────────────────────────────────────
//
// When the caller opts into kid-safe mode, any matched flag whose severity
// is ≥2 AND whose category tag intersects one of
//   { artificial_additives, heavy_metals, endocrine_disruptors }
// downgrades the whole product to F. The priorities[] array on each flag
// is how we tag which concern categories it belongs to.

const KID_SAFE_CATEGORIES: UserPriority[] = [
  'artificial_additives',
  'heavy_metals',
  'endocrine_disruptors',
];

export interface KidSafeOptions {
  kidSafe: boolean;
}

export interface KidSafeResult {
  grade: 'A' | 'B' | 'C' | 'D' | 'F';
  reason?: string; // prominent reason string when downgraded
  triggeringFlag?: IngredientFlag;
}

export function kidSafeScore(
  flags: IngredientFlag[],
  personalizedScore: number,
  options: KidSafeOptions = { kidSafe: false }
): KidSafeResult {
  if (!options.kidSafe) {
    return { grade: scoreToGrade(personalizedScore) };
  }
  const trigger = flags.find(f =>
    f.severity >= 2 &&
    f.priorities.some(p => KID_SAFE_CATEGORIES.includes(p))
  );
  if (trigger) {
    return {
      grade: 'F',
      triggeringFlag: trigger,
      reason: `Contains ${trigger.ingredient} — ${trigger.reason}`,
    };
  }
  return { grade: scoreToGrade(personalizedScore) };
}
