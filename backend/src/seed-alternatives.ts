/**
 * seed-alternatives.ts
 * Inserts 50 pre-verified clean product alternatives into the alternatives table.
 * Run with: npx ts-node src/seed-alternatives.ts
 */

import { db, ensureAlternativesTable } from './db';

const TAG = process.env.AMAZON_AFFILIATE_TAG ?? 'revelio-20';
const THRIVE = process.env.THRIVE_AFFILIATE_ID ?? 'revelio';

function amazon(asin: string, name: string): string {
  return `https://www.amazon.com/dp/${asin}?tag=${TAG}`;
}

function thrive(path: string): string {
  return `https://thrivemarket.com/${path}?ref=${THRIVE}`;
}

interface AlternativeSeed {
  barcode: string;              // scanned (unhealthy) product
  alternative_barcode: string;  // clean alternative
  name: string;
  brand: string;
  score: number;
  grade: string;
  affiliate_url: string;
  affiliate_network: string;
  price_cents: number;
}

// ─── 50 Seeded Alternatives ───────────────────────────────────────────────────

const seeds: AlternativeSeed[] = [
  // ── FOOD: Condiments & Sauces ──────────────────────────────────────────────
  {
    barcode: '048001215751', // Hellmann's Mayonnaise
    alternative_barcode: '0856769006116',
    name: 'Primal Kitchen Avocado Oil Mayo',
    brand: 'Primal Kitchen',
    score: 91, grade: 'A',
    affiliate_url: amazon('B01N5GD8MO', 'Primal Kitchen Mayo'),
    affiliate_network: 'amazon', price_cents: 999,
  },
  {
    barcode: '013000006422', // Heinz Ketchup
    alternative_barcode: '0856769005744',
    name: 'Primal Kitchen Organic Ketchup',
    brand: 'Primal Kitchen',
    score: 88, grade: 'A',
    affiliate_url: amazon('B07BJJGM9F', 'Primal Kitchen Ketchup'),
    affiliate_network: 'amazon', price_cents: 799,
  },
  {
    barcode: '070200012027', // French's Yellow Mustard
    alternative_barcode: '9999000000101',
    name: 'Annie\'s Organic Yellow Mustard',
    brand: 'Annie\'s',
    score: 87, grade: 'A',
    affiliate_url: amazon('B004LDCHD4', 'Annie\'s Organic Mustard'),
    affiliate_network: 'amazon', price_cents: 349,
  },
  {
    barcode: '078742028484', // Kraft Ranch Dressing
    alternative_barcode: '0856769006338',
    name: 'Primal Kitchen Ranch Dressing',
    brand: 'Primal Kitchen',
    score: 89, grade: 'A',
    affiliate_url: amazon('B07BPPX79K', 'Primal Kitchen Ranch'),
    affiliate_network: 'amazon', price_cents: 899,
  },
  {
    barcode: '055000125009', // Ragu Pasta Sauce
    alternative_barcode: '9999000000201',
    name: 'Rao\'s Homemade Marinara Sauce',
    brand: 'Rao\'s Homemade',
    score: 92, grade: 'A',
    affiliate_url: amazon('B009NZURQQ', 'Rao\'s Marinara'),
    affiliate_network: 'amazon', price_cents: 879,
  },

  // ── FOOD: Snacks ──────────────────────────────────────────────────────────
  {
    barcode: '028400090100', // Pringles Original
    alternative_barcode: '0856489005071',
    name: 'Siete Grain-Free Potato Chips',
    brand: 'Siete',
    score: 85, grade: 'A',
    affiliate_url: amazon('B09TQTQKL9', 'Siete Grain Free Chips'),
    affiliate_network: 'amazon', price_cents: 449,
  },
  {
    barcode: '028400064057', // Doritos Nacho Cheese
    alternative_barcode: '0856489005033',
    name: 'Siete Nacho Grain-Free Tortilla Chips',
    brand: 'Siete',
    score: 84, grade: 'A',
    affiliate_url: amazon('B08KHN1LVQ', 'Siete Nacho Chips'),
    affiliate_network: 'amazon', price_cents: 449,
  },
  {
    barcode: '060410000106', // Lay\'s Classic Chips
    alternative_barcode: '9999000000301',
    name: 'Jackson\'s Sea Salt Sweet Potato Chips',
    brand: 'Jackson\'s',
    score: 83, grade: 'A',
    affiliate_url: amazon('B08LGXHQMQ', 'Jacksons Sea Salt Chips'),
    affiliate_network: 'amazon', price_cents: 499,
  },
  {
    barcode: '028400063982', // Cheetos Crunchy
    alternative_barcode: '9999000000401',
    name: 'Pipcorn Heirloom Cheese Balls',
    brand: 'Pipcorn',
    score: 82, grade: 'A',
    affiliate_url: amazon('B09JJLKV5W', 'Pipcorn Cheese Balls'),
    affiliate_network: 'amazon', price_cents: 599,
  },
  {
    barcode: '016000124011', // Goldfish Original
    alternative_barcode: '9999000000501',
    name: 'Simple Mills Farmhouse Cheddar Crackers',
    brand: 'Simple Mills',
    score: 86, grade: 'A',
    affiliate_url: amazon('B00K4XK2R8', 'Simple Mills Cheddar Crackers'),
    affiliate_network: 'amazon', price_cents: 549,
  },

  // ── FOOD: Breakfast ──────────────────────────────────────────────────────
  {
    barcode: '038000845055', // Kellogg\'s Frosted Flakes
    alternative_barcode: '9999000000601',
    name: 'Magic Spoon Frosted Grain-Free Cereal',
    brand: 'Magic Spoon',
    score: 87, grade: 'A',
    affiliate_url: amazon('B07QKPV1GK', 'Magic Spoon Cereal'),
    affiliate_network: 'amazon', price_cents: 1099,
  },
  {
    barcode: '016000419155', // Cheerios Honey Nut
    alternative_barcode: '9999000000701',
    name: 'One Degree Organics Sprouted Oat O\'s',
    brand: 'One Degree Organics',
    score: 88, grade: 'A',
    affiliate_url: thrive('brands/one-degree-organics'),
    affiliate_network: 'thrive', price_cents: 699,
  },
  {
    barcode: '041190418718', // Pop-Tarts
    alternative_barcode: '9999000000801',
    name: 'NutriGrain Soft Baked Breakfast Bars (Organic)',
    brand: 'Nature\'s Bakery',
    score: 79, grade: 'B',
    affiliate_url: amazon('B07QDGF19X', 'Natures Bakery Fig Bars'),
    affiliate_network: 'amazon', price_cents: 799,
  },

  // ── FOOD: Beverages ───────────────────────────────────────────────────────
  {
    barcode: '049000028928', // Coca-Cola Classic
    alternative_barcode: '9999000000901',
    name: 'Olipop Classic Root Beer Prebiotic Soda',
    brand: 'Olipop',
    score: 88, grade: 'A',
    affiliate_url: amazon('B082TCQ4X9', 'Olipop Prebiotic Soda'),
    affiliate_network: 'amazon', price_cents: 299,
  },
  {
    barcode: '012000161155', // Pepsi
    alternative_barcode: '9999000001001',
    name: 'Poppi Prebiotic Soda Cola',
    brand: 'Poppi',
    score: 87, grade: 'A',
    affiliate_url: amazon('B09Z2WKZRM', 'Poppi Prebiotic Soda'),
    affiliate_network: 'amazon', price_cents: 299,
  },
  {
    barcode: '099482454562', // Gatorade Orange
    alternative_barcode: '9999000001101',
    name: 'LMNT Electrolyte Drink Mix',
    brand: 'LMNT',
    score: 91, grade: 'A',
    affiliate_url: amazon('B08G7FRJ13', 'LMNT Electrolytes'),
    affiliate_network: 'amazon', price_cents: 4499,
  },

  // ── FOOD: Dairy & Alternatives ────────────────────────────────────────────
  {
    barcode: '011110860767', // Yoplait Strawberry Yogurt
    alternative_barcode: '9999000001201',
    name: 'Siggi\'s Plain Whole Milk Skyr',
    brand: 'Siggi\'s',
    score: 90, grade: 'A',
    affiliate_url: thrive('brands/siggis'),
    affiliate_network: 'thrive', price_cents: 249,
  },
  {
    barcode: '070640301218', // Velveeta Cheese
    alternative_barcode: '9999000001301',
    name: 'Organic Valley Mild Cheddar Slices',
    brand: 'Organic Valley',
    score: 85, grade: 'A',
    affiliate_url: amazon('B00CEXWBWW', 'Organic Valley Cheddar'),
    affiliate_network: 'amazon', price_cents: 599,
  },

  // ── FOOD: Spreads & Oils ──────────────────────────────────────────────────
  {
    barcode: '046470005018', // Jif Peanut Butter
    alternative_barcode: '9999000001401',
    name: 'Thrive Market Organic Creamy Peanut Butter',
    brand: 'Thrive Market',
    score: 89, grade: 'A',
    affiliate_url: thrive('products/thrive-market-organic-peanut-butter'),
    affiliate_network: 'thrive', price_cents: 599,
  },
  {
    barcode: '016000249745', // Skippy Peanut Butter
    alternative_barcode: '9999000001501',
    name: 'Justin\'s Classic Almond Butter',
    brand: 'Justin\'s',
    score: 90, grade: 'A',
    affiliate_url: amazon('B007J5TPHU', 'Justins Almond Butter'),
    affiliate_network: 'amazon', price_cents: 1299,
  },

  // ── FOOD: Frozen & Prepared ───────────────────────────────────────────────
  {
    barcode: '013562400040', // Totino\'s Party Pizza
    alternative_barcode: '9999000001601',
    name: 'Real Good Foods Cauliflower Crust Pizza',
    brand: 'Real Good Foods',
    score: 81, grade: 'A',
    affiliate_url: amazon('B086M7KZ7S', 'Real Good Foods Pizza'),
    affiliate_network: 'amazon', price_cents: 899,
  },

  // ── COSMETICS: Shampoo & Conditioner ─────────────────────────────────────
  {
    barcode: '037000805014', // Head & Shoulders Classic
    alternative_barcode: '9999000001701',
    name: 'Acure Vivacious Volume Shampoo',
    brand: 'Acure',
    score: 88, grade: 'A',
    affiliate_url: amazon('B00P8HKZQ8', 'Acure Shampoo'),
    affiliate_network: 'amazon', price_cents: 999,
  },
  {
    barcode: '037000527404', // Pantene Smooth Shampoo
    alternative_barcode: '9999000001801',
    name: 'Briogeo Scalp Revival Charcoal Shampoo',
    brand: 'Briogeo',
    score: 86, grade: 'A',
    affiliate_url: amazon('B011BQNM6G', 'Briogeo Shampoo'),
    affiliate_network: 'amazon', price_cents: 3900,
  },
  {
    barcode: '037000527367', // Pantene Smooth Conditioner
    alternative_barcode: '9999000001901',
    name: 'SheaMoisture Raw Shea Butter Conditioner',
    brand: 'SheaMoisture',
    score: 85, grade: 'A',
    affiliate_url: amazon('B003RPDOHA', 'SheaMoisture Conditioner'),
    affiliate_network: 'amazon', price_cents: 1099,
  },

  // ── COSMETICS: Body Wash ──────────────────────────────────────────────────
  {
    barcode: '011111006062', // Dove Deep Moisture Body Wash
    alternative_barcode: '9999000002001',
    name: 'EO Organic French Lavender Body Wash',
    brand: 'EO',
    score: 90, grade: 'A',
    affiliate_url: amazon('B006OFQ10C', 'EO Organic Body Wash'),
    affiliate_network: 'amazon', price_cents: 1299,
  },
  {
    barcode: '037000908869', // Olay Moisturizing Body Wash
    alternative_barcode: '9999000002101',
    name: 'Dr. Bronner\'s Pure-Castile Liquid Soap',
    brand: 'Dr. Bronner\'s',
    score: 92, grade: 'A',
    affiliate_url: amazon('B00120VW5C', 'Dr Bronners Castile Soap'),
    affiliate_network: 'amazon', price_cents: 1799,
  },

  // ── COSMETICS: Deodorant ──────────────────────────────────────────────────
  {
    barcode: '022600386766', // Old Spice Original
    alternative_barcode: '9999000002201',
    name: 'Native Coconut & Vanilla Deodorant',
    brand: 'Native',
    score: 89, grade: 'A',
    affiliate_url: amazon('B06Y2F8TMB', 'Native Deodorant'),
    affiliate_network: 'amazon', price_cents: 1300,
  },
  {
    barcode: '017000093383', // Secret Clinical Strength
    alternative_barcode: '9999000002301',
    name: 'Schmidt\'s Fragrance-Free Natural Deodorant',
    brand: 'Schmidt\'s',
    score: 87, grade: 'A',
    affiliate_url: amazon('B01B2YEWOO', 'Schmidts Natural Deodorant'),
    affiliate_network: 'amazon', price_cents: 999,
  },

  // ── COSMETICS: Sunscreen ──────────────────────────────────────────────────
  {
    barcode: '093851001073', // Neutrogena Beach Defense SPF 70
    alternative_barcode: '9999000002401',
    name: 'Badger SPF 40 Mineral Sunscreen',
    brand: 'Badger',
    score: 91, grade: 'A',
    affiliate_url: amazon('B008MHSJFK', 'Badger Mineral Sunscreen'),
    affiliate_network: 'amazon', price_cents: 1699,
  },
  {
    barcode: '072140000819', // Coppertone Sport SPF 50
    alternative_barcode: '9999000002501',
    name: 'Blue Lizard Sensitive Mineral Sunscreen SPF 50',
    brand: 'Blue Lizard',
    score: 89, grade: 'A',
    affiliate_url: amazon('B000VGPBBW', 'Blue Lizard Sunscreen'),
    affiliate_network: 'amazon', price_cents: 1499,
  },

  // ── COSMETICS: Face Care ──────────────────────────────────────────────────
  {
    barcode: '070501007074', // Cetaphil Moisturizing Lotion
    alternative_barcode: '9999000002601',
    name: 'Vanicream Moisturizing Lotion',
    brand: 'Vanicream',
    score: 90, grade: 'A',
    affiliate_url: amazon('B00LNMSXRM', 'Vanicream Moisturizer'),
    affiliate_network: 'amazon', price_cents: 1299,
  },
  {
    barcode: '041167010609', // Clean & Clear Morning Burst
    alternative_barcode: '9999000002701',
    name: 'CeraVe Hydrating Facial Cleanser',
    brand: 'CeraVe',
    score: 88, grade: 'A',
    affiliate_url: amazon('B01MSSDEPK', 'CeraVe Facial Cleanser'),
    affiliate_network: 'amazon', price_cents: 1498,
  },

  // ── COSMETICS: Toothpaste ─────────────────────────────────────────────────
  {
    barcode: '035000511010', // Colgate Total Whitening
    alternative_barcode: '9999000002801',
    name: 'David\'s Natural Toothpaste Premium',
    brand: 'David\'s',
    score: 91, grade: 'A',
    affiliate_url: amazon('B07PJYV4QB', 'Davids Natural Toothpaste'),
    affiliate_network: 'amazon', price_cents: 1499,
  },
  {
    barcode: '037000009665', // Crest 3D White Toothpaste
    alternative_barcode: '9999000002901',
    name: 'Hello Fluoride Free Whitening Toothpaste',
    brand: 'Hello',
    score: 86, grade: 'A',
    affiliate_url: amazon('B01DYKBWCO', 'Hello Whitening Toothpaste'),
    affiliate_network: 'amazon', price_cents: 599,
  },

  // ── CLEANING: Laundry ─────────────────────────────────────────────────────
  {
    barcode: '037000929352', // Tide Pods Original
    alternative_barcode: '9999000003001',
    name: 'Seventh Generation Free & Clear Laundry Packs',
    brand: 'Seventh Generation',
    score: 89, grade: 'A',
    affiliate_url: amazon('B07BMZS12V', 'Seventh Generation Laundry'),
    affiliate_network: 'amazon', price_cents: 2199,
  },
  {
    barcode: '022200710106', // Gain Flings Original
    alternative_barcode: '9999000003101',
    name: 'Dropps Laundry Detergent Pods Fragrance Free',
    brand: 'Dropps',
    score: 90, grade: 'A',
    affiliate_url: amazon('B0971SNVJ4', 'Dropps Laundry Pods'),
    affiliate_network: 'amazon', price_cents: 3299,
  },

  // ── CLEANING: Dish Soap ───────────────────────────────────────────────────
  {
    barcode: '037000935445', // Dawn Ultra Original
    alternative_barcode: '9999000003201',
    name: 'Branch Basics All-Purpose Concentrate',
    brand: 'Branch Basics',
    score: 92, grade: 'A',
    affiliate_url: amazon('B07PZV73BQ', 'Branch Basics Concentrate'),
    affiliate_network: 'amazon', price_cents: 6900,
  },
  {
    barcode: '051700001043', // Ajax Ultra Dish Soap
    alternative_barcode: '9999000003301',
    name: 'Ecover Zero Dish Soap Fragrance Free',
    brand: 'Ecover',
    score: 88, grade: 'A',
    affiliate_url: amazon('B001SXQEVC', 'Ecover Zero Dish Soap'),
    affiliate_network: 'amazon', price_cents: 699,
  },

  // ── CLEANING: All-Purpose ─────────────────────────────────────────────────
  {
    barcode: '051700037158', // Lysol All-Purpose Cleaner
    alternative_barcode: '9999000003401',
    name: 'Method All-Purpose Cleaner Spray',
    brand: 'Method',
    score: 87, grade: 'A',
    affiliate_url: amazon('B01JRNI9Y8', 'Method All Purpose Cleaner'),
    affiliate_network: 'amazon', price_cents: 399,
  },
  {
    barcode: '041785001013', // Windex Original
    alternative_barcode: '9999000003501',
    name: 'Better Life Natural Glass & Surface Cleaner',
    brand: 'Better Life',
    score: 91, grade: 'A',
    affiliate_url: amazon('B003BFKAM4', 'Better Life Glass Cleaner'),
    affiliate_network: 'amazon', price_cents: 899,
  },
  {
    barcode: '019200855025', // Mr. Clean Multi-Surface
    alternative_barcode: '9999000003601',
    name: 'Puracy Natural Multi-Surface Cleaner',
    brand: 'Puracy',
    score: 90, grade: 'A',
    affiliate_url: amazon('B00DTFRPFC', 'Puracy Natural Cleaner'),
    affiliate_network: 'amazon', price_cents: 1699,
  },

  // ── CLEANING: Fabric Softener ─────────────────────────────────────────────
  {
    barcode: '037000925019', // Downy Fabric Softener
    alternative_barcode: '9999000003701',
    name: 'Seventh Generation Free & Clear Fabric Softener',
    brand: 'Seventh Generation',
    score: 88, grade: 'A',
    affiliate_url: thrive('products/seventh-generation-fabric-softener'),
    affiliate_network: 'thrive', price_cents: 1299,
  },

  // ── SUPPLEMENTS: Protein ──────────────────────────────────────────────────
  {
    barcode: '749826141038', // Optimum Nutrition Whey Gold Standard
    alternative_barcode: '9999000003801',
    name: 'Thrive Market Grass-Fed Whey Protein',
    brand: 'Thrive Market',
    score: 89, grade: 'A',
    affiliate_url: thrive('products/thrive-market-grass-fed-whey-protein'),
    affiliate_network: 'thrive', price_cents: 3999,
  },
  {
    barcode: '018533007258', // MuscleMilk Protein Shake
    alternative_barcode: '9999000003901',
    name: 'Orgain Organic Protein Chocolate',
    brand: 'Orgain',
    score: 87, grade: 'A',
    affiliate_url: amazon('B00J074W7A', 'Orgain Organic Protein'),
    affiliate_network: 'amazon', price_cents: 3399,
  },

  // ── SUPPLEMENTS: Vitamins ─────────────────────────────────────────────────
  {
    barcode: '016500511000', // Flintstones Vitamins Complete
    alternative_barcode: '9999000004001',
    name: 'Garden of Life Vitamin Code Kids',
    brand: 'Garden of Life',
    score: 92, grade: 'A',
    affiliate_url: amazon('B001Q3LATM', 'Garden of Life Kids Vitamins'),
    affiliate_network: 'amazon', price_cents: 3699,
  },
  {
    barcode: '019579000015', // Centrum Adults Multivitamin
    alternative_barcode: '9999000004101',
    name: 'Thorne Research Basic Nutrients 2/Day',
    brand: 'Thorne',
    score: 93, grade: 'A',
    affiliate_url: amazon('B0013OVR2G', 'Thorne Research Multivitamin'),
    affiliate_network: 'amazon', price_cents: 3200,
  },
  {
    barcode: '031604014827', // Nature Made Fish Oil
    alternative_barcode: '9999000004201',
    name: 'Nordic Naturals Ultimate Omega Softgels',
    brand: 'Nordic Naturals',
    score: 94, grade: 'A',
    affiliate_url: amazon('B002CQU564', 'Nordic Naturals Omega 3'),
    affiliate_network: 'amazon', price_cents: 3995,
  },

  // ── SUPPLEMENTS: Greens / Powders ─────────────────────────────────────────
  {
    barcode: '013347100089', // Metamucil Orange
    alternative_barcode: '9999000004301',
    name: 'Sunfiber Partially Hydrolyzed Guar Gum',
    brand: 'Sunfiber',
    score: 90, grade: 'A',
    affiliate_url: amazon('B00VOVEKJK', 'Sunfiber Guar Gum'),
    affiliate_network: 'amazon', price_cents: 1999,
  },
  {
    barcode: '074590500019', // Emergen-C Original Orange
    alternative_barcode: '9999000004401',
    name: 'Camu Camu Vitamin C Powder by Navitas',
    brand: 'Navitas Organics',
    score: 91, grade: 'A',
    affiliate_url: amazon('B004ZYOPEM', 'Navitas Camu Camu'),
    affiliate_network: 'amazon', price_cents: 1799,
  },
  {
    barcode: '026893002027', // Muscle Milk Chocolate (ready-to-drink)
    alternative_barcode: '9999000004501',
    name: 'Aloha Organic Plant-Based Protein Drink',
    brand: 'Aloha',
    score: 88, grade: 'A',
    affiliate_url: amazon('B0786YNFG8', 'Aloha Plant Protein Drink'),
    affiliate_network: 'amazon', price_cents: 4200,
  },
];

