// REV-T3.4: Batch backfill embeddings for every product missing one.
// Runs from a cron or CLI: `ts-node src/jobs/embedProducts.ts`.
//
// TODO: requires OPENAI_API_KEY to be set in prod (already enforced by the
// backend-security agent's startup guard in index.ts).

import OpenAI from 'openai';
import { db } from '../db';

const BATCH_SIZE = 100;
const EMBED_MODEL = 'text-embedding-3-small';

let openai: OpenAI | null = null;
function getOpenAI(): OpenAI {
  if (!openai) {
    openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY || 'sk-placeholder' });
  }
  return openai;
}

/** Shape of the descriptor row pulled from Postgres. */
interface ProductRow {
  barcode: string;
  name: string | null;
  brand: string | null;
  category: string | null;
  ingredients: unknown;
}

/** Build the canonical descriptor string the embedder sees. */
export function buildDescriptor(row: ProductRow): string {
  const name = (row.name ?? '').toString().trim();
  const brand = (row.brand ?? '').toString().trim();
  const category = (row.category ?? 'food').toString().trim();

  let ings: string[] = [];
  try {
    if (typeof row.ingredients === 'string') {
      ings = JSON.parse(row.ingredients);
    } else if (Array.isArray(row.ingredients)) {
      ings = row.ingredients as string[];
    }
  } catch {
    ings = [];
  }
  const topIngredients = ings.slice(0, 10).map(s => String(s).trim()).filter(Boolean);

  return [
    name ? `Name: ${name}` : '',
    brand ? `Brand: ${brand}` : '',
    `Category: ${category}`,
    topIngredients.length > 0 ? `Top ingredients: ${topIngredients.join(', ')}` : '',
  ]
    .filter(Boolean)
    .join('\n');
}

/** Convert a JS number[] into the pgvector text literal `[0.1,0.2,...]`. */
function toPgVectorLiteral(values: number[]): string {
  return `[${values.join(',')}]`;
}

/**
 * Embed a single product inline (used by the dupe-finder fallback path).
 * Returns the vector literal suitable for an `UPDATE` binding.
 */
export async function embedOneProduct(row: ProductRow): Promise<string> {
  const descriptor = buildDescriptor(row);
  const resp = await getOpenAI().embeddings.create({
    model: EMBED_MODEL,
    input: descriptor,
  });
  const vec = resp.data[0]?.embedding;
  if (!vec) throw new Error('no embedding returned');
  return toPgVectorLiteral(vec);
}

/**
 * Pull the next batch of un-embedded products and embed them.
 * Returns the number of rows written. Idempotent; safe to re-run.
 */
export async function embedMissingProducts(limit = BATCH_SIZE): Promise<number> {
  // Pull candidates.
  const { rows } = await db.query<ProductRow>(
    `SELECT barcode, name, brand, category, ingredients
       FROM products
      WHERE description_embedding IS NULL
      LIMIT $1`,
    [limit]
  );
  if (rows.length === 0) return 0;

  // Build descriptors.
  const descriptors = rows.map(buildDescriptor);

  // Batch-embed (OpenAI supports arrays).
  const resp = await getOpenAI().embeddings.create({
    model: EMBED_MODEL,
    input: descriptors,
  });

  let wrote = 0;
  for (let i = 0; i < rows.length; i++) {
    const embedding = resp.data[i]?.embedding;
    if (!embedding) continue;
    const literal = toPgVectorLiteral(embedding);
    try {
      await db.query(
        `UPDATE products SET description_embedding = $1::vector WHERE barcode = $2`,
        [literal, rows[i].barcode]
      );
      wrote += 1;
    } catch (err) {
      console.error('[embedProducts] write failed for', rows[i].barcode, err);
    }
  }

  return wrote;
}

/**
 * Loop until there is nothing left to embed, or until we hit maxBatches.
 * Useful for CLI runs: `ts-node src/jobs/embedProducts.ts --all`.
 */
export async function embedAllMissingProducts(maxBatches = 1000): Promise<number> {
  let total = 0;
  for (let i = 0; i < maxBatches; i++) {
    const wrote = await embedMissingProducts(BATCH_SIZE);
    if (wrote === 0) break;
    total += wrote;
    console.log(`[embedProducts] batch ${i + 1}: wrote ${wrote} (running total ${total})`);
  }
  return total;
}

// CLI entry point — only runs when invoked directly.
if (require.main === module) {
  const all = process.argv.includes('--all');
  const runner = all ? embedAllMissingProducts() : embedMissingProducts();
  runner
    .then(n => {
      console.log(`[embedProducts] done, wrote ${n} embeddings`);
      process.exit(0);
    })
    .catch(err => {
      console.error('[embedProducts] fatal:', err);
      process.exit(1);
    });
}
