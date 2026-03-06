import { Router } from 'express';
export const ingredientRouter = Router();
ingredientRouter.get('/:name', async (_, res) => res.json({ ok: true }));
