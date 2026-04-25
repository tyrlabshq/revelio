# Revelio Scripts

## seed-products.sql

Direct SQL seed — inserts 30 products across all 4 categories (food, cosmetics, cleaning, supplements) plus fake scan records for the trending endpoint.

```bash
# Ensure migrations have been run first
psql $DATABASE_URL -f backend/migrations/001_initial.sql
psql $DATABASE_URL -f backend/migrations/005_scans_history.sql

# Run seed
psql $DATABASE_URL -f scripts/seed-products.sql
```

**What it seeds:**
- 6 Hall of Shame products (score < 30) — Cheetos, Mountain Dew, Pop-Tarts, etc.
- 6 Hidden Gems (score > 85) — RXBar, Hu Chocolate, Primal Kitchen, etc.
- 3 Mid-range food products — Cheerios, Ritz, Nature Valley
- 5 Cosmetics — CeraVe, Neutrogena, Native, Dove, The Ordinary
- 4 Cleaning — Branch Basics, Tide, Blueland, Lysol
- 6 Supplements — NOW Foods, Centrum, AG1, Seed, Liquid IV, Garden of Life
- Proportional scan records for `/products/trending`

**Also adds missing columns** (`id`, `product_name`, `score`, `grade`, `scan_count`, `created_at`) that the product routes expect but aren't in the initial migration.

## seed-products.js

Node.js script that seeds products by hitting the scan endpoint, which fetches real data from Open Food Facts and scores it through Revelio's engine.

```bash
# With backend running locally
node scripts/seed-products.js

# Against a deployed API
API_URL=https://api.revelio.app node scripts/seed-products.js
```

Requires the backend to be running. Falls back with guidance to use the SQL seed if the API is unavailable.
