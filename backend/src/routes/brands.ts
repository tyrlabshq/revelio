// Brand deep-dive endpoints.
//
// Public (unauth) endpoints that power the "View all products from this
// brand" flow in the iOS client. No PII is returned — only aggregated
// product data from the `products` cache.

import { Router } from 'express';
import {
  listBrandProducts,
  getBrandSummary,
  slugifyBrand,
} from '../services/brandSummary';
import { logger } from '../logger';

export const brandsRouter = Router();

const DEFAULT_LIMIT = 24;
const MAX_LIMIT = 100;
const VALID_GRADES = new Set(['A', 'B', 'C', 'D', 'F']);

// GET /brands/:slug — paginated product list for a brand.
//
// `slug` is normalized again server-side so callers can pass either the
// slug form ("hellmanns") or the raw brand name ("Hellmann's"); we slugify
// both. Optional ?grade=A filters to a single grade.
brandsRouter.get('/:slug', async (req, res) => {
  try {
    const slug = slugifyBrand(req.params.slug);
    if (!slug) return res.status(400).json({ error: 'invalid brand slug' });

    const page = Math.max(1, parseInt((req.query.page as string) ?? '1', 10) || 1);
    const limit = Math.min(
      MAX_LIMIT,
      Math.max(1, parseInt((req.query.limit as string) ?? String(DEFAULT_LIMIT), 10) || DEFAULT_LIMIT)
    );
    const grade = typeof req.query.grade === 'string' ? req.query.grade.toUpperCase() : undefined;
    if (grade && !VALID_GRADES.has(grade)) {
      return res.status(400).json({ error: 'invalid grade' });
    }

    const result = await listBrandProducts(slug, { page, limit, grade });
    res.json({
      slug,
      page,
      limit,
      total: result.total,
      products: result.products,
    });
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'brands-list-failed' }, '[brands] GET /:slug error');
    res.status(500).json({ error: 'Failed to load brand products' });
  }
});

// GET /brands/:slug/summary — aggregate metrics for the deep-dive header.
brandsRouter.get('/:slug/summary', async (req, res) => {
  try {
    const slug = slugifyBrand(req.params.slug);
    if (!slug) return res.status(400).json({ error: 'invalid brand slug' });

    const summary = await getBrandSummary(slug);
    res.json(summary);
  } catch (err) {
    logger.error({ err: (err as Error)?.message, event: 'brands-summary-failed' }, '[brands] GET /:slug/summary error');
    res.status(500).json({ error: 'Failed to load brand summary' });
  }
});
