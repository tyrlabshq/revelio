import { Router } from 'express';
export const profileRouter = Router();
profileRouter.get('/', async (_, res) => res.json({ profile: null }));
