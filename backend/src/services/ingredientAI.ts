import OpenAI from 'openai';
import { createHash } from 'crypto';

// ─── OpenAI Client (lazy — only used when AI explainer route is called) ───────

let openai: OpenAI | null = null;
function getOpenAI(): OpenAI {
  if (!openai) {
    openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY || 'sk-placeholder' });
  }
  return openai;
}

// ─── In-Memory Cache ──────────────────────────────────────────────────────────

interface CacheEntry {
  explanation: string;
  timestamp: number;
}

const CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
const explanationCache = new Map<string, CacheEntry>();

function getCacheKey(ingredientName: string, priorities: string[]): string {
  const normalizedName = ingredientName.toLowerCase().trim();
  const prioritiesHash = createHash('md5')
    .update(priorities.slice().sort().join(','))
    .digest('hex');
  return `ingredient:${normalizedName}:${prioritiesHash}`;
}

function getCached(key: string): string | null {
  const entry = explanationCache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.timestamp > CACHE_TTL_MS) {
    explanationCache.delete(key);
    return null;
  }
  return entry.explanation;
}

function setCache(key: string, explanation: string): void {
  explanationCache.set(key, { explanation, timestamp: Date.now() });
}

// ─── explainIngredient ────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `You are a food and cosmetic safety expert. Give clear, factual, non-alarmist explanations of why certain ingredients may be concerning. Always cite whether the concern is: (1) well-established science, (2) emerging research, or (3) precautionary. Keep it under 100 words. End with one concrete action tip.`;

/**
 * Get an AI explanation for why an ingredient is flagged.
 * Caches responses in-memory with a 24-hour TTL.
 */
export async function explainIngredient(
  ingredientName: string,
  productCategory: string,
  userPriorities: string[]
): Promise<{ explanation: string; cached: boolean }> {
  const cacheKey = getCacheKey(ingredientName, userPriorities);
  const cached = getCached(cacheKey);

  if (cached) {
    return { explanation: cached, cached: true };
  }

  const prioritiesText = userPriorities.length > 0
    ? userPriorities.join(', ')
    : 'general health';

  const userPrompt = `Explain why ${ingredientName} is flagged in ${productCategory} products. User priorities: ${prioritiesText}`;

  const completion = await getOpenAI().chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: userPrompt },
    ],
    max_tokens: 200,
    temperature: 0.7,
  });

  const explanation = completion.choices[0]?.message?.content?.trim() ?? 'No explanation available.';
  setCache(cacheKey, explanation);

  return { explanation, cached: false };
}
