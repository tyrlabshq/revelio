# Revelio — Screenshot Specification

## Required Device Sizes

| Device | Resolution | Orientation |
|--------|-----------|-------------|
| iPhone 6.9" (iPhone 16 Pro Max) | 1320 × 2868 px | Portrait |
| iPhone 6.5" (iPhone 11 Pro Max / 12 Pro Max) | 1242 × 2688 px | Portrait |
| iPad Pro 13" | 2048 × 2732 px | Portrait (landscape optional) |

**Required:** At least iPhone 6.9" or 6.5" screenshots are mandatory for App Store submission. iPad is required if the app supports iPad.

---

## 10 Key Screens

### Screen 1 — Hero: Scan in Action
**UI State:** ScanView with live camera feed active, targeting a real product barcode (e.g., Doritos bag). Show the scan reticle overlaid on the barcode.
**Caption:** "Point. Scan. Know instantly."
**Goal:** Hook — this is the money shot. Shows the core action.

---

### Screen 2 — Scan Result Card (A-Grade Product)
**UI State:** ScanResultCard showing an A-rated product (e.g., organic apple juice). GradeBadge showing "A" / score 88. Brand name visible. Ingredient count shown.
**Caption:** "Instant grades backed by real science."
**Goal:** Show best-case outcome; demonstrates the core value prop.

---

### Screen 3 — Scan Result Card (F-Grade Product)
**UI State:** ScanResultCard showing an F-rated product (e.g., a chip brand with seed oils + artificial dyes). GradeBadge showing "F" / score 18. Red flag indicators visible.
**Caption:** "Know what to avoid — and why."
**Goal:** Creates urgency. Shows that Revelio catches bad stuff.

---

### Screen 4 — Product Detail: Ingredient Breakdown
**UI State:** ProductDetailView scrolled to show the ingredient list with flag chips (e.g., "High Fructose Corn Syrup ⚠️", "Red 40 🔴", "Sodium Benzoate ⚠️"). Science citation link visible on at least one flag.
**Caption:** "Every flag. Cited science. Plain English."
**Goal:** Differentiator — citations are the killer feature vs Yuka.

---

### Screen 5 — Personalized Scoring Toggle
**UI State:** ProductDetailView showing the "Personalized" vs "Base" score toggle. Score changes when toggled (e.g., base: 62, personalized: 41 for a seed-oil-heavy product with "avoid seed oils" priority set).
**Caption:** "Scores that adapt to your health goals."
**Goal:** Shows personalization — a key differentiator. Makes it feel tailored.

---

### Screen 6 — Allergen Alert
**UI State:** ProductDetailView or ScanResultCard showing a prominent allergen warning banner (e.g., "Contains: Gluten, Dairy, Soy" in red/orange). Allergen chips clearly visible.
**Caption:** "Never miss an allergen again."
**Goal:** Appeals to allergy/sensitivity audience. High emotional resonance.

---

### Screen 7 — Alternatives Finder
**UI State:** Alternatives section of ProductDetailView showing 2-3 alternative product cards with higher scores and "Buy on Amazon" / "Buy at Thrive Market" buttons. Side-by-side grade comparison visible.
**Caption:** "Instant upgrades. Cleaner choices."
**Goal:** Shows actionability — not just a scanner, but a solution.

---

### Screen 8 — Pantry View
**UI State:** PantryView showing a grid of scanned products with grade badges. Household health score visible at top (e.g., "Your Pantry Score: C+"). Multiple family member tabs visible.
**Caption:** "Your whole pantry. One health score."
**Goal:** Shows depth of the product. Pantry = retention driver.

---

### Screen 9 — Family Profiles
**UI State:** ProfileView or PantryView showing multiple family member tabs (e.g., "Mom", "Dad", "Emma"). Each with different priority settings shown below name.
**Caption:** "Personalized for every family member."
**Goal:** Appeals to parents. Shows the family use case.

---

### Screen 10 — Onboarding / Value Prop Slide
**UI State:** OnboardingView showing slide 1 or 2 with the barcode scanner icon and headline text. Clean, branded look. Theme colors prominent.
**Caption:** "Know what's really in it."
**Goal:** Brand moment. Use as last screenshot or promotional image.

---

## Caption Style Guide
- **Max 30 characters** per caption line (App Store shows ~2 lines)
- Use short punchy verbs: "Know", "Scan", "Find", "Never miss"
- Avoid technical jargon — speak to the outcome, not the feature
- Contrast with light text over dark background (Revelio uses dark theme)

## Production Notes
- **Background:** Revelio uses a dark theme (`Theme.background`). Screenshots will naturally be dark — this stands out in the App Store.
- **Devices to use for capture:** iPhone 16 Pro Max (6.9") as primary. Use Simulator for consistent UI state.
- **Font overlay:** Add captions as a text overlay in Figma/Sketch/Canva after capture — don't bake them into screenshots.
- **Simulator tip:** Use `xcrun simctl io booted screenshot screenshot.png` for clean captures.
- **Frame:** Consider using Apple device frames (via AppLaunchpad, Screenshots.pro, or Figma Apple UI Kit).

## Recommended Screenshot Order in App Store
1. Scan in Action (hero)
2. Scan Result — Good product
3. Scan Result — Bad product  
4. Ingredient Breakdown with citations
5. Allergen Alert
6. Personalized Scoring
7. Alternatives Finder
8. Pantry View
9. Family Profiles
10. Onboarding slide (brand moment)
