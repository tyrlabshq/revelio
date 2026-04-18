import pLimit from 'p-limit';
import { db } from '../db';
import type { Nutriments, NutriScore, NovaGroup, EcoScore } from '../../../shared/scoring';
import { getRedis } from '../lib/redis';

export interface ProductData {
  barcode: string;
  name: string;
  brand: string;
  category: 'food' | 'cosmetics' | 'cleaning';
  imageUrl?: string;
  ingredients: string[];
  rawData?: any;
  nutriments?: Nutriments;
  nutriScoreGrade?: NutriScore;
  nutriScorePoints?: number;
  novaGroup?: NovaGroup;
  ecoScoreGrade?: EcoScore;
  ecoScore?: number;
}

export interface LookupOptions {
  // When true, skip memory + Redis + Postgres caches and force a fresh
  // fetch from the upstream APIs. Routes plumb `Cache-Control: no-cache`
  // into this flag. Postgres is still written on success so downstream
  // readers see the refreshed row.
  bypassCache?: boolean;
}

// OFF v2 fields we need. Includes nutri/nova/eco for Track 2 parity.
const FIELDS = [
  'product_name',
  'brands',
  'image_url',
  'ingredients_text',
  'additives_tags',
  'nutriments',
  'categories_tags',
  'nova_group',
  'nutriscore_grade',
  'nutriscore_score',
  'ecoscore_grade',
  'ecoscore_score',
].join(',');

const SOURCES = [
  { name: 'OFF', url: (barcode: string) => `https://world.openfoodfacts.org/api/v2/product/${barcode}.json?fields=${FIELDS}` },
  { name: 'OBF', url: (barcode: string) => `https://world.openbeautyfacts.org/api/v2/product/${barcode}.json?fields=${FIELDS}` },
  { name: 'OPF', url: (barcode: string) => `https://world.openproductsfacts.org/api/v2/product/${barcode}.json?fields=${FIELDS}` },
];

// Rate limiter: max 1 concurrent request to OFF (1 req/sec friendly)
const offLimiter = pLimit(1);

// ─── Cache config ────────────────────────────────────────────────────────────
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const SEVEN_DAYS_SEC = 7 * 24 * 60 * 60;
const MEMORY_TTL_MS = 5 * 60 * 1000; // 5 min hot cache in-process
const MEMORY_MAX_ENTRIES = 500;
const cacheKey = (barcode: string) => `product:v1:${barcode}`;

type MemoryEntry = { value: ProductData; expiresAt: number };
const memoryCache = new Map<string, MemoryEntry>();

function memoryGet(barcode: string): ProductData | null {
  const entry = memoryCache.get(barcode);
  if (!entry) return null;
  if (Date.now() > entry.expiresAt) {
    memoryCache.delete(barcode);
    return null;
  }
  return entry.value;
}

function memorySet(barcode: string, value: ProductData): void {
  if (memoryCache.size >= MEMORY_MAX_ENTRIES) {
    // Evict the oldest insertion — Map preserves insertion order.
    const oldest = memoryCache.keys().next().value;
    if (oldest !== undefined) memoryCache.delete(oldest);
  }
  memoryCache.set(barcode, { value, expiresAt: Date.now() + MEMORY_TTL_MS });
}

async function redisGet(barcode: string): Promise<ProductData | null> {
  const redis = getRedis();
  if (!redis) return null;
  try {
    const raw = await redis.get(cacheKey(barcode));
    if (!raw) return null;
    return JSON.parse(raw) as ProductData;
  } catch (err) {
    console.error('[productLookup] redis get failed:', (err as Error).message);
    return null;
  }
}

async function redisSet(barcode: string, value: ProductData): Promise<void> {
  const redis = getRedis();
  if (!redis) return;
  try {
    await redis.set(cacheKey(barcode), JSON.stringify(value), 'EX', SEVEN_DAYS_SEC);
  } catch (err) {
    console.error('[productLookup] redis set failed:', (err as Error).message);
  }
}

// ─── Parsing helpers ─────────────────────────────────────────────────────────

function detectCategory(categoriesTags: string[]): 'food' | 'cosmetics' | 'cleaning' {
  const tags = categoriesTags.map(t => t.toLowerCase());
  const cosmeticKeywords = ['cosmetic', 'beauty', 'skin-care', 'hair', 'make-up'];
  const cleaningKeywords = ['cleaning', 'household', 'detergent'];
  if (tags.some(t => cosmeticKeywords.some(k => t.includes(k)))) return 'cosmetics';
  if (tags.some(t => cleaningKeywords.some(k => t.includes(k)))) return 'cleaning';
  return 'food';
}