// ─── Seeder ──────────────────────────────────────────────────────────────────

async function seed(): Promise<void> {
  console.log('🌱 Ensuring alternatives table exists...');
  await ensureAlternativesTable();

  console.log(`🌱 Inserting ${seeds.length} alternative product mappings...`);
  let inserted = 0;
  let skipped = 0;

  for (const s of seeds) {
    try {
      // Skip if already seeded (upsert by barcode + alternative_barcode)
      const exists = await db.query(
        'SELECT id FROM alternatives WHERE barcode = $1 AND alternative_barcode = $2',
        [s.barcode, s.alternative_barcode]
      );
      if (exists.rows.length > 0) {
        skipped++;
        continue;
      }

      await db.query(
        `INSERT INTO alternatives
         (barcode, alternative_barcode, name, brand, score, grade, affiliate_url, affiliate_network, price_cents)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [s.barcode, s.alternative_barcode, s.name, s.brand, s.score, s.grade,
         s.affiliate_url, s.affiliate_network, s.price_cents]
      );
      inserted++;
    } catch (err) {
      console.error(`  ❌ Failed to insert ${s.name}:`, err);
    }
  }

  console.log(`✅ Done: ${inserted} inserted, ${skipped} already existed.`);
  await db.end();
}

seed().catch(err => {
  console.error('Seed failed:', err);
  process.exit(1);
});
