-- Revelio — Discover tab seed data
-- Adds 30 realistic products across food, cosmetics, cleaning, supplements
-- Also seeds scan records so /products/trending returns results
--
-- Usage:
--   psql $DATABASE_URL -f scripts/seed-products.sql
--
-- Prerequisites:
--   Run all migrations first (001–005)

-- ─── Ensure products table has columns the routes expect ─────────────────────
-- The initial migration defines (barcode PK, name, brand, …) but routes query
-- for id, product_name, score, grade, scan_count, created_at.

ALTER TABLE products ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid();
ALTER TABLE products ADD COLUMN IF NOT EXISTS product_name TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS score INTEGER;
ALTER TABLE products ADD COLUMN IF NOT EXISTS grade CHAR(1);
ALTER TABLE products ADD COLUMN IF NOT EXISTS scan_count INTEGER DEFAULT 0;
ALTER TABLE products ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- Back-fill product_name from name where NULL
UPDATE products SET product_name = name WHERE product_name IS NULL AND name IS NOT NULL;

-- ─── FOOD — Hall of Shame (score < 30) ──────────────────────────────────────

INSERT INTO products (barcode, name, product_name, brand, category, score, grade, scan_count, image_url, ingredients, created_at)
VALUES
  ('028400064057', 'Flamin'' Hot Cheetos', 'Flamin'' Hot Cheetos', 'Frito-Lay', 'food', 12, 'F', 847,
   'https://picsum.photos/400/400?random=1',
   '["corn meal","vegetable oil (corn, canola, sunflower)","flamin'' hot seasoning","maltodextrin","salt","sugar","monosodium glutamate","yeast extract","citric acid","red 40","yellow 6"]'::jsonb,
   NOW() - INTERVAL '30 days'),

  ('049000006346', 'Mountain Dew', 'Mountain Dew', 'PepsiCo', 'food', 8, 'F', 612,
   'https://picsum.photos/400/400?random=2',
   '["carbonated water","high fructose corn syrup","concentrated orange juice","citric acid","natural flavor","sodium benzoate","caffeine","sodium citrate","gum arabic","yellow 5","bha"]'::jsonb,
   NOW() - INTERVAL '25 days'),

  ('044000032081', 'Pop-Tarts Frosted Strawberry', 'Pop-Tarts Frosted Strawberry', 'Kellogg''s', 'food', 15, 'F', 534,
   'https://picsum.photos/400/400?random=3',
   '["enriched flour","corn syrup","high fructose corn syrup","soybean oil","sugar","dextrose","palm oil","red 40","tbhq","sodium benzoate"]'::jsonb,
   NOW() - INTERVAL '20 days'),

  ('041196010558', 'Lunchables Turkey & Cheddar', 'Lunchables Turkey & Cheddar', 'Oscar Mayer', 'food', 18, 'F', 445,
   'https://picsum.photos/400/400?random=4',
   '["turkey breast","cheddar cheese","enriched flour crackers","water","modified cornstarch","sodium nitrite","sodium phosphate","bha","bht","caramel color"]'::jsonb,
   NOW() - INTERVAL '18 days'),

  ('041220960095', 'Cool Ranch Doritos', 'Cool Ranch Doritos', 'Frito-Lay', 'food', 22, 'F', 389,
   'https://picsum.photos/400/400?random=5',
   '["corn","vegetable oil (corn, canola, sunflower)","maltodextrin","salt","tomato powder","corn syrup solids","monosodium glutamate","sunflower oil","sugar","red 40","blue 1","yellow 5"]'::jsonb,
   NOW() - INTERVAL '15 days'),

  ('012000161155', 'Gatorade Fruit Punch', 'Gatorade Fruit Punch', 'PepsiCo', 'food', 25, 'F', 367,
   'https://picsum.photos/400/400?random=6',
   '["water","sugar","dextrose","citric acid","natural flavor","salt","sodium citrate","monopotassium phosphate","red 40"]'::jsonb,
   NOW() - INTERVAL '12 days'),

