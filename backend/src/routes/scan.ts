import { Router } from 'express';
import { db } from '../db';
export const scanRouter = Router();

const OFF_BASE = 'https://world.openfoodfacts.org/api/v2/product';

async function fetchFromAPI(barcode: string): Promise<any> {
  try {
    const res = await fetch(\`\${OFF_BASE}/\${barcode}.json?fields=product_name,brands,image_url,ingredients_text,categories_tags\`);
    const data = await res.json() as any;
    if (data.status === 1 && data.product) return data.product;
  } catch {}
  return null;
}

function parseIngredients(text: string): string[] {
  if (!text) return [];
  return text.toLowerCase().replace(/\\([^)]*\\)/g, '').replace(/\\d+%/g, '')
    .split(/[,;]/).map(s => s.trim().replace(/^[\\-*•]/, '').trim()).filter(s => s.length > 1);
}

function scoreIngredients(ingredients: string[], flags: any[]) {
  const matched: any[] = [];
  let penalty = 0;
  for (const f of flags) {
    const name = f.ingredient_name.toLowerCase();
    if (ingredients.some(i => i.includes(name) || name.includes(i))) {
      matched.push(f);
      penalty += f.severity === 1 ? 5 : f.severity === 2 ? 15 : f.severity === 3 ? 25 : 0;
    }
  }
  const score = Math.max(20, Math.min(100, 100 - penalty));
  const grade = score >= 80 ? 'A' : score >= 65 ? 'B' : score >= 50 ? 'C' : score >= 35 ? 'D' : 'F';
  return { score, grade, flags: matched };
}

scanRouter.get('/:barcode', async (req, res) => {
  const { barcode } = req.params;
  try {
    const cached = await db.query('SELECT * FROM products WHERE barcode = \$1', [barcode]);
    let product = cached.rows[0];
    const needsFetch = !product || (Date.now() - new Date(product.last_fetched).getTime() > 7 * 24 * 60 * 60 * 1000);

    if (needsFetch) {
      const raw = await fetchFromAPI(barcode);
      if (!raw) return res.status(404).json({ found: false, barcode });
      const ingredients = parseIngredients(raw.ingredients_text || '');
      const category = (raw.categories_tags || []).some((c: string) => c.includes('cosmetic') || c.includes('beauty')) ? 'cosmetics' : 'food';
      await db.query(\`
        INSERT INTO products (barcode, name, brand, category, image_url, ingredients, off_data, last_fetched)
        VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, NOW())
        ON CONFLICT (barcode) DO UPDATE SET name=\$2, brand=\$3, category=\$4, image_url=\$5, ingredients=\$6, off_data=\$7, last_fetched=NOW()\`,
        [barcode, raw.product_name || 'Unknown', raw.brands || 'Unknown', category, raw.image_url, JSON.stringify(ingredients), JSON.stringify(raw)]
      );
      product = { barcode, name: raw.product_name, brand: raw.brands, category, image_url: raw.image_url, ingredients };
    }

    const ings = typeof product.ingredients === 'string' ? JSON.parse(product.ingredients) : product.ingredients;
    const flagsRes = await db.query('SELECT * FROM ingredient_flags ORDER BY severity DESC');
    const { score, grade, flags } = scoreIngredients(ings, flagsRes.rows);

    res.json({
      id: crypto.randomUUID(), barcode, productName: product.name || 'Unknown', brand: product.brand || 'Unknown',
      category: product.category || 'food', imageUrl: product.image_url, ingredients: ings, flags,
      baseScore: score, personalizedScore: score, grade, scannedAt: new Date().toISOString()
    });
  } catch (err) {
    console.error('Scan error:', err);
    res.status(500).json({ error: 'Failed to scan' });
  }
});
