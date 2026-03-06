import { Router } from 'express';
export const authRouter = Router();
authRouter.post('/request-otp', async (_, res) => res.json({ ok: true }));
authRouter.post('/verify-otp', async (_, res) => res.json({ ok: true, token: '' }));
