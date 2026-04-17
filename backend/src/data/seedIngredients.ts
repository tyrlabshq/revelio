/**
 * seedIngredients.ts
 * Adds additional ingredient flags to the DB beyond those in migrations/001_initial.sql.
 * Idempotent — uses ON CONFLICT DO NOTHING on ingredient_name uniqueness.
 *
 * Run:  npx ts-node src/data/seedIngredients.ts
 *       (or: node -r ts-node/register src/data/seedIngredients.ts)
 */

import { db } from '../db';

interface SeedFlag {
  ingredient_name: string;
  severity: 0 | 1 | 2 | 3;
  category: string;
  reason: string;
  citation_title: string;
  citation_url: string;
  citation_year: number;
  priorities: string[];
}

const ADDITIONAL_FLAGS: SeedFlag[] = [
  // ─── SEED OILS ──────────────────────────────────────────────────────────────
  {
    ingredient_name: 'rice bran oil',
    severity: 2,
    category: 'SEED OIL',
    reason: 'High omega-6; heavily processed',
    citation_title: 'J Am Oil Chem Soc — Rice Bran Oil Composition',
    citation_url: 'https://doi.org/10.1007/s11746-005-1140-z',
    citation_year: 2005,
    priorities: ['seed_oils'],
  },
  {
    ingredient_name: 'grape seed oil',
    severity: 2,
    category: 'SEED OIL',
    reason: 'Very high linoleic acid content',
    citation_title: 'Food Chem — Grape Seed Oil Fatty Acid Profile',
    citation_url: 'https://doi.org/10.1016/j.foodchem.2009.08.028',
    citation_year: 2010,
    priorities: ['seed_oils'],
  },
  {
    ingredient_name: 'rapeseed oil',
    severity: 2,
    category: 'SEED OIL',
    reason: 'Erucic acid concerns; usually GMO',
    citation_title: 'EFSA — Erucic Acid in Food',
    citation_url: 'https://doi.org/10.2903/j.efsa.2016.4521',
    citation_year: 2016,
    priorities: ['seed_oils'],
  },

  // ─── FRAGRANCE ───────────────────────────────────────────────────────────────
  {
    ingredient_name: 'artificial flavor',
    severity: 1,
    category: 'FRAGRANCE',
    reason: 'Undisclosed chemical mixture',
    citation_title: 'FEMA GRAS List — Artificial Flavors',
    citation_url: 'https://www.femaflavor.org/flavor-ingredient-library',
    citation_year: 2020,
    priorities: ['fragrance_free', 'artificial_additives'],
  },

  // ─── SURFACTANTS ─────────────────────────────────────────────────────────────
  {
    ingredient_name: 'sodium laureth sulfate',
    severity: 1,
    category: 'SURFACTANT',
    reason: '1,4-dioxane byproduct concern',
    citation_title: 'Environ Sci Technol — 1,4-Dioxane in Products',
    citation_url: 'https://doi.org/10.1021/es300062f',
    citation_year: 2012,
    priorities: ['sulfate_free'],
  },
  {
    ingredient_name: 'diethanolamine (dea)',
    severity: 2,
    category: 'SURFACTANT',
    reason: 'Carcinogenic nitrosamines',
    citation_title: 'NTP TR-478 — Diethanolamine',
    citation_url: 'https://ntp.niehs.nih.gov/ntp/htdocs/lt_rpts/tr478.pdf',
    citation_year: 1999,
    priorities: ['artificial_additives', 'endocrine_disruptors'],
  },

  // ─── PRESERVATIVES ───────────────────────────────────────────────────────────
  {
    ingredient_name: 'propyl gallate',
    severity: 2,
    category: 'PRESERVATIVE',
    reason: 'Possible carcinogen; endocrine disruptor',
    citation_title: 'NTP Report — Propyl Gallate',
    citation_url: 'https://ntp.niehs.nih.gov',
    citation_year: 2020,
    priorities: ['artificial_additives', 'endocrine_disruptors'],
  },
  {
    ingredient_name: 'dmdm hydantoin',
    severity: 3,
    category: 'PRESERVATIVE',
    reason: 'Formaldehyde releaser; hair loss',
    citation_title: 'Contact Dermatitis — Formaldehyde Releasers',
    citation_url: 'https://doi.org/10.1111/cod.12419',
    citation_year: 2015,
    priorities: ['artificial_additives'],
  },
  {
    ingredient_name: 'quaternium-15',
    severity: 3,
    category: 'PRESERVATIVE',
    reason: 'Formaldehyde releaser; allergen',
    citation_title: 'Am J Contact Dermat — Quaternium-15',
    citation_url: 'https://doi.org/10.2310/6620.2005.00024',
    citation_year: 2005,
    priorities: ['artificial_additives'],
  },

  // ─── UV FILTERS ───────────────────────────────────────────────────────────────
  {
    ingredient_name: 'benzophenone',
    severity: 2,
    category: 'UV FILTER',
    reason: 'IARC possible carcinogen',
    citation_title: 'IARC Monographs — Benzophenone',
    citation_url: 'https://monographs.iarc.who.int',
    citation_year: 2019,
    priorities: ['endocrine_disruptors'],
  },
  {
    ingredient_name: 'homosalate',
    severity: 2,
    category: 'UV FILTER',
    reason: 'Endocrine disruptor; hormone mimicker',
    citation_title: 'Environ Sci Technol — Homosalate Endocrine Activity',
    citation_url: 'https://doi.org/10.1021/acs.est.1c04297',
    citation_year: 2021,
    priorities: ['endocrine_disruptors'],
  },

  // ─── SWEETENERS ──────────────────────────────────────────────────────────────
  {
    ingredient_name: 'saccharin',
    severity: 1,
    category: 'SWEETENER',
    reason: 'Bladder tumors in animal studies',
    citation_title: 'NCI Cancer Topics — Saccharin',
    citation_url: 'https://www.cancer.gov/about-cancer/causes-prevention/risk/diet/artificial-sweeteners-fact-sheet',
    citation_year: 2016,
    priorities: ['artificial_additives'],
  },
  {
    ingredient_name: 'acesulfame potassium',
    severity: 1,
    category: 'SWEETENER',
    reason: 'Genotoxicity concerns',
    citation_title: 'Food Chem Toxicol — Acesulfame-K Review',
    citation_url: 'https://doi.org/10.1016/j.fct.2020.111613',
    citation_year: 2020,
    priorities: ['artificial_additives'],
  },

  // ─── PROPELLANTS ─────────────────────────────────────────────────────────────
  {
    ingredient_name: 'nitrous oxide',
    severity: 1,
    category: 'PROPELLANT',
    reason: 'Environmental concern; dissociative',
    citation_title: 'Lancet — Nitrous Oxide Climate and Health',
    citation_url: 'https://doi.org/10.1016/S0140-6736(22)01595-5',
    citation_year: 2022,
    priorities: ['artificial_additives'],
  },

  // ─── DYES ─────────────────────────────────────────────────────────────────────
  {
    ingredient_name: 'coal tar',
    severity: 3,
    category: 'DYE',
    reason: 'IARC Group 1 carcinogen',
    citation_title: 'IARC Monographs Vol 92 — Coal Tar',
    citation_url: 'https://monographs.iarc.who.int/list-of-classifications',
    citation_year: 2010,
    priorities: ['artificial_additives'],
  },

  // ─── SKIN LIGHTENERS ──────────────────────────────────────────────────────────
  {
    ingredient_name: 'hydroquinone',
    severity: 3,
    category: 'SKIN LIGHTENER',
    reason: 'Ochronosis; FDA banned OTC',
    citation_title: 'FDA 21 CFR 310.545 — Hydroquinone Ban',
    citation_url: 'https://www.ecfr.gov/current/title-21/part-310/section-310.545',
    citation_year: 2020,
    priorities: ['artificial_additives'],
  },

  // ─── HAIR DYES ───────────────────────────────────────────────────────────────
  {
    ingredient_name: 'resorcinol',
    severity: 2,
    category: 'HAIR DYE',
    reason: 'Thyroid disruptor; skin sensitizer',
    citation_title: 'EFSA — Resorcinol Safety Assessment',
    citation_url: 'https://doi.org/10.2903/j.efsa.2012.2573',
    citation_year: 2012,
    priorities: ['endocrine_disruptors'],
  },
  {
    ingredient_name: 'p-phenylenediamine',
    severity: 2,
    category: 'HAIR DYE',
    reason: 'Contact dermatitis; carcinogenicity',
    citation_title: 'Contact Dermatitis — PPD Allergy Review',
    citation_url: 'https://doi.org/10.1111/j.1600-0536.2007.01042.x',
    citation_year: 2007,
    priorities: ['artificial_additives'],
  },

  // ─── CONTAMINANTS / BYPRODUCTS ───────────────────────────────────────────────
  {
    ingredient_name: 'ethylene oxide',
    severity: 3,
    category: 'SURFACTANT BYPRODUCT',
    reason: 'IARC Group 1 carcinogen',
    citation_title: 'IARC Monographs — Ethylene Oxide',
    citation_url: 'https://monographs.iarc.who.int/list-of-classifications',
    citation_year: 2012,
    priorities: ['artificial_additives'],
  },
  {
    ingredient_name: '1,4-dioxane',
    severity: 3,
    category: 'CONTAMINANT',
    reason: 'Probable carcinogen; kidney damage',
    citation_title: 'EPA IRIS — 1,4-Dioxane Assessment',
    citation_url: 'https://iris.epa.gov/ChemicalLanding/&substance_nmbr=326',
    citation_year: 2010,
    priorities: ['artificial_additives'],
  },

  // ─── COSMETICS DEPTH (EWG Skin Deep) ─────────────────────────────────────────
  // Track 3.5: curated from EWG Skin Deep + FDA/EU regulatory lists.
  // Every entry targets a beauty/personal-care SKU concern that Yuka's
  // cosmetics grader catches. Severity follows EWG's 1-10 hazard scale
  // compressed into Revelio's 0-3: EWG 1-2 → 1, 3-6 → 2, 7-10 → 3.

  // Parabens (beyond methyl/propyl/butyl already seeded)
  {
    ingredient_name: 'ethylparaben',
    severity: 2,
    category: 'PRESERVATIVE',
    reason: 'Estrogenic paraben; detected in breast tissue',
    citation_title: 'EWG Skin Deep — Ethylparaben',
    citation_url: 'https://www.ewg.org/skindeep/ingredients/702339-ethylparaben/',
    citation_year: 2022,
    priorities: ['paraben_free', 'endocrine_disruptors'],
  },
  {
    ingredient_name: 'isobutylparaben',
    severity: 3,
    category: 'PRESERVATIVE',
    reason: 'Banned in EU cosmetics 2015; endocrine disruptor',
    citation_title: 'EU Regulation 1004/2014 — Paraben Ban',
    citation_url: 'https://eur-lex.europa.eu/eli/reg/2014/1004/oj',
    citation_year: 2014,
    priorities: ['paraben_free', 'endocrine_disruptors'],
  },
  {
    ingredient_name: 'isopropylparaben',
    severity: 3,
    category: 'PRESERVATIVE',
    reason: 'Banned in EU cosmetics 2015; endocrine disruptor',
    citation_title: 'EU Regulation 1004/2014 — Paraben Ban',
    citation_url: 'https://eur-lex.europa.eu/eli/reg/2014/1004/oj',
    citation_year: 2014,
    priorities: ['paraben_free', 'endocrine_disruptors'],
  },

  // Phthalates (specific esters — beyond the generic "phthalates" entry)
  {
    ingredient_name: 'dibutyl phthalate',
    severity: 3,
    category: 'PLASTICIZER',
    reason: 'Reproductive toxin; banned in EU cosmetics',
    citation_title: 'EWG Skin Deep — Dibutyl Phthalate (DBP)',
    citation_url: 'https://www.ewg.org/skindeep/ingredients/702317-dibutyl-phthalate/',
    citation_year: 2022,
    priorities: ['endocrine_disruptors'],
  },
  {
    ingredient_name: 'diethyl phthalate',
    severity: 2,
    category: 'PLASTICIZER',
    reason: 'Solvent in fragrance; endocrine disruptor',
    citation_title: 'CDC NHANES — Phthalate Biomonitoring',
    citation_url: 'https://www.cdc.gov/biomonitoring/Phthalates_FactSheet.html',
    citation_year: 2022,
    priorities: ['endocrine_disruptors', 'fragrance_free'],
  },
  {
    ingredient_name: 'dehp',
    severity: 3,
    category: 'PLASTICIZER',
    reason: 'Di(2-ethylhexyl) phthalate — reproductive carcinogen',
    citation_title: 'IARC Monographs Vol 101 — DEHP',
    citation_url: 'https://monographs.iarc.who.int/list-of-classifications',
    citation_year: 2013,
    priorities: ['endocrine_disruptors'],
  },

  // Formaldehyde releasers (beyond dmdm hydantoin / quaternium-15)
  {
    ingredient_name: 'imidazolidinyl urea',
    severity: 2,
    category: 'PRESERVATIVE',
    reason: 'Formaldehyde releaser; contact allergen',
    citation_title: 'Contact Dermatitis — Formaldehyde Releasers',
    citation_url: 'https://doi.org/10.1111/cod.12419',
    citation_year: 2015,
    priorities: ['artificial_additives'],
  },
  {
    ingredient_name: 'diazolidinyl urea',
    severity: 2,
    category: 'PRESERVATIVE',
    reason: 'Formaldehyde releaser; contact allergen',
    citation_title: 'Contact Dermatitis — Formaldehyde Releasers',
    citation_url: 'https://doi.org/10.1111/cod.12419',
    citation_year: 2015,
    priorities: ['artificial_additives'],
  },
  {
    ingredient_name: 'bronopol',
    severity: 2,
    category: 'PRESERVATIVE',
    reason: '2-bromo-2-nitropropane-1,3-diol — formaldehyde releaser',
    citation_title: 'EWG Skin Deep — Bronopol',
    citation_url: 'https://www.ewg.org/skindeep/ingredients/700687-bronopol/',
    citation_year: 2022,
    priorities: ['artificial_additives'],
  },

  // Synthetic fragrance ingredients
  {
    ingredient_name: 'synthetic fragrance',
    severity: 2,
    category: 'FRAGRANCE',
    reason: 'Undisclosed mix of up to 3,000 chemicals; allergens',
    citation_title: 'EWG — Not So Sexy: The Hidden Chemicals in Perfume',
    citation_url: 'https://www.ewg.org/research/not-so-sexy',
    citation_year: 2010,
    priorities: ['fragrance_free', 'endocrine_disruptors'],
  },
  {
    ingredient_name: 'butylphenyl methylpropional',
    severity: 3,
    category: 'FRAGRANCE',
    reason: 'Lilial — banned in EU 2022 as reproductive toxin',
    citation_title: 'EU CLP Regulation — Lilial Reclassification',
    citation_url: 'https://echa.europa.eu/substance-information/-/substanceinfo/100.002.741',
    citation_year: 2022,
    priorities: ['fragrance_free', 'endocrine_disruptors'],
  },
  {
    ingredient_name: 'galaxolide',
    severity: 2,
    category: 'FRAGRANCE',
    reason: 'Synthetic musk; bioaccumulative',
    citation_title: 'Environ Sci Technol — Synthetic Musk Biomonitoring',
    citation_url: 'https://doi.org/10.1021/es070977g',
    citation_year: 2008,
    priorities: ['fragrance_free', 'endocrine_disruptors'],
  },

  // UV filters (beyond oxybenzone/octinoxate/benzophenone/homosalate)
  {
    ingredient_name: 'octocrylene',
    severity: 2,
    category: 'UV FILTER',
    reason: 'Degrades to benzophenone; endocrine activity',
    citation_title: 'Chem Res Toxicol — Octocrylene Degradation',
    citation_url: 'https://doi.org/10.1021/acs.chemrestox.0c00461',
    citation_year: 2021,
    priorities: ['endocrine_disruptors'],
  },
  {
    ingredient_name: 'avobenzone',
    severity: 1,
    category: 'UV FILTER',
    reason: 'Photo-unstable; degradation products of concern',
    citation_title: 'EWG Skin Deep — Avobenzone',
    citation_url: 'https://www.ewg.org/skindeep/ingredients/700612-avobenzone/',
    citation_year: 2022,
    priorities: ['endocrine_disruptors'],
  },

  // Coal tar dyes (explicit CI codes — OFF/OBF often uses these)
  {
    ingredient_name: 'p-aminophenol',
    severity: 2,
    category: 'DYE',
    reason: 'Coal tar hair dye; methemoglobinemia risk',
    citation_title: 'EWG Skin Deep — p-Aminophenol',
    citation_url: 'https://www.ewg.org/skindeep/ingredients/704081-p-aminophenol/',
    citation_year: 2022,
    priorities: ['artificial_additives'],
  },
  {
    ingredient_name: 'ci 15985',
    severity: 2,
    category: 'DYE',
    reason: 'FD&C Yellow 6 coal tar dye',
    citation_title: 'FDA Color Additive Status List',
    citation_url: 'https://www.fda.gov/industry/color-additive-inventories',
    citation_year: 2023,
    priorities: ['artificial_additives'],
  },

  // PFAS — found in waterproof cosmetics
  {
    ingredient_name: 'ptfe',
    severity: 2,
    category: 'PFAS',
    reason: 'Polytetrafluoroethylene — PFAS family; bioaccumulates',
    citation_title: 'Environ Sci Technol Lett — PFAS in Cosmetics',
    citation_url: 'https://doi.org/10.1021/acs.estlett.1c00240',
    citation_year: 2021,
    priorities: ['endocrine_disruptors'],
  },
  {
    ingredient_name: 'perfluorohexane',
    severity: 3,
    category: 'PFAS',
    reason: 'PFAS; persistent environmental pollutant',
    citation_title: 'EWG — PFAS in Personal Care Products',
    citation_url: 'https://www.ewg.org/research/pfas-cosmetics',
    citation_year: 2021,
    priorities: ['endocrine_disruptors'],
  },
  {
    ingredient_name: 'perfluorodecalin',
    severity: 2,
    category: 'PFAS',
    reason: 'PFAS used in cosmetic emulsions; persistent',
    citation_title: 'EWG Skin Deep — Perfluorodecalin',
    citation_url: 'https://www.ewg.org/skindeep/ingredients/704285-perfluorodecalin/',
    citation_year: 2022,
    priorities: ['endocrine_disruptors'],
  },

  // Siloxanes
  {
    ingredient_name: 'cyclopentasiloxane',
    severity: 2,
    category: 'SILICONE',
    reason: 'D5 siloxane — EU restricted 2020; bioaccumulative',
    citation_title: 'ECHA D5 Restriction',
    citation_url: 'https://echa.europa.eu/substances-restricted-under-reach',
    citation_year: 2020,
    priorities: ['endocrine_disruptors'],
  },
  {
    ingredient_name: 'cyclotetrasiloxane',
    severity: 2,
    category: 'SILICONE',
    reason: 'D4 siloxane — EU restricted; reproductive toxin',
    citation_title: 'ECHA D4 Restriction',
    citation_url: 'https://echa.europa.eu/substances-restricted-under-reach',
    citation_year: 2018,
    priorities: ['endocrine_disruptors'],
  },

  // Ethanolamines (beyond DEA already seeded)
  {
    ingredient_name: 'triethanolamine',
    severity: 2,
    category: 'SURFACTANT',
    reason: 'TEA — nitrosamine precursor',
    citation_title: 'EWG Skin Deep — Triethanolamine',
    citation_url: 'https://www.ewg.org/skindeep/ingredients/706681-triethanolamine/',
    citation_year: 2022,
    priorities: ['artificial_additives', 'endocrine_disruptors'],
  },
];

