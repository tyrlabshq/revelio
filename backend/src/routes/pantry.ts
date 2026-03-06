import { Router } from 'express';
export const pantryRouter = Router();
pantryRouter.get('/', async (_, res) => res.json({ items: [] }));
