CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS products (
  barcode VARCHAR PRIMARY KEY,
  name TEXT,
  brand TEXT,
  category TEXT DEFAULT 'food',
  image_url TEXT,
  ingredients JSONB DEFAULT '[]',
  off_data JSONB DEFAULT '{}',
  last_fetched TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ingredient_flags (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ingredient_name TEXT NOT NULL,
  severity INTEGER NOT NULL CHECK (severity BETWEEN 0 AND 3),
  category TEXT NOT NULL,
  reason TEXT NOT NULL,
  citation_title TEXT,
  citation_url TEXT,
  citation_year INTEGER,
  priorities TEXT[] DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS scans (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID,
  barcode VARCHAR,
  product_name TEXT,
  score INTEGER,
  grade CHAR(1),
  flags JSONB DEFAULT '[]',
  scanned_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS pantry_items (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL,
  barcode VARCHAR NOT NULL,
  product_name TEXT,
  score INTEGER,
  grade CHAR(1),
  quantity INTEGER DEFAULT 1,
  added_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_profiles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  phone TEXT UNIQUE,
  name TEXT,
  tier TEXT DEFAULT 'free',
  priorities TEXT[] DEFAULT '{}',
  allergies TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scans_user ON scans(user_id, scanned_at DESC);
CREATE INDEX IF NOT EXISTS idx_scans_barcode ON scans(barcode);

-- Seed ingredient flags
INSERT INTO ingredient_flags (ingredient_name, severity, category, reason, citation_title, citation_url, citation_year, priorities) VALUES
('canola oil', 2, 'SEED OIL', 'High in omega-6; oxidizes during processing', 'Dietary Fats and CVD Advisory', 'https://doi.org/10.1161/CIR.0000000000000510', 2017, ARRAY['seed_oils']),
('soybean oil', 2, 'SEED OIL', 'High omega-6, linked to inflammation', 'PLoS One soybean study', 'https://doi.org/10.1371/journal.pone.0132672', 2015, ARRAY['seed_oils']),
('corn oil', 2, 'SEED OIL', 'Very high omega-6; oxidizes easily', 'AHA Fats Advisory', 'https://doi.org/10.1161/CIR.0000000000000510', 2017, ARRAY['seed_oils']),
('sunflower oil', 2, 'SEED OIL', 'High linoleic acid; toxic aldehydes when heated', 'Food Chemistry aldehydes', 'https://doi.org/10.1016/j.foodchem.2014.09.148', 2014, ARRAY['seed_oils']),
('safflower oil', 2, 'SEED OIL', 'High omega-6; solvent extracted', 'AHA Fats Advisory', 'https://doi.org/10.1161/CIR.0000000000000510', 2017, ARRAY['seed_oils']),
('cottonseed oil', 3, 'SEED OIL', 'Contains gossypol toxin; highly processed', 'J Environ Sci Health', 'https://doi.org/10.1080/01480545.2010.536767', 2011, ARRAY['seed_oils']),
('vegetable oil', 2, 'SEED OIL', 'Usually soybean/canola blend; high omega-6', 'AHA Fats Advisory', 'https://doi.org/10.1161/CIR.0000000000000510', 2017, ARRAY['seed_oils']),
('red 40', 3, 'ARTIFICIAL DYE', 'Linked to hyperactivity; petroleum derived', 'Lancet food additives', 'https://doi.org/10.1016/S0140-6736(07)61306-3', 2007, ARRAY['artificial_additives']),
('yellow 5', 3, 'ARTIFICIAL DYE', 'Tartrazine; hyperactivity + allergies', 'Lancet food additives', 'https://doi.org/10.1016/S0140-6736(07)61306-3', 2007, ARRAY['artificial_additives']),
('yellow 6', 3, 'ARTIFICIAL DYE', 'Sunset Yellow; benzidine carcinogen', 'Lancet food additives', 'https://doi.org/10.1016/S0140-6736(07)61306-3', 2007, ARRAY['artificial_additives']),
('blue 1', 2, 'ARTIFICIAL DYE', 'Possible neurotoxicity concerns', 'Toxicol Ind Health', 'https://doi.org/10.1177/0960327111433474', 2012, ARRAY['artificial_additives']),
('blue 2', 2, 'ARTIFICIAL DYE', 'Brain tumors in rats at high doses', 'CSPI Rainbow of Risks', 'https://cspinet.org', 2010, ARRAY['artificial_additives']),
('caramel color', 2, 'ARTIFICIAL DYE', '4-MEI possible carcinogen', 'Toxicol Sci 4-MEI', 'https://doi.org/10.1093/toxsci/kfs306', 2012, ARRAY['artificial_additives']),
('bha', 3, 'PRESERVATIVE', 'Possible carcinogen; endocrine disruptor', 'NTP Report BHA', 'https://ntp.niehs.nih.gov', 2016, ARRAY['artificial_additives','endocrine_disruptors']),
('bht', 2, 'PRESERVATIVE', 'Possible carcinogen; tumor promotion', 'NTP Report BHT', 'https://ntp.niehs.nih.gov', 2016, ARRAY['artificial_additives']),
('tbhq', 2, 'PRESERVATIVE', 'Immune system disruption', 'AJLM TBHQ', 'https://doi.org/10.1177/1559827619872245', 2019, ARRAY['artificial_additives']),
('sodium benzoate', 2, 'PRESERVATIVE', 'Forms benzene with vitamin C', 'FDA Benzene Study', 'https://www.fda.gov/food', 2006, ARRAY['artificial_additives']),
('potassium benzoate', 2, 'PRESERVATIVE', 'Benzene formation risk', 'Food Chemistry benzene', 'https://doi.org/10.1016/j.foodchem.2006.01.047', 2006, ARRAY['artificial_additives']),
('sodium nitrate', 2, 'PRESERVATIVE', 'Nitrosamines; colorectal cancer link', 'Int J Epidemiology', 'https://doi.org/10.1093/ije/dyq063', 2011, ARRAY['artificial_additives']),
('sodium nitrite', 2, 'PRESERVATIVE', 'Nitrosamines; IARC probable carcinogen', 'IARC Monographs', 'https://doi.org/10.1016/S1470-2045(15)00444-1', 2015, ARRAY['artificial_additives']),
('high fructose corn syrup', 2, 'SWEETENER', 'Metabolic syndrome, fatty liver', 'AJCN HFCS', 'https://doi.org/10.1093/ajcn/83.6.1356', 2006, ARRAY['artificial_additives']),
('aspartame', 2, 'SWEETENER', 'IARC possibly carcinogenic (2B)', 'WHO Aspartame', 'https://www.who.int/news/2023', 2023, ARRAY['artificial_additives']),
('sucralose', 1, 'SWEETENER', 'Gut microbiome effects; genotoxicity', 'Toxicol Sci sucralose', 'https://doi.org/10.1093/toxsci/kfad060', 2023, ARRAY['artificial_additives']),
('carrageenan', 1, 'THICKENER', 'GI inflammation concerns', 'Front Pediatr review', 'https://doi.org/10.3389/fped.2017.00096', 2017, ARRAY['artificial_additives']),
('titanium dioxide', 2, 'ADDITIVE', 'Banned EU 2022; possible carcinogen', 'EFSA TiO2 re-evaluation', 'https://doi.org/10.2903/j.efsa.2021.6585', 2021, ARRAY['artificial_additives']),
('methylparaben', 2, 'PRESERVATIVE', 'Estrogenic; breast tumor tissue', 'J Appl Toxicol', 'https://doi.org/10.1002/jat.946', 2004, ARRAY['paraben_free','endocrine_disruptors']),
('propylparaben', 2, 'PRESERVATIVE', 'Male reproductive hormone disruption', 'Reproductive Toxicology', 'https://doi.org/10.1016/j.reprotox.2010.09.013', 2010, ARRAY['paraben_free','endocrine_disruptors']),
('butylparaben', 3, 'PRESERVATIVE', 'Strongest estrogenic activity', 'Toxicol Appl Pharmacol', 'https://doi.org/10.1016/j.taap.2012.01.033', 2012, ARRAY['paraben_free','endocrine_disruptors']),
('triclosan', 3, 'ANTIMICROBIAL', 'Endocrine disruptor; antibiotic resistance', 'Int J Antimicrob Agents', 'https://doi.org/10.1016/j.ijantimicag.2010.05.041', 2010, ARRAY['endocrine_disruptors','fragrance_free']),
('oxybenzone', 3, 'UV FILTER', 'Breast milk detected; endocrine disruptor', 'Environ Health Perspect', 'https://doi.org/10.1289/ehp.9860', 2008, ARRAY['endocrine_disruptors']),
('octinoxate', 2, 'UV FILTER', 'Breast milk detected; estrogenic', 'J Toxicol Environ Health', 'https://doi.org/10.1080/15287394.2012.666627', 2012, ARRAY['endocrine_disruptors']),
('fragrance', 2, 'FRAGRANCE', 'Hides undisclosed chemicals; allergens', 'Contact Dermatitis', 'https://doi.org/10.1111/cod.13639', 2019, ARRAY['fragrance_free']),
('parfum', 2, 'FRAGRANCE', 'EU term for fragrance; same concerns', 'Contact Dermatitis', 'https://doi.org/10.1111/cod.13639', 2019, ARRAY['fragrance_free']),
('sodium lauryl sulfate', 2, 'SURFACTANT', 'Skin irritant; strips natural oils', 'Contact Dermatitis', 'https://doi.org/10.1111/cod.12950', 2018, ARRAY['sulfate_free']),
('sodium laureth sulfate', 1, 'SURFACTANT', '1,4-dioxane byproduct concern', 'Environ Sci Technol', 'https://doi.org/10.1021/es300062f', 2012, ARRAY['sulfate_free']),
('formaldehyde', 3, 'PRESERVATIVE', 'IARC Group 1 carcinogen', 'IARC Monographs', 'https://monographs.iarc.who.int', 2006, ARRAY['artificial_additives','endocrine_disruptors']),
('phthalates', 2, 'PLASTICIZER', 'Reproductive harm; early puberty', 'Environ Int', 'https://doi.org/10.1016/j.envint.2007.05.007', 2007, ARRAY['endocrine_disruptors']),
('lead', 3, 'HEAVY METAL', 'Neurotoxin; no safe exposure level', 'FDA hair dye ban', 'https://www.federalregister.gov', 2018, ARRAY['heavy_metals']),
('mercury', 3, 'HEAVY METAL', 'Neurotoxin in skin products', 'MMWR Mercury', 'https://doi.org/10.15585/mmwr.mm6945a2', 2020, ARRAY['heavy_metals']),
('polysorbate 80', 1, 'EMULSIFIER', 'Gut microbiome disruption', 'Nature emulsifiers', 'https://doi.org/10.1038/nature14232', 2015, ARRAY['artificial_additives']),
('monosodium glutamate', 1, 'FLAVOR ENHANCER', 'MSG sensitivity; headaches', 'J Allergy Clin Immunol', 'https://doi.org/10.1016/S0091-6749(97)70198-7', 1997, ARRAY['artificial_additives'])
ON CONFLICT DO NOTHING;
