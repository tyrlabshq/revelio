import pLimit from 'p-limit';
import { db } from '../db';

export interface ProductData {
  barcode: string;
  name: string;
  brand: string;
  category: 'food' | 'cosmetics' | 'cleaning';
  imageUrl?: string;
  ingredients: string[];
  rawData?: any;
}

const FIELDS = 'product_name,brands,image_url,ingredients_text,additives_tags,nutriments,categories_tags';

const SOURCES = [
  { name: 'OFF', url: (barcode: string) => `https://world.openfoodfacts.org/api/v2/product/${barcode}.json?fields=${FIELDS}` },
  { name: 'OBF', url: (barcode: string) => `https://world.openbeautyfacts.org/api/v2/product/${barcode}.json?fields=${FIELDS}` },
  { name: 'OPF', url: (barcode: string) => `https://world.openproductsfacts.org/api/v2/product/${barcode}.json?fields=${FIELDS}` },
];

// Rate limiter: max 1 concurrent request to OFF (1 req/sec friendly)
const offLimiter = pLimit(1);

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

export async function lookupProduct(barcode: string): Promise<ProductData | null> {
  // Check DB cache first
  const cached = await db.query('SELECT * FROM products WHERE barcode = $1', [barcode]);
  if (cached.rows.length > 0) {
    const row = cached.rows[0];
    const ageMs = Date.now() - new Date(row.last_fetched).getTime();
    const sevenDays = 7 * 24 * 60 * 60 * 1000;
    if (ageMs < sevenDays) {
      const ingredients = typeof row.ingredients === 'string' ? JSON.parse(row.ingredients) : row.ingredients;
      return {
        barcode: row.barcode,
        name: row.name || 'Unknown',
        brand: row.brand || 'Unknown',
        category: row.category as 'food' | 'cosmetics' | 'cleaning',
        imageUrl: row.image_url,
        ingredients,
        rawData: row.off_data,
      };
    }
  }

  // Fetch from APIs (fallback chain: OFF → OBF → OPF)
  const result = await fetchFromAPIs(barcode);
  if (!result) return null;

  const { raw, category } = result;
  const ingredients = parseIngredients(raw.ingredients_text || '');
  const name = raw.product_name || 'Unknown';
  const brand = raw.brands || 'Unknown';
  const imageUrl = raw.image_url;

  // Upsert to DB
  await db.query(
    `INSERT INTO products (barcode, name, brand, category, image_url, ingredients, off_data, last_fetched)
     VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
     ON CONFLICT (barcode) DO UPDATE SET
       name = $2, brand = $3, category = $4, image_url = $5,
       ingredients = $6, off_data = $7, last_fetched = NOW()`,
    [barcode, name, brand, category, imageUrl, JSON.stringify(ingredients), JSON.stringify(raw)]
  );

  return { barcode, name, brand, category, imageUrl, ingredients, rawData: raw };
}
