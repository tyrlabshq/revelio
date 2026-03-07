import Foundation

struct IngredientFlagDatabase {
    static func check(ingredient: String, category: ProductCategory) -> IngredientFlag? {
        let lower = ingredient.lowercased()
        
        // --- SEED OILS ---
        if lower.contains("canola oil") || lower.contains("rapeseed oil") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "SEED OIL", reason: "High in omega-6 fatty acids; oxidizes during high-heat processing, potentially forming harmful aldehydes.", citationTitle: "Dietary Fats and Cardiovascular Disease", citationUrl: "https://doi.org/10.1161/CIR.0000000000000510", citationYear: 2017, priorities: ["seed_oils"])
        }
        if lower.contains("soybean oil") || lower.contains("soy oil") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "SEED OIL", reason: "Highly processed; very high omega-6 content disrupts omega-3/6 balance.", citationTitle: "Soybean Oil: A Review", citationUrl: "https://pubmed.ncbi.nlm.nih.gov/21308440/", citationYear: 2011, priorities: ["seed_oils"])
        }
        if lower.contains("sunflower oil") || lower.contains("safflower oil") || lower.contains("corn oil") || lower.contains("cottonseed oil") || lower.contains("vegetable oil") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "SEED OIL", reason: "Polyunsaturated oils high in omega-6; prone to oxidation during processing.", citationTitle: "Industrial Seed Oils Review", citationUrl: "https://doi.org/10.1093/advances/nmx004", citationYear: 2018, priorities: ["seed_oils"])
        }
        
        // --- SUGARS & SWEETENERS ---
        if lower.contains("high fructose corn syrup") || lower.contains("corn syrup") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 3, category: "SWEETENER", reason: "Linked to obesity, insulin resistance, and non-alcoholic fatty liver disease at high consumption levels.", citationTitle: "Fructose and Metabolic Disease", citationUrl: "https://doi.org/10.1016/j.metabol.2017.11.017", citationYear: 2018, priorities: ["sugar"])
        }
        if lower.contains("aspartame") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "ARTIFICIAL SWEETENER", reason: "WHO classified as possibly carcinogenic (Group 2B) in 2023. Controversy ongoing.", citationTitle: "WHO IARC Monographs on Aspartame", citationUrl: "https://www.who.int/news/item/14-07-2023-aspartame-hazard-and-risk-assessment", citationYear: 2023, priorities: ["artificial_additives"])
        }
        if lower.contains("sucralose") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 1, category: "ARTIFICIAL SWEETENER", reason: "May alter gut microbiome; some studies show glucose intolerance in susceptible individuals.", citationTitle: "Sucralose and Gut Microbiome", citationUrl: "https://pubmed.ncbi.nlm.nih.gov/28394643/", citationYear: 2017, priorities: ["artificial_additives"])
        }
        if lower.contains("saccharin") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 1, category: "ARTIFICIAL SWEETENER", reason: "Oldest artificial sweetener; mixed evidence on gut microbiome disruption.", citationTitle: "Non-nutritive Sweeteners Review", citationUrl: "https://doi.org/10.1016/j.appet.2019.04.023", citationYear: 2019, priorities: ["artificial_additives"])
        }
        
        // --- PRESERVATIVES ---
        if lower.contains("sodium nitrate") || lower.contains("sodium nitrite") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 3, category: "PRESERVATIVE", reason: "Can form nitrosamines (carcinogenic compounds) during cooking at high heat.", citationTitle: "Nitrates, Nitrites and Cancer Risk", citationUrl: "https://www.cancer.org/cancer/risk-prevention/chemicals/nitrates-nitrites.html", citationYear: 2020, priorities: ["preservatives"])
        }
        if lower.contains("bha") || lower.contains("butylated hydroxyanisole") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "PRESERVATIVE", reason: "Listed as possibly carcinogenic (Group 2B) by IARC. Banned in Japan and parts of EU.", citationTitle: "IARC Monograph on BHA", citationUrl: "https://monographs.iarc.who.int/agents-classified-by-the-iarc/", citationYear: 2019, priorities: ["preservatives"])
        }
        if lower.contains("bht") || lower.contains("butylated hydroxytoluene") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "PRESERVATIVE", reason: "Endocrine disruption concerns; restricted in several countries.", citationTitle: "BHT Toxicology Review", citationUrl: "https://pubmed.ncbi.nlm.nih.gov/25225754/", citationYear: 2014, priorities: ["preservatives"])
        }
        if lower.contains("sodium benzoate") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "PRESERVATIVE", reason: "Reacts with vitamin C to form benzene, a known carcinogen.", citationTitle: "Benzene in Soft Drinks", citationUrl: "https://www.fda.gov/food/environmental-contaminants-food/benzene-soft-drinks", citationYear: 2022, priorities: ["preservatives"])
        }
        if lower.contains("potassium bromate") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 3, category: "PRESERVATIVE", reason: "Classified as possibly carcinogenic by IARC; banned in EU, UK, Canada. Still legal in US.", citationTitle: "Potassium Bromate and Cancer", citationUrl: "https://www.ewg.org/research/potassium-bromate", citationYear: 2021, priorities: ["preservatives"])
        }
        
        // --- ARTIFICIAL COLORS ---
        if lower.contains("red 40") || lower.contains("allura red") || lower.contains("fd&c red") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "ARTIFICIAL COLOR", reason: "Linked to hyperactivity in children; requires warning label in EU.", citationTitle: "Artificial Food Colors and ADHD", citationUrl: "https://doi.org/10.1001/jamapediatrics.2019.0803", citationYear: 2019, priorities: ["artificial_additives"])
        }
        if lower.contains("yellow 5") || lower.contains("tartrazine") || lower.contains("yellow 6") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "ARTIFICIAL COLOR", reason: "Azo dyes linked to hyperactivity in children; warning labels required in EU.", citationTitle: "EU EFSA Opinion on Azo Dyes", citationUrl: "https://www.efsa.europa.eu/en/efsajournal/pub/2714", citationYear: 2016, priorities: ["artificial_additives"])
        }
        if lower.contains("blue 1") || lower.contains("blue 2") || lower.contains("green 3") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 1, category: "ARTIFICIAL COLOR", reason: "Synthetic food dye; limited long-term safety data.", citationTitle: "FDA Color Additives", citationUrl: "https://www.fda.gov/food/food-additives-petitions/color-additives-questions-answers-consumers", citationYear: 2023, priorities: ["artificial_additives"])
        }
        if lower.contains("titanium dioxide") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "ARTIFICIAL COLOR", reason: "Banned in food in the EU since 2022 due to genotoxicity concerns.", citationTitle: "EFSA Titanium Dioxide Re-evaluation", citationUrl: "https://doi.org/10.2903/j.efsa.2021.6585", citationYear: 2021, priorities: ["artificial_additives"])
        }
        
        // --- EMULSIFIERS / ADDITIVES ---
        if lower.contains("carrageenan") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "ADDITIVE", reason: "May cause gut inflammation and microbiome disruption; avoided in infant formula.", citationTitle: "Carrageenan and GI Inflammation", citationUrl: "https://doi.org/10.1155/2017/6509507", citationYear: 2017, priorities: ["gut_health"])
        }
        if lower.contains("polysorbate 80") || lower.contains("polysorbate 60") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 1, category: "EMULSIFIER", reason: "Animal studies show gut microbiome disruption; more human research needed.", citationTitle: "Dietary Emulsifiers and Microbiota", citationUrl: "https://doi.org/10.1038/nature14232", citationYear: 2015, priorities: ["gut_health"])
        }
        if lower.contains("calcium disodium edta") || lower.contains("disodium edta") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 1, category: "PRESERVATIVE", reason: "Chelating agent that may deplete essential minerals; FDA approved but worth watching.", citationTitle: "FDA Food Additive Status", citationUrl: "https://www.fda.gov/food/food-additives-petitions/food-additive-status-list", citationYear: 2023, priorities: ["artificial_additives"])
        }
        if lower.contains("propylparaben") || lower.contains("butylparaben") || lower.contains("methylparaben") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "PARABEN", reason: "Endocrine disruptors; can mimic estrogen. EU restricts concentrations.", citationTitle: "Parabens and Endocrine Disruption", citationUrl: "https://doi.org/10.1016/j.reprotox.2019.05.005", citationYear: 2019, priorities: ["parabens", "endocrine"])
        }
        if lower.contains("propylene glycol") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 1, category: "ADDITIVE", reason: "Generally recognized as safe, but large amounts may affect kidney function.", citationTitle: "FDA Propylene Glycol GRAS", citationUrl: "https://www.fda.gov/food/food-additives-petitions/gras-substances-scogs-database", citationYear: 2020, priorities: ["artificial_additives"])
        }
        if lower.contains("monosodium glutamate") || lower == "msg" {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 1, category: "FLAVOR ENHANCER", reason: "Controversial; FDA considers safe but some individuals report sensitivity symptoms.", citationTitle: "MSG Safety Review", citationUrl: "https://www.fda.gov/food/food-additives-petitions/questions-and-answers-monosodium-glutamate-msg", citationYear: 2022, priorities: [])
        }
        
        // --- TRANS FATS ---
        if lower.contains("partially hydrogenated") {
            return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 3, category: "TRANS FAT", reason: "Artificial trans fats increase LDL, decrease HDL, and strongly linked to heart disease. FDA banned in 2018 — shouldn't be here.", citationTitle: "FDA Trans Fat Final Rule", citationUrl: "https://www.fda.gov/food/food-additives-petitions/final-determination-regarding-partially-hydrogenated-oils", citationYear: 2018, priorities: ["heart_health"])
        }
        
        // --- COSMETIC SPECIFIC ---
        if category == .cosmetics {
            if lower.contains("formaldehyde") || lower.contains("formalin") {
                return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 3, category: "CARCINOGEN", reason: "Known human carcinogen (IARC Group 1). Found in some hair-straightening products and preservative systems.", citationTitle: "IARC Formaldehyde Classification", citationUrl: "https://monographs.iarc.who.int/list-of-classifications/", citationYear: 2012, priorities: ["carcinogens"])
            }
            if lower.contains("oxybenzone") {
                return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 2, category: "ENDOCRINE DISRUPTOR", reason: "Absorbs through skin; endocrine disruption concerns. Hawaii banned it to protect coral reefs.", citationTitle: "Oxybenzone Absorption Study", citationUrl: "https://doi.org/10.1001/jama.2019.5586", citationYear: 2019, priorities: ["endocrine", "parabens"])
            }
            if lower.contains("phthalate") || lower.contains("diethyl phthalate") || lower.contains("dep") {
                return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 3, category: "ENDOCRINE DISRUPTOR", reason: "Strong endocrine disruptors; linked to reproductive toxicity. Banned in cosmetics in EU.", citationTitle: "Phthalates and Reproductive Health", citationUrl: "https://doi.org/10.1210/er.2007-0023", citationYear: 2008, priorities: ["endocrine"])
            }
            if lower.contains("toluene") {
                return IngredientFlag(id: UUID().uuidString, ingredient: ingredient, severity: 3, category: "TOXIN", reason: "Neurotoxic solvent; reproductive hazard. Found in some nail polishes.", citationTitle: "Toluene Toxicology", citationUrl: "https://www.atsdr.cdc.gov/toxprofiles/tp56.pdf", citationYear: 2017, priorities: ["carcinogens"])
            }
        }
        
        return nil
    }
}