-- ─── FOOD — Hidden Gems (score > 85) ────────────────────────────────────────

  ('859006004019', 'RXBar Chocolate Sea Salt', 'RXBar Chocolate Sea Salt', 'RXBAR', 'food', 92, 'A', 298,
   'https://picsum.photos/400/400?random=7',
   '["egg whites","dates","cashews","almonds","chocolate","cocoa","sea salt"]'::jsonb,
   NOW() - INTERVAL '28 days'),

  ('853715003992', 'EPIC Venison Bar', 'EPIC Venison Bar', 'EPIC Provisions', 'food', 94, 'A', 187,
   'https://picsum.photos/400/400?random=8',
   '["venison","dried cranberries","sea salt","celery powder","black pepper","garlic powder"]'::jsonb,
   NOW() - INTERVAL '26 days'),

  ('850004207017', 'Hu Dark Chocolate 70%', 'Hu Dark Chocolate 70%', 'Hu Kitchen', 'food', 96, 'A', 245,
   'https://picsum.photos/400/400?random=9',
   '["organic cacao","organic coconut sugar","organic cocoa butter"]'::jsonb,
   NOW() - INTERVAL '22 days'),

  ('851710003664', 'Primal Kitchen Avocado Mayo', 'Primal Kitchen Avocado Mayo', 'Primal Kitchen', 'food', 90, 'A', 312,
   'https://picsum.photos/400/400?random=10',
   '["avocado oil","organic eggs","organic vinegar","sea salt","rosemary extract"]'::jsonb,
   NOW() - INTERVAL '19 days'),

  ('850025974011', 'Siete Grain-Free Tortilla Chips', 'Siete Grain-Free Tortilla Chips', 'Siete', 'food', 88, 'A', 201,
   'https://picsum.photos/400/400?random=11',
   '["cassava flour","avocado oil","coconut flour","ground chia seeds","sea salt"]'::jsonb,
   NOW() - INTERVAL '16 days'),

  ('810005411318', 'Chomps Original Beef Stick', 'Chomps Original Beef Stick', 'Chomps', 'food', 93, 'A', 176,
   'https://picsum.photos/400/400?random=12',
   '["grass-fed beef","water","sea salt","celery juice","black pepper","garlic powder","coriander","mustard seed"]'::jsonb,
   NOW() - INTERVAL '10 days'),

-- ─── FOOD — Mid-range (30–85) ────────────────────────────────────────────────

  ('038000138416', 'Cheerios Original', 'Cheerios Original', 'General Mills', 'food', 65, 'C', 523,
   'https://picsum.photos/400/400?random=13',
   '["whole grain oats","corn starch","sugar","salt","tripotassium phosphate","vitamin e"]'::jsonb,
   NOW() - INTERVAL '29 days'),

  ('041570054826', 'Ritz Crackers', 'Ritz Crackers', 'Nabisco', 'food', 35, 'D', 411,
   'https://picsum.photos/400/400?random=14',
   '["unbleached enriched flour","soybean oil","sugar","salt","high fructose corn syrup","baking soda","soy lecithin"]'::jsonb,
   NOW() - INTERVAL '24 days'),

  ('021131502850', 'Nature Valley Granola Bar', 'Nature Valley Granola Bar', 'General Mills', 'food', 45, 'C', 356,
   'https://picsum.photos/400/400?random=15',
   '["whole grain oats","sugar","canola oil","rice flour","honey","salt","soy lecithin","baking soda"]'::jsonb,
   NOW() - INTERVAL '14 days'),

