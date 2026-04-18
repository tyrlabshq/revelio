# Revelio — Claude Code instructions

## What this app is

Revelio is a Yuka competitor: a barcode scanner for food, cosmetics, cleaning products, and supplements that returns a personalized health score with cited scientific evidence. Stack: SwiftUI iOS + Kotlin/Compose Android + Node.js/Express + PostgreSQL + Redis. Differentiators vs Yuka: personalization, cited science, Dupe Finder, Smart Swap Cart, conversational AI, family profiles, viral video scorecards.

## Workflow rules

- **Develop on a feature branch** — the Claude Code on Web harness assigns one per session. Never push to a different branch without explicit permission.
- **Open a pull request into `main`** when a body of work is complete. Include a Summary and a Test plan (bulleted checklist).
- **Do not merge PRs to `main` without explicit user confirmation**, even if they pass CI. "Merge once tested" counts as explicit confirmation for the PR it refers to — no standing authorization beyond that.
- **Prefer stacking** new work on the open feature branch when the previous PR is still pending, so all related commits land in one review.

## Commit message style

Follow the existing history: `<scope>: <short imperative>` where scope is one of `security`, `feat`, `fix`, `ios`, `android`, `backend`, `db`, `devops`, `ci`, `docs`, `integration`, `scoring`, `chore`, `merge`. Body explains *why*, not *what*. Every commit message ends with the `https://claude.ai/code/session_...` trailing line that the harness provides — do not omit it.

## Build discipline

- **Backend:** run `cd backend && ./node_modules/.bin/tsc --noEmit` before committing any `backend/**` change. It must exit 0. Install new deps with `npm install` from `backend/`.
- **iOS:** you cannot run Xcode in this environment. After touching Swift files, visually `Read` each one to confirm balanced braces and plausible compilation. If you add new `.swift` files, register them in `ios/Revelio.xcodeproj/project.pbxproj` — four places per file (PBXBuildFile, PBXFileReference, the owning PBXGroup's children, the main target's PBXSourcesBuildPhase). Main target Sources UUID is `B4DF3DBE84A8B4858C8EC308`.
- **Android:** no SDK is available here; proofread imports and Gradle syntax. The Gradle wrapper is not committed — note this in PRs so CI/devs run `gradle wrapper --gradle-version 8.5` once.

## Security invariants

- **Every route that reads or mutates user-owned data MUST use `requireAuth`**, and `userId` MUST come from `req.user.userId`, never from the client. No `user_id` from query, body, params, or headers.
- **Never log PII**: phone, email, userId, tokens, OTP codes, authorization headers. Use the pino logger (`backend/src/logger.ts`) which redacts these by default.
- **All SQL must be parameterized** (`$1`, `$2`, …). No string concatenation into queries, ever.
- **Do not default secrets** in source. In production, fail fast if required env vars are missing; the startup guard in `backend/src/index.ts` is the pattern to follow.
- **iOS secrets go in Keychain**, never `UserDefaults`. Reuse `Services/KeychainStore.swift`.
- **Validate inputs with Zod** at route handlers. Schemas live in `backend/src/lib/zod-schemas.ts`.

## Architecture conventions

- **Product data** flows through `backend/src/services/productLookup.ts` — OFF → OBF → OPF fallback, 7-day Postgres cache. Never fetch OFF directly from route handlers.
- **Scoring** is a shared module at `shared/scoring.ts` that both the TypeScript backend (`services/scorer.ts`) and the iOS client import. The Kotlin port lives at `android/.../domain/scoring/Scoring.kt`. Keep all three in sync when changing the algorithm.
- **Personalization** (priorities, allergies, family members, kid-safe) is applied at score time via `personalizeScore` — never rebuild it per-route.
- **Migrations** are ordinal SQL files in `backend/migrations/NNN_name.sql`. Never edit a migration after it's been committed and applied anywhere; add a new one.
- **Jobs** (cron-like work) live in `backend/src/jobs/*.ts`, invoked from `jobs/scheduler.ts`. Prefer moving these to BullMQ when the list grows beyond 3.

## Testing expectations

- **Backend:** when adding endpoints that return user-owned data, include a Vitest + Supertest case asserting 401 without a JWT and 403 when the path/body userId mismatches the JWT. See `backend/test/` for existing patterns.
- **Scoring:** any change to `shared/scoring.ts` or `backend/src/services/scorer.ts` needs a fixture assertion against the golden-set (e.g., Nutella → grade E) in `backend/test/scoring.test.ts`.
- **UI:** when you can't run the emulator, describe the test in the PR body under "Test plan" as a human-runnable checklist.

## PR checklist (copy into every PR body)

```
## Summary
<what and why, 1–3 bullets>

## Test plan
- [ ] `tsc --noEmit` exits 0
- [ ] Migrations run clean on a fresh DB
- [ ] Relevant IDOR/401/403 tests pass
- [ ] iOS: new Swift files registered in Xcode project
- [ ] Android: Gradle sync (after `gradle wrapper`)
- [ ] Manual: <endpoint-specific smoke test>
```

## Anti-patterns to reject in review

- Route handlers that accept `user_id` from the client
- New `console.log` calls in backend code — use the logger
- `as any` in TypeScript without a one-line justification comment
- Speculative abstractions, feature flags for non-existent features, backwards-compat shims for code paths that were just added
- Comments describing *what* the code does when the identifier already says it