export function parseIngredients(text: string): string[] {
  if (!text) return [];
  const cleaned = text
    .replace(/\([^)]*\)/g, '')       // strip parenthetical sub-ingredients
    .replace(/\d+(\.\d+)?%/g, '')    // strip percentages
    .replace(/<[^>]+>/g, '')          // strip bold/html markup
    .replace(/\*/g, '');              // strip asterisks
  const parts = cleaned.split(/[,;]/);
  const seen = new Set<string>();
  const result: string[] = [];
  for (const part of parts) {
    const normalized = part.toLowerCase().trim().replace(/\.$/, '');
    if (normalized.length < 2) continue;
    if (!seen.has(normalized)) {
      seen.add(normalized);
      result.push(normalized);
    }
  }
  return result;
}

// ─── OFF nutriments parser ────────────────────────────────────────────────────
// OFF returns units inconsistently. Energy comes as either `energy-kj_100g` or
// `energy_100g` (which is kcal in some older entries). We prefer kJ, falling back
// to kcal × 4.184. Sodium is `sodium_100g` in grams — we convert to mg. If only
// `salt_100g` is present we derive sodium = salt / 2.5.
export function parseNutriments(raw: any): Nutriments {
  const n = (raw && raw.nutriments) || {};
  const num = (v: any): number | undefined => {
    const x = typeof v === 'number' ? v : parseFloat(v);
    return Number.isFinite(x) ? x : undefined;
  };

  let energyKj = num(n['energy-kj_100g']) ?? num(n['energy-kj']);
  if (energyKj == null) {
    const kcal = num(n['energy-kcal_100g']) ?? num(n['energy-kcal']);
    if (kcal != null) energyKj = kcal * 4.184;
    else {
      const e = num(n['energy_100g']) ?? num(n['energy']);
      // Heuristic: values > 500 are usually kJ; lower are kcal.
      if (e != null) energyKj = e > 500 ? e : e * 4.184;
    }
  }

  const saturatedFatG = num(n['saturated-fat_100g']) ?? num(n['saturated-fat']);
  const sugarsG = num(n['sugars_100g']) ?? num(n['sugars']);

  // sodium comes in grams per 100g in OFF; convert to mg.
  let sodiumMg: number | undefined;
  const sodiumG = num(n['sodium_100g']) ?? num(n['sodium']);
  if (sodiumG != null) sodiumMg = sodiumG * 1000;
  if (sodiumMg == null) {
    const saltG = num(n['salt_100g']) ?? num(n['salt']);
    if (saltG != null) sodiumMg = (saltG / 2.5) * 1000;
  }

  const fiberG = num(n['fiber_100g']) ?? num(n['fiber']);
  const proteinG = num(n['proteins_100g']) ?? num(n['proteins']);
  const fruitsVegNutsPercent =
    num(n['fruits-vegetables-nuts_100g']) ??
    num(n['fruits-vegetables-nuts-estimate_100g']) ??
    num(n['fruits-vegetables-nuts-estimate-from-ingredients_100g']);

  return { energyKj, saturatedFatG, sugarsG, sodiumMg, fiberG, proteinG, fruitsVegNutsPercent };
}

function normalizeNutriGrade(g: any): NutriScore | undefined {
  if (typeof g !== 'string') return undefined;
  const up = g.trim().toUpperCase();
  return (['A', 'B', 'C', 'D', 'E'] as const).includes(up as any) ? (up as NutriScore) : undefined;
}

function normalizeEcoGrade(g: any): EcoScore | undefined {
  if (typeof g !== 'string') return undefined;
  const up = g.trim().toUpperCase();
  return (['A', 'B', 'C', 'D', 'E'] as const).includes(up as any) ? (up as EcoScore) : undefined;
}

function normalizeNova(g: any): NovaGroup | undefined {
  const n = typeof g === 'number' ? g : parseInt(g, 10);
  if (Number.isFinite(n) && n >= 1 && n <= 4) return n as NovaGroup;
  return undefined;
}

async function fetchFromSource(url: string): Promise<any | null> {
  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': 'Revelio/1.0 (barcode ingredient analyzer)' },
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return null;
    const data = await res.json() as any;
    if (data.status === 1 && data.product) return data.product;
  } catch {
    // Network or timeout error — move to next source
  }
  return null;
}

