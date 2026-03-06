import { Router } from 'express';
export const alternativesRouter = Router();
alternativesRouter.get('/:barcode', async (_, res) => res.json({ alternatives: [] }));