-- ─── COSMETICS ───────────────────────────────────────────────────────────────

  ('3614272049529', 'CeraVe Moisturizing Cream', 'CeraVe Moisturizing Cream', 'CeraVe', 'cosmetics', 87, 'A', 278,
   'https://picsum.photos/400/400?random=16',
   '["purified water","glycerin","cetearyl alcohol","capric triglyceride","cetyl alcohol","ceramide np","ceramide ap","ceramide eop","hyaluronic acid","cholesterol","petrolatum"]'::jsonb,
   NOW() - INTERVAL '27 days'),

  ('5010724527474', 'Neutrogena Ultra Sheer SPF 70', 'Neutrogena Ultra Sheer SPF 70', 'Neutrogena', 'cosmetics', 28, 'F', 195,
   'https://picsum.photos/400/400?random=17',
   '["avobenzone","homosalate","octisalate","octocrylene","oxybenzone","water","alcohol denat","styrene","acrylates copolymer","fragrance","bht"]'::jsonb,
   NOW() - INTERVAL '23 days'),

  ('0854220005045', 'Native Deodorant Coconut Vanilla', 'Native Deodorant Coconut Vanilla', 'Native', 'cosmetics', 91, 'A', 165,
   'https://picsum.photos/400/400?random=18',
   '["caprylic triglyceride","tapioca starch","ozokerite","coconut oil","beeswax","sodium bicarbonate","magnesium hydroxide","coconut fragrance"]'::jsonb,
   NOW() - INTERVAL '21 days'),

  ('630382028724', 'Dove Beauty Bar', 'Dove Beauty Bar', 'Dove', 'cosmetics', 42, 'C', 234,
   'https://picsum.photos/400/400?random=19',
   '["sodium lauroyl isethionate","stearic acid","sodium lauryl sulfate","sodium stearate","lauric acid","sodium isethionate","water","fragrance","sodium chloride","tetrasodium edta","bht","titanium dioxide"]'::jsonb,
   NOW() - INTERVAL '17 days'),

  ('5011321680593', 'The Ordinary Niacinamide 10%', 'The Ordinary Niacinamide 10%', 'The Ordinary', 'cosmetics', 89, 'A', 302,
   'https://picsum.photos/400/400?random=20',
   '["aqua","niacinamide","pentylene glycol","zinc pca","dimethyl isosorbide","tamarindus indica seed gum","xanthan gum","isoceteth-20","ethoxydiglycol","phenoxyethanol","chlorphenesin"]'::jsonb,
   NOW() - INTERVAL '11 days'),

-- ─── CLEANING ────────────────────────────────────────────────────────────────

  ('757037514009', 'Branch Basics Concentrate', 'Branch Basics Concentrate', 'Branch Basics', 'cleaning', 95, 'A', 143,
   'https://picsum.photos/400/400?random=21',
   '["purified water","decyl glucoside","coco glucoside","sodium citrate","chamomile extract","aloe vera"]'::jsonb,
   NOW() - INTERVAL '26 days'),

  ('037000348856', 'Tide Original Detergent', 'Tide Original Detergent', 'Procter & Gamble', 'cleaning', 20, 'F', 387,
   'https://picsum.photos/400/400?random=22',
   '["water","sodium lauryl sulfate","alcohol ethoxylate","citric acid","sodium hydroxide","fragrance","sodium borate","ethanolamine","calcium formate","diquaternium","titanium dioxide","formaldehyde"]'::jsonb,
   NOW() - INTERVAL '22 days'),

  ('817256020010', 'Blueland Multi-Surface Tablet', 'Blueland Multi-Surface Tablet', 'Blueland', 'cleaning', 93, 'A', 112,
   'https://picsum.photos/400/400?random=23',
   '["sodium carbonate","sodium bicarbonate","citric acid","sodium sulfate","decyl glucoside","potassium oleate"]'::jsonb,
   NOW() - INTERVAL '13 days'),

  ('021130126163', 'Lysol Disinfecting Wipes', 'Lysol Disinfecting Wipes', 'Lysol', 'cleaning', 15, 'F', 290,
   'https://picsum.photos/400/400?random=24',
   '["alkyl dimethyl benzyl ammonium chloride","alkyl dimethyl ethylbenzyl ammonium chloride","water","isopropanol","fragrance","sodium lauryl sulfate","dye"]'::jsonb,
   NOW() - INTERVAL '9 days'),