async function fetchFromAPIs(barcode: string): Promise<{ raw: any; category: 'food' | 'cosmetics' | 'cleaning' } | null> {
  for (let i = 0; i < SOURCES.length; i++) {
    const source = SOURCES[i];
    const url = source.url(barcode);
    // Apply rate limiting only to OFF
    const raw = i === 0
      ? await offLimiter(() => fetchFromSource(url))
      : await fetchFromSource(url);
    if (raw) {
      const category = detectCategory(raw.categories_tags || []);
      return { raw, category };
    }
  }
  return null;
}

function hydrateCached(row: any): ProductData {
  const ingredients = typeof row.ingredients === 'string' ? JSON.parse(row.ingredients) : row.ingredients;
  const raw = row.off_data;
  return {
    barcode: row.barcode,
    name: row.name || 'Unknown',
    brand: row.brand || 'Unknown',
    category: row.category as 'food' | 'cosmetics' | 'cleaning',
    imageUrl: row.image_url,
    ingredients,
    rawData: raw,
    nutriments: raw ? parseNutriments(raw) : undefined,
    nutriScoreGrade: normalizeNutriGrade(row.nutri_score_grade),
    nutriScorePoints: row.nutri_score_points ?? undefined,
    novaGroup: normalizeNova(row.nova_group),
    ecoScoreGrade: normalizeEcoGrade(row.ecoscore_grade),
    ecoScore: row.ecoscore_score ?? undefined,
  };
}

// ─── Lookup ──────────────────────────────────────────────────────────────────

export async function lookupProduct(
  barcode: string,
  options: LookupOptions = {}
): Promise<ProductData | null> {
  const { bypassCache = false } = options;

  if (!bypassCache) {
    // Layer 1: in-process memory
    const mem = memoryGet(barcode);
    if (mem) return mem;

    // Layer 2: Redis
    const hit = await redisGet(barcode);
    if (hit) {
      memorySet(barcode, hit);
      return hit;
    }

    // Layer 3: Postgres 7-day cache (hydrated with Nutri/Nova/Eco columns)
    const cached = await db.query('SELECT * FROM products WHERE barcode = $1', [barcode]);
    if (cached.rows.length > 0) {
      const row = cached.rows[0];
      const ageMs = Date.now() - new Date(row.last_fetched).getTime();
      if (ageMs < SEVEN_DAYS_MS) {
        const product = hydrateCached(row);
        memorySet(barcode, product);
        void redisSet(barcode, product);
        return product;
      }
    }
  }

  // Layer 4: upstream APIs (OFF → OBF → OPF)
  const result = await fetchFromAPIs(barcode);
  if (!result) return null;

  const { raw, category } = result;
  const ingredients = parseIngredients(raw.ingredients_text || '');
  const name = raw.product_name || 'Unknown';
  const brand = raw.brands || 'Unknown';
  const imageUrl = raw.image_url;
  const nutriments = parseNutriments(raw);
  const nutriScoreGrade = normalizeNutriGrade(raw.nutriscore_grade);
  const nutriScorePoints = typeof raw.nutriscore_score === 'number' ? raw.nutriscore_score : null;
  const novaGroup = normalizeNova(raw.nova_group);
  const ecoScoreGrade = normalizeEcoGrade(raw.ecoscore_grade);
  const ecoScoreNumeric = typeof raw.ecoscore_score === 'number' ? raw.ecoscore_score : null;

  // Upsert to DB (always — even on bypassCache, readers stay fresh).
  // Includes Nutri/Nova/Eco columns from migration 007.
  await db.query(
    `INSERT INTO products (
       barcode, name, brand, category, image_url, ingredients, off_data,
       nutri_score_grade, nutri_score_points, nova_group,
       ecoscore_grade, ecoscore_score, last_fetched
     )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW())
     ON CONFLICT (barcode) DO UPDATE SET
       name = $2, brand = $3, category = $4, image_url = $5,
       ingredients = $6, off_data = $7,
       nutri_score_grade = $8, nutri_score_points = $9, nova_group = $10,
       ecoscore_grade = $11, ecoscore_score = $12,
       last_fetched = NOW()`,
    [
      barcode, name, brand, category, imageUrl,
      JSON.stringify(ingredients), JSON.stringify(raw),
      nutriScoreGrade ?? null, nutriScorePoints, novaGroup ?? null,
      ecoScoreGrade ?? null, ecoScoreNumeric,
    ]
  );

  const product: ProductData = {
    barcode, name, brand, category, imageUrl, ingredients, rawData: raw,
    nutriments,
    nutriScoreGrade,
    nutriScorePoints: nutriScorePoints ?? undefined,
    novaGroup,
    ecoScoreGrade,
    ecoScore: ecoScoreNumeric ?? undefined,
  };
  memorySet(barcode, product);
  void redisSet(barcode, product);
  return product;
}
