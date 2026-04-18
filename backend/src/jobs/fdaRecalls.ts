import { db } from '../db';
import { sendPush } from '../services/push';

// ─── openFDA endpoints ────────────────────────────────────────────────────────

type ProductType = 'food' | 'drug' | 'cosmetic';

const FDA_ENDPOINTS: Record<ProductType, string> = {
  food: 'https://api.fda.gov/food/enforcement.json',
  drug: 'https://api.fda.gov/drug/enforcement.json',
  cosmetic: 'https://api.fda.gov/cosmetic/enforcement.json',
};

interface FdaEnforcementRecord {
  recall_number?: string;
  classification?: string;
  product_description?: string;
  reason_for_recall?: string;
  recalling_firm?: string;
  product_type?: string;
  code_info?: string;
  recall_initiation_date?: string;
}

interface FdaEnforcementResponse {
  results?: FdaEnforcementRecord[];
  error?: { code?: string; message?: string };
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function yyyymmdd(date: Date): string {
  return date.toISOString().slice(0, 10).replace(/-/g, '');
}

function isoDate(value: string | undefined): string | null {
  if (!value) return null;
  // openFDA returns YYYYMMDD; normalize to YYYY-MM-DD for DATE column.
  if (/^\d{8}$/.test(value)) {
    return `${value.slice(0, 4)}-${value.slice(4, 6)}-${value.slice(6, 8)}`;
  }
  return value;
}

/**
 * Best-effort UPC extraction from the free-text `code_info` field. openFDA
 * has no structured UPC column; firms paste lot numbers, UPCs, SKUs, and
 * prose into one string. We accept both 12-digit UPC-A and 13-digit EAN-13
 * runs, plus 8-digit UPC-E (rare). Duplicates deduped.
 */
export function extractUpcCodes(codeInfo: string | undefined): string[] {
  if (!codeInfo) return [];
  const found = new Set<string>();
  // Match 8, 12, 13 or 14-digit numeric runs bounded by non-digits.
  const regex = /(?<!\d)(\d{8}|\d{12,14})(?!\d)/g;
  let m: RegExpExecArray | null;
  while ((m = regex.exec(codeInfo)) !== null) {
    found.add(m[1]);
  }
  return Array.from(found);
}

async function fetchRecallsForType(productType: ProductType, sinceDays = 14): Promise<FdaEnforcementRecord[]> {
  const today = new Date();
  const from = new Date(today.getTime() - sinceDays * 24 * 60 * 60 * 1000);
  const search = `report_date:[${yyyymmdd(from)}+TO+${yyyymmdd(today)}]`;
  const url = `${FDA_ENDPOINTS[productType]}?search=${search}&limit=100`;

  try {
    const res = await fetch(url);
    if (!res.ok) {
      // openFDA returns 404 when a query window has zero results — that's not an error for us.
      if (res.status === 404) return [];
      console.error(`[fdaRecalls] ${productType} fetch failed: HTTP ${res.status}`);
      return [];
    }
    const json = (await res.json()) as FdaEnforcementResponse;
    return json.results ?? [];
  } catch (err) {
    console.error(`[fdaRecalls] ${productType} fetch exception:`, err);
    return [];
  }
}

// ─── Match & notify ───────────────────────────────────────────────────────────

/**
 * For a newly-inserted recall, find every user whose scan history or pantry
 * contains one of the recalled UPCs. Insert a recall_notifications row
 * (ON CONFLICT DO NOTHING so repeated ingests are idempotent) and enqueue
 * a push payload via sendPush().
 */
export async function matchAndNotify(recallId: string): Promise<number> {
  const recallRow = await db.query(
    `SELECT id, recall_number, product_description, recalling_firm,
            reason_for_recall, upc_codes
     FROM recalls WHERE id = $1`,
    [recallId]
  );
  const recall = recallRow.rows[0];
  if (!recall || !recall.upc_codes || recall.upc_codes.length === 0) return 0;

  // Users with matching scans OR pantry items.
  const affected = await db.query(
    `SELECT DISTINCT user_id, barcode FROM (
       SELECT user_id, barcode FROM scans
         WHERE user_id IS NOT NULL AND barcode = ANY($1::text[])
       UNION
       SELECT user_id::uuid AS user_id, barcode FROM pantry_items
         WHERE barcode = ANY($1::text[])
     ) AS matches`,
    [recall.upc_codes]
  );

  let notified = 0;
  for (const row of affected.rows as Array<{ user_id: string; barcode: string }>) {
    const ins = await db.query(
      `INSERT INTO recall_notifications (user_id, recall_id, barcode)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, recall_id, barcode) DO NOTHING
       RETURNING id`,
      [row.user_id, recall.id, row.barcode]
    );
    if (ins.rowCount === 0) continue; // already notified
    notified += 1;

    const productLine = recall.recalling_firm
      ? `${recall.recalling_firm} – ${recall.product_description}`
      : recall.product_description;
    await sendPush(row.user_id, {
      title: 'Product Recall Alert',
      body: `A product you scanned (${productLine}) has been recalled. Reason: ${recall.reason_for_recall}`,
      data: {
        kind: 'recall',
        recallId: recall.id,
        recallNumber: recall.recall_number,
        barcode: row.barcode,
      },
    });
  }
  return notified;
}

// ─── Ingest entry point ───────────────────────────────────────────────────────

export async function ingestRecentRecalls(): Promise<{ inserted: number; notified: number }> {
  let inserted = 0;
  let notified = 0;

  for (const type of Object.keys(FDA_ENDPOINTS) as ProductType[]) {
    const records = await fetchRecallsForType(type, 14);
    for (const rec of records) {
      if (!rec.recall_number || !rec.product_description || !rec.reason_for_recall) continue;

      const upcCodes = extractUpcCodes(rec.code_info);
      const classification = rec.classification ?? 'Unknown';
      const productType = (rec.product_type?.toLowerCase() as ProductType | undefined) ?? type;

      const insertResult = await db.query(
        `INSERT INTO recalls
          (recall_number, classification, product_description, reason_for_recall,
           recalling_firm, product_type, upc_codes, recall_initiation_date)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (recall_number) DO NOTHING
         RETURNING id`,
        [
          rec.recall_number,
          classification,
          rec.product_description,
          rec.reason_for_recall,
          rec.recalling_firm ?? null,
          productType,
          upcCodes,
          isoDate(rec.recall_initiation_date),
        ]
      );

      const newId: string | undefined = insertResult.rows[0]?.id;
      if (!newId) continue; // already seen — skip match pass

      inserted += 1;
      notified += await matchAndNotify(newId);
    }
  }

  console.log(`[fdaRecalls] ingest complete: ${inserted} new recalls, ${notified} user notifications`);
  return { inserted, notified };
}
