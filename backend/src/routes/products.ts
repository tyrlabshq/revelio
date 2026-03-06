import { Router } from 'express';
export const productRouter = Router();
productRouter.get('/search', async (_, res) => res.json({ results: [] }));
productRouter.get('/trending', async (_, res) => res.json({ products: [] }));
