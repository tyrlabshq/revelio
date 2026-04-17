// REV-T3.3: 7-day meal plan generator. Reads a user's pantry + profile, asks
// gpt-4o-mini for a week of breakfast/lunch/dinner using mostly clean-score
// ingredients, and caches the result for 24 hours per userId.
//
// TODO: assumes OPENAI_API_KEY is set in prod (enforced by the backend-security
// startup guard in index.ts).

import OpenAI from 'openai';
import { db } from '../db';

let openai: OpenAI | null = null;
function getOpenAI(): OpenAI {
  if (!openai) {
    openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY || 'sk-placeholder' });
  }
  return openai;
}

// ─── Types ────────────────────────────────────────────────────────────────────

export interface MealPlanDay {
  day: number; // 1..7
  breakfast: string;
  lunch: string;
  dinner: string;
  shoppingList: string[];
}

export interface MealPlan {
  days: MealPlanDay[];
  generatedAt: number;
  summary?: string;
}

// ─── Cache ────────────────────────────────────────────────────────────────────

const CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const planCache = new Map<string, { plan: MealPlan; expires: number }>();

function cachedPlan(userId: string): MealPlan | null {
  const entry = planCache.get(userId);
  if (!entry) return null;
  if (Date.now() > entry.expires) {
    planCache.delete(userId);
    return null;
  }
  return entry.plan;
}

function storePlan(userId: string, plan: MealPlan): void {
  planCache.set(userId, { plan, expires: Date.now() + CACHE_TTL_MS });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

async function loadUserContext(userId: string): Promise<{
  pantry: Array<{ name: string; brand: string; grade: string }>;
  goals: string[];
  allergies: string[];
  priorities: string[];
}> {
  const [pantryRes, profileRes] = await Promise.all([
    db.query(
      `SELECT product_name, brand, grade FROM pantry_items WHERE user_id::text = $1 ORDER BY grade ASC`,
      [userId]
    ),
    db.query(
      `SELECT goals, allergies, priorities FROM user_profiles WHERE id = $1`,
      [userId]
    ),
  ]);

  const pantry = pantryRes.rows.map((r: any) => ({
    name: r.product_name || 'Unknown',
    brand: r.brand || '',
    grade: r.grade || 'C',
  }));
  const profile = profileRes.rows[0] || {};
  return {
    pantry,
    goals: (profile.goals ?? []) as string[],
    allergies: (profile.allergies ?? []) as string[],
    priorities: (profile.priorities ?? []) as string[],
  };
}

function buildPrompt(ctx: Awaited<ReturnType<typeof loadUserContext>>): string {
  const cleanPantry = ctx.pantry.filter(p => p.grade === 'A' || p.grade === 'B');
  const pantryText = cleanPantry.length > 0
    ? cleanPantry.map(p => `- ${p.name}${p.brand ? ` (${p.brand})` : ''} [grade ${p.grade}]`).join('\n')
    : '(no clean pantry items on file)';

  return `Build a 7-day meal plan for this user.

Clean pantry items (grade A or B) — use these as anchors:
${pantryText}

Goals: ${ctx.goals.length > 0 ? ctx.goals.join(', ') : 'general wellness'}
Allergies to avoid: ${ctx.allergies.length > 0 ? ctx.allergies.join(', ') : 'none'}
Ingredient priorities: ${ctx.priorities.length > 0 ? ctx.priorities.join(', ') : 'none specific'}

Return strict JSON only, matching this schema exactly:
{
  "summary": "<one-sentence overview>",
  "days": [
    {
      "day": 1,
      "breakfast": "<meal name — 1 short sentence>",
      "lunch": "<meal name — 1 short sentence>",
      "dinner": "<meal name — 1 short sentence>",
      "shoppingList": ["item1", "item2"]
    }
    // ... 7 total
  ]
}

Rules:
- Every day must have breakfast, lunch, and dinner.
- Favor whole, minimally-processed ingredients.
- Avoid any listed allergy.
- shoppingList per day is additional grocery items not already in the pantry.
- Keep each meal description under 140 characters.`;
}

function parsePlan(raw: string): MealPlan {
  // Strip code fences if the model wraps its JSON.
  const cleaned = raw.trim().replace(/^```(?:json)?\s*/i, '').replace(/```$/i, '').trim();
  let parsed: any;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    // Fallback: crude regex to find the outermost JSON object.
    const match = cleaned.match(/\{[\s\S]*\}/);
    if (!match) throw new Error('meal plan: no JSON in model response');
    parsed = JSON.parse(match[0]);
  }
  const rawDays = Array.isArray(parsed.days) ? parsed.days : [];
  const days: MealPlanDay[] = rawDays.slice(0, 7).map((d: any, i: number) => ({
    day: typeof d.day === 'number' ? d.day : i + 1,
    breakfast: String(d.breakfast ?? ''),
    lunch: String(d.lunch ?? ''),
    dinner: String(d.dinner ?? ''),
    shoppingList: Array.isArray(d.shoppingList)
      ? d.shoppingList.map((s: unknown) => String(s)).filter(Boolean)
      : [],
  }));
  return {
    summary: typeof parsed.summary === 'string' ? parsed.summary : undefined,
    days,
    generatedAt: Date.now(),
  };
}

// ─── Public API ───────────────────────────────────────────────────────────────

export async function generate7DayPlan(args: { userId: string }): Promise<MealPlan> {
  const cached = cachedPlan(args.userId);
  if (cached) return cached;

  const ctx = await loadUserContext(args.userId);
  const prompt = buildPrompt(ctx);

  const completion = await getOpenAI().chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content:
          'You are a registered-dietitian meal planner who speaks in tight, friendly prose. Always respond with valid JSON only, no prose before or after.',
      },
      { role: 'user', content: prompt },
    ],
    max_tokens: 1400,
    temperature: 0.6,
    response_format: { type: 'json_object' },
  });

  const raw = completion.choices[0]?.message?.content ?? '';
  const plan = parsePlan(raw);
  storePlan(args.userId, plan);
  return plan;
}

// Expose cache control for tests / admin routes.
export function invalidateMealPlanCache(userId?: string): void {
  if (userId) planCache.delete(userId);
  else planCache.clear();
}