// ─── Seed helper ──────────────────────────────────────────────────────────────

async function insertFlag(flag: SeedFlag): Promise<void> {
  await db.query(
    `
    INSERT INTO ingredient_flags
      (ingredient_name, severity, category, reason,
       citation_title, citation_url, citation_year, priorities)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
    ON CONFLICT DO NOTHING
    `,
    [
      flag.ingredient_name,
      flag.severity,
      flag.category,
      flag.reason,
      flag.citation_title,
      flag.citation_url,
      flag.citation_year,
      flag.priorities,
    ]
  );
}

// ─── Main ─────────────────────────────────────────────────────────────────────

export async function main(): Promise<void> {
  console.log(`Seeding ${ADDITIONAL_FLAGS.length} additional ingredient flags…`);

  let inserted = 0;
  let skipped = 0;

  for (const flag of ADDITIONAL_FLAGS) {
    try {
      const before = await db.query(
        'SELECT id FROM ingredient_flags WHERE ingredient_name = $1',
        [flag.ingredient_name]
      );
      await insertFlag(flag);
      const after = await db.query(
        'SELECT id FROM ingredient_flags WHERE ingredient_name = $1',
        [flag.ingredient_name]
      );
      if (after.rowCount! > before.rowCount!) {
        console.log(`  ✅ Inserted: ${flag.ingredient_name}`);
        inserted++;
      } else {
        console.log(`  ⏭  Already exists: ${flag.ingredient_name}`);
        skipped++;
      }
    } catch (err) {
      console.error(`  ❌ Failed: ${flag.ingredient_name}`, err);
    }
  }

  console.log(`\nDone. Inserted: ${inserted}, Skipped: ${skipped}`);
  await db.end();
}

// Run if called directly
if (require.main === module) {
  main().catch(err => {
    console.error('Seed failed:', err);
    process.exit(1);
  });
}
