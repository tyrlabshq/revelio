# productLookup cache spec

Vitest is not yet wired into `backend/`. This spec documents the behavior
of `lookupProduct` so the cache layers have a contract reviewers and the
eventual test suite can hold us to. Convert to `.test.ts` once vitest +
supertest land in `backend/package.json` (mirror the pattern from
`backend/test/scoring.test.ts` when that file exists).

## Cache order (read path)

1. **In-process memory** (`memoryCache`, 5 min TTL, LRU at 500 entries).
2. **Redis** (`product:v1:<barcode>`, 7-day TTL) via `getRedis()`.
3. **Postgres** `products` table, 7-day `last_fetched` window.
4. **Upstream APIs** `OFF -> OBF -> OPF` with the OFF rate limiter.

Each miss populates every layer above it.

## Cases

- `lookupProduct("123")` with memory hit returns immediately and never
  touches Redis, Postgres, or the network.
- `lookupProduct("123")` with memory miss + Redis hit populates memory
  and returns. No Postgres query, no upstream fetch.
- `lookupProduct("123")` with memory + Redis miss but fresh Postgres row
  (< 7 days) populates Redis and memory.
- `lookupProduct("123")` with stale Postgres row (> 7 days) falls
  through to the upstream chain and upserts all caches on success.
- `lookupProduct("123", { bypassCache: true })` skips all three cache
  layers, always hits the upstream chain, and refreshes Postgres +
  Redis + memory on success.
- With `REDIS_URL` unset, `getRedis()` returns `null` and every
  `redisGet` / `redisSet` is a silent no-op — Postgres and upstreams
  remain the source of truth.
- Redis errors are logged but never thrown to the caller.

## Keys and TTL

- Key format: `product:v1:<barcode>` — the `v1` prefix lets us bump
  the version on a breaking `ProductData` shape change without
  flushing manually.
- Redis TTL: 7 days (matches the Postgres freshness window).
- Memory TTL: 5 minutes — short enough that a barcode picker spam
  does not pin stale data past a legitimate refresh.

## Non-goals

- Cache stampede protection (single-flight / request coalescing). If
  two concurrent requests miss on the same barcode they will both hit
  OFF. Acceptable for v1; revisit if OFF rate limiting bites.
- Negative caching (404 -> "not found"). Currently every 404 re-hits
  upstream on every call. Add when abuse shows up in logs.
