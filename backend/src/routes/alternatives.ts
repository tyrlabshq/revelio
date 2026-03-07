import { Router } from 'express';
import { db } from '../db';
import { findAlternatives } from '../services/alternatives';

export const alternativesRouter = Router();

// GET /alternatives/:barcode
// Returns top 3 cleaner alternatives for the scanned product
alternativesRouter.get('/:barcode', async (req, res) => {
  const { barcode } = req.params;

  try {
    // Fetch current product's category and flags from DB (if available)
    const pResult = await db.query(
      'SELECT category FROM products WHERE barcode = $1',
      [barcode]
    );
    const category = pResult.rows[0]?.category ?? 'food';

    // flags would come from re-scoring, but we pass empty here —
    // findAlternatives handles severity-3 filtering internally
    const alternatives = await findAlternatives(barcode, category, []);

    return res.json({ alternatives });
  } catch (err) {
    console.error('Alternatives error:', err);
    return res.status(500).json({ error: 'Failed to fetch alternatives' });
  }
});
