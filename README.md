# 🔬 Revelio

**Know what's really in it.**

The Yuka killer — a barcode scanner for food, cosmetics, cleaning products, and supplements. Personalized scoring with cited science, not a black box. Built to bury Exposr.

## Why We Win
- 📦 **4 categories** — food, cosmetics, cleaning products, supplements (Exposr: food only)
- 🧪 **Cited science** — every flagged ingredient links to the actual study (Yuka/Exposr: just vibes)
- 🎯 **Personalized scoring** — re-weights based on your goals (cut seed oils, avoid gluten, keto, etc.)
- 🔄 **Alternative finder** — red score? Here are 3 cleaner options to buy right now (affiliate rev)
- 📱 **TikTok score cards** — shareable branded cards designed to go viral
- 🏠 **Pantry tracker** — scan your whole pantry, get a household health score
- 👨‍👩‍👧 **Family profiles** — separate settings per household member (kids, allergies)
- 💰 **Creator program** — influencers earn 20% recurring on referred subs

## Stack
- **App:** SwiftUI (iOS native)
- **Backend:** Node.js + Express + PostgreSQL
- **Barcode:** AVFoundation (native iOS camera)
- **Data:** Open Food Facts API + Open Beauty Facts API + custom ingredient DB
- **Scoring:** Custom weighted engine + OpenAI ingredient analysis
- **Subscriptions:** RevenueCat (Free / Pro $4.99/mo)
- **Affiliates:** Amazon Associates + Thrive Market

## Pricing (US-first, undercuts Exposr)
| Tier | Price | Limits |
|------|-------|--------|
| Free | $0 | 10 scans/day, food only |
| Pro | $4.99/mo or $34.99/yr | Unlimited, all categories, alternatives, pantry |

## Repo Structure
```
ios/Revelio/     SwiftUI Xcode project
backend/         Node.js API
shared/          Shared types + ingredient scoring logic
docs/            Architecture, ingredient DB schema
```
