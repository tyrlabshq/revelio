# Dupe Finder Eval Set

Target metric: **recall@3 ≥ 70%** — for each source, at least one of the three
returned dupes must match a hand-labeled expected alternative.

Vitest is not yet installed in the backend. When it is, port the table below
to `test/dupes.test.ts` and iterate: `GET /products/:barcode/dupes?limit=3`,
assert at least one of the expected barcodes is present.

## Eval table (50 pairs, curated by category)

| # | Category   | Source product (D/F)             | Source barcode | Expected cleaner dupes (A/B) |
|---|------------|----------------------------------|----------------|------------------------------|
|  1 | food       | Coca-Cola Classic 12oz           | 049000006346   | Olipop Vintage Cola; Poppi Classic Cola; Zevia Cola |
|  2 | food       | Doritos Nacho Cheese             | 028400064057   | Siete Nacho Chips; Jackson's Honest Tortilla Chips |
|  3 | food       | Gatorade Thirst Quencher Orange  | 052000338836   | Nooma Organic Electrolyte; Liquid IV Sugar-Free |
|  4 | food       | Cheerios Honey Nut               | 016000275287   | Three Wishes Cinnamon; Magic Spoon Honey Nut |
|  5 | food       | Skippy Peanut Butter (sugar)     | 037600105729   | Once Again Natural; Santa Cruz Organic |
|  6 | food       | Oreo Original                    | 044000032029   | Simple Mills Sandwich Cookies; Partake Chocolate |
|  7 | food       | Kraft Mac & Cheese blue box      | 021000658831   | Annie's Organic Shells; Banza Chickpea Mac |
|  8 | food       | Lay's Classic Potato Chips       | 028400433303   | Jackson's Honest; Boulder Canyon Avocado |
|  9 | food       | Pringles Original                | 038000138416   | Hippeas Organic Chickpea Puffs; Bare Baked Crunchy |
| 10 | food       | Chef Boyardee Ravioli            | 064144281190   | Amy's Organic Cheese Ravioli; Evol Beef Ravioli |
| 11 | food       | Hostess Twinkies                 | 888109001001   | Simple Mills Vanilla Cupcakes; Emmy's Organics |
| 12 | food       | Red Bull 8.4oz                   | 9002490100084  | Runa Clean Energy; Mati Unsweetened |
| 13 | food       | Sunny D Orange                   | 052000000092   | Suja Organic Orange Juice; RW Knudsen Orange |
| 14 | food       | Cap'n Crunch                     | 030000065259   | Magic Spoon Cocoa; Three Wishes Cocoa |
| 15 | food       | Pop-Tarts Frosted Strawberry     | 038000318184   | Nature's Path Organic Toaster Pastries |
| 16 | food       | Hellmann's Mayonnaise            | 048001006348   | Primal Kitchen Avocado Oil Mayo; Chosen Foods Mayo |
| 17 | food       | Kraft Ranch Dressing             | 021000643011   | Primal Kitchen Ranch; Tessemae's Ranch |
| 18 | food       | Heinz Ketchup                    | 013000006101   | Primal Kitchen Organic Ketchup; True Made Foods |
| 19 | food       | Jif Peanut Butter                | 051500241271   | 365 Organic PB; Once Again Organic |
| 20 | food       | Nutella Hazelnut Spread          | 009800895250   | Nuttzo Power Fuel; Rx Nut Butter |
| 21 | food       | Starbucks Frappuccino Mocha      | 012000161551   | Laird Superfood Latte; RISE Brewing Cold Brew |
| 22 | food       | Yoplait Strawberry Yogurt        | 070470003207   | Siggi's Plain; Stonyfield Organic Plain |
| 23 | food       | Minute Maid Lemonade             | 025000004216   | Lemon Perfect; Health-Ade Lemonade Kombucha |
| 24 | food       | Ocean Spray Cranberry Cocktail   | 031200020017   | RW Knudsen Just Cranberry; Lakewood Organic |
| 25 | food       | Campbell's Tomato Soup           | 051000012517   | Amy's Organic Tomato Soup; Pacific Foods Creamy |
| 26 | food       | Goldfish Cheddar                 | 014100085409   | Annie's Organic Cheddar Bunnies; Simple Mills |
| 27 | food       | Ritz Crackers Original           | 044000005795   | Simple Mills Sea Salt; Mary's Gone Crackers |
| 28 | food       | Hershey's Milk Chocolate         | 034000002405   | Hu Kitchen Simple Dark; Alter Eco Organic |
| 29 | food       | Mountain Dew 12oz                | 012000001475   | Olipop Orange Squeeze; Poppi Orange |
| 30 | food       | SpaghettiOs                      | 051000013538   | Annie's Organic Bernie O's |
| 31 | cosmetics  | Dove Body Wash Deep Moisture     | 011111612396   | Dr. Bronner's Pure-Castile; Alaffia Body Wash |
| 32 | cosmetics  | Herbal Essences Shampoo          | 381519017780   | Acure Ultra-Hydrating; 100% Pure Glossy Locks |
| 33 | cosmetics  | Pantene Pro-V Shampoo            | 080878178476   | Rahua Classic Shampoo; Innersense Color Radiance |
| 34 | cosmetics  | Old Spice Deodorant              | 012044033364   | Native Coconut & Vanilla; Schmidt's Natural |
| 35 | cosmetics  | Axe Body Spray                   | 079400343506   | Every Man Jack Body Spray; Native Body Spray |
| 36 | cosmetics  | Suave Lotion                     | 079400300591   | Weleda Skin Food; Dr. Bronner's Lotion |
| 37 | cosmetics  | Aveeno Daily Moisturizer         | 381370038337   | Beauty Counter Countermatch; 100% Pure Moisturizer |
| 38 | cosmetics  | Banana Boat Sunscreen SPF 50     | 079656044522   | Badger Mineral SPF 30; ThinkSport SPF 50 |
| 39 | cosmetics  | Maybelline Great Lash Mascara    | 041554238853   | Ilia Limitless Lash; Tower 28 MakeWaves |
| 40 | cosmetics  | Neutrogena Oil-Free Face Wash    | 070501051382   | Youth To The People Superfood Cleanser |
| 41 | cleaning   | Tide Original Detergent          | 037000127864   | Molly's Suds; Branch Basics Laundry |
| 42 | cleaning   | Lysol Disinfectant Spray         | 019200025195   | Branch Basics All-Purpose; Force of Nature |
| 43 | cleaning   | Dawn Ultra Dish Soap             | 037000946694   | Blueland Dish Soap; Branch Basics Dish |
| 44 | cleaning   | Clorox Bleach                    | 044600321448   | Seventh Generation Disinfecting |
| 45 | cleaning   | Febreze Air Freshener            | 037000861485   | Aunt Fannie's Room Spray; Grow Fragrance |
| 46 | cleaning   | Windex Glass Cleaner             | 070501101605   | Branch Basics Glass; Blueland Glass |
| 47 | supplements| Centrum Silver Multi             | 305734090036   | Ritual Essential for Women; Garden of Life Vitamin Code |
| 48 | supplements| One A Day Men's Multi            | 016500579540   | Thorne Basic Nutrients; Pure Encapsulations |
| 49 | supplements| Emergen-C Vitamin C              | 076314300303   | Garden of Life MyKind Organics C; Pure Synergy Pure Radiance C |
| 50 | supplements| Flintstones Children's Multi     | 016500532231   | SmartyPants Kids Formula; Llama Naturals Chewable |

## Out-of-band checks (run manually against staging)

1. Source product with no embedding → server embeds inline within 2s, then returns dupes.
2. Source with no same-category neighbors → returns empty list with `dupes: []` (never 500).
3. All candidates carry a severity-3 flag → returns empty list.
4. Requesting dupes for a non-existent barcode → 404.
5. Unauthenticated request → 401.
