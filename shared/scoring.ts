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
  | 'sulfate_free';

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

// Personalized scoring: amplify flags that match user priorities
export const personalizeScore = (
  baseScore: number,
  flags: IngredientFlag[],
  priorities: UserPriority[]
): number => {
  if (priorities.length === 0) return baseScore;
  let penalty = 0;
  for (const flag of flags) {
    const overlap = flag.priorities.filter(p => priorities.includes(p)).length;
    if (overlap > 0) {
      penalty += flag.severity * 5 * overlap;
    }
  }
  return Math.max(0, Math.min(100, baseScore - penalty));
};