-- ─── SUPPLEMENTS ─────────────────────────────────────────────────────────────

  ('733739004253', 'NOW Foods Magnesium Glycinate', 'NOW Foods Magnesium Glycinate', 'NOW Foods', 'supplements', 91, 'A', 198,
   'https://picsum.photos/400/400?random=25',
   '["magnesium bisglycinate","cellulose capsule","rice flour","magnesium stearate"]'::jsonb,
   NOW() - INTERVAL '25 days'),

  ('021078025504', 'Centrum Silver Adults 50+', 'Centrum Silver Adults 50+', 'Centrum', 'supplements', 29, 'F', 256,
   'https://picsum.photos/400/400?random=26',
   '["calcium carbonate","ascorbic acid","dl-alpha tocopheryl acetate","ferrous fumarate","titanium dioxide","soybean oil","corn starch","bha","red 40","yellow 6","blue 2"]'::jsonb,
   NOW() - INTERVAL '20 days'),

  ('653341130693', 'Athletic Greens AG1', 'Athletic Greens AG1', 'AG1', 'supplements', 86, 'A', 341,
   'https://picsum.photos/400/400?random=27',
   '["spirulina","wheatgrass","chlorella","ashwagandha","rhodiola","reishi mushroom","probiotics","digestive enzymes","vitamins","minerals","citric acid","stevia"]'::jsonb,
   NOW() - INTERVAL '8 days'),

  ('850032307017', 'Seed DS-01 Daily Synbiotic', 'Seed DS-01 Daily Synbiotic', 'Seed', 'supplements', 94, 'A', 189,
   'https://picsum.photos/400/400?random=28',
   '["lactobacillus rhamnosus","bifidobacterium longum","lactobacillus plantarum","bifidobacterium infantis","prebiotic fiber","hydroxypropyl methylcellulose capsule"]'::jsonb,
   NOW() - INTERVAL '6 days'),

  ('850002660012', 'Liquid IV Hydration Multiplier', 'Liquid IV Hydration Multiplier', 'Liquid IV', 'food', 48, 'C', 276,
   'https://picsum.photos/400/400?random=29',
   '["pure cane sugar","dextrose","citric acid","sodium citrate","dipotassium phosphate","silicon dioxide","natural flavors","stevia leaf extract","vitamins b3 b5 b6 b12 c"]'::jsonb,
   NOW() - INTERVAL '4 days'),

  ('711381020513', 'Garden of Life Vitamin Code Raw B-Complex', 'Garden of Life Vitamin Code Raw B-Complex', 'Garden of Life', 'supplements', 88, 'A', 154,
   'https://picsum.photos/400/400?random=30',
   '["raw b-complex blend","vegetable cellulose capsule","organic rice bran","saccharomyces cerevisiae","lactobacillus bulgaricus"]'::jsonb,
   NOW() - INTERVAL '2 days')

ON CONFLICT (barcode) DO UPDATE SET
  product_name = EXCLUDED.product_name,
  score = EXCLUDED.score,
  grade = EXCLUDED.grade,
  scan_count = EXCLUDED.scan_count,
  image_url = EXCLUDED.image_url,
  ingredients = EXCLUDED.ingredients;

-- ─── Seed scan records for trending ──────────────────────────────────────────
-- Generate fake scans across last 7 days so /products/trending has data

INSERT INTO scans (user_id, barcode, product_name, score, grade, category, image_url, brand, scanned_at)
SELECT
  gen_random_uuid(),
  p.barcode,
  p.product_name,
  p.score,
  p.grade,
  p.category,
  p.image_url,
  p.brand,
  NOW() - (random() * INTERVAL '7 days')
FROM products p
CROSS JOIN generate_series(1, (p.scan_count / 100 + 1))  -- proportional scans
WHERE p.scan_count IS NOT NULL AND p.scan_count > 0;

-- ─── Summary ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  product_count INTEGER;
  scan_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO product_count FROM products;
  SELECT COUNT(*) INTO scan_count FROM scans WHERE scanned_at >= NOW() - INTERVAL '7 days';
  RAISE NOTICE '✅ Seeded % products and % recent scans', product_count, scan_count;
END $$;
