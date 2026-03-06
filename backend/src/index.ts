import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { scanRouter } from './routes/scan';
import { productRouter } from './routes/products';
import { ingredientRouter } from './routes/ingredients';
import { alternativesRouter } from './routes/alternatives';
import { pantryRouter } from './routes/pantry';
import { profileRouter } from './routes/profiles';
import { authRouter } from './routes/auth';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 8430;

app.use(cors());
app.use(express.json());

app.get('/health', (_, res) => res.json({ ok: true, service: 'revelio-api', version: '1.0.0' }));

app.use('/auth', authRouter);
app.use('/scan', scanRouter);
app.use('/products', productRouter);
app.use('/ingredients', ingredientRouter);
app.use('/alternatives', alternativesRouter);
app.use('/pantry', pantryRouter);
app.use('/profiles', profileRouter);

app.listen(PORT, () => console.log(`Revelio API on :${PORT}`));
