#!/usr/bin/env node
/**
 * Revelio — Seed products via API
 *
 * Inserts seed products by calling the scan endpoint, which fetches from
 * Open Food Facts and caches in the DB. Falls back to direct DB insert
 * if the scan endpoint doesn't create products.
 *
 * Usage:
 *   node scripts/seed-products.js                    # default: http://localhost:8430
 *   API_URL=https://api.revelio.app node scripts/seed-products.js
 *
 * Prerequisites:
 *   - Backend running (npm run dev in backend/)
 *   - DATABASE_URL set in backend/.env
 */

const API_URL = process.env.API_URL || 'http://localhost:8430';

const products = [
  // ── Food — Hall of Shame ──
  { barcode: '028400064057', name: 'Flamin\' Hot Cheetos', brand: 'Frito-Lay', category: 'food' },
  { barcode: '049000006346', name: 'Mountain Dew', brand: 'PepsiCo', category: 'food' },
  { barcode: '044000032081', name: 'Pop-Tarts Frosted Strawberry', brand: 'Kellogg\'s', category: 'food' },
  { barcode: '041196010558', name: 'Lunchables Turkey & Cheddar', brand: 'Oscar Mayer', category: 'food' },
  { barcode: '041220960095', name: 'Cool Ranch Doritos', brand: 'Frito-Lay', category: 'food' },
  { barcode: '012000161155', name: 'Gatorade Fruit Punch', brand: 'PepsiCo', category: 'food' },
  // ── Food — Hidden Gems ──
  { barcode: '859006004019', name: 'RXBar Chocolate Sea Salt', brand: 'RXBAR', category: 'food' },
  { barcode: '853715003992', name: 'EPIC Venison Bar', brand: 'EPIC Provisions', category: 'food' },
  { barcode: '850004207017', name: 'Hu Dark Chocolate 70%', brand: 'Hu Kitchen', category: 'food' },
  { barcode: '851710003664', name: 'Primal Kitchen Avocado Mayo', brand: 'Primal Kitchen', category: 'food' },
  { barcode: '850025974011', name: 'Siete Grain-Free Tortilla Chips', brand: 'Siete', category: 'food' },
  { barcode: '810005411318', name: 'Chomps Original Beef Stick', brand: 'Chomps', category: 'food' },
  // ── Food — Mid ──
  { barcode: '038000138416', name: 'Cheerios Original', brand: 'General Mills', category: 'food' },
  { barcode: '041570054826', name: 'Ritz Crackers', brand: 'Nabisco', category: 'food' },
  { barcode: '021131502850', name: 'Nature Valley Granola Bar', brand: 'General Mills', category: 'food' },
  // ── Cosmetics ──
  { barcode: '3614272049529', name: 'CeraVe Moisturizing Cream', brand: 'CeraVe', category: 'cosmetics' },
  { barcode: '5010724527474', name: 'Neutrogena Ultra Sheer SPF 70', brand: 'Neutrogena', category: 'cosmetics' },
  { barcode: '0854220005045', name: 'Native Deodorant Coconut Vanilla', brand: 'Native', category: 'cosmetics' },
  { barcode: '630382028724', name: 'Dove Beauty Bar', brand: 'Dove', category: 'cosmetics' },
  { barcode: '5011321680593', name: 'The Ordinary Niacinamide 10%', brand: 'The Ordinary', category: 'cosmetics' },
  // ── Cleaning ──
  { barcode: '757037514009', name: 'Branch Basics Concentrate', brand: 'Branch Basics', category: 'cleaning' },
  { barcode: '037000348856', name: 'Tide Original Detergent', brand: 'Procter & Gamble', category: 'cleaning' },
  { barcode: '817256020010', name: 'Blueland Multi-Surface Tablet', brand: 'Blueland', category: 'cleaning' },
  { barcode: '021130126163', name: 'Lysol Disinfecting Wipes', brand: 'Lysol', category: 'cleaning' },
  // ── Supplements ──
  { barcode: '733739004253', name: 'NOW Foods Magnesium Glycinate', brand: 'NOW Foods', category: 'supplements' },
  { barcode: '021078025504', name: 'Centrum Silver Adults 50+', brand: 'Centrum', category: 'supplements' },
  { barcode: '653341130693', name: 'Athletic Greens AG1', brand: 'AG1', category: 'supplements' },
  { barcode: '850032307017', name: 'Seed DS-01 Daily Synbiotic', brand: 'Seed', category: 'supplements' },
  { barcode: '850002660012', name: 'Liquid IV Hydration Multiplier', brand: 'Liquid IV', category: 'food' },
  { barcode: '711381020513', name: 'Garden of Life Vitamin Code Raw B-Complex', brand: 'Garden of Life', category: 'supplements' },
];

async function seedViaScans() {
  console.log(`Seeding ${products.length} products via ${API_URL}/scan/:barcode\n`);

  let success = 0;
  let failed = 0;

  for (const p of products) {
    try {
      const res = await fetch(`${API_URL}/scan/${p.barcode}`);
      const data = await res.json();

      if (res.ok) {
        console.log(`  ✅ ${p.name} (${p.barcode}) — score: ${data.score ?? '?'}, grade: ${data.grade ?? '?'}`);
        success++;
      } else {
        console.log(`  ⚠️  ${p.name} (${p.barcode}) — ${res.status}: ${data.error || 'unknown'}`);
        failed++;
      }
    } catch (err) {
      console.log(`  ❌ ${p.name} (${p.barcode}) — ${err.message}`);
      failed++;
    }
  }

  console.log(`\nDone: ${success} seeded, ${failed} failed`);

  if (failed > 0) {
    console.log('\nTip: If the API isn\'t running, use the SQL seed instead:');
    console.log('  psql $DATABASE_URL -f scripts/seed-products.sql');
  }
}

seedViaScans();
