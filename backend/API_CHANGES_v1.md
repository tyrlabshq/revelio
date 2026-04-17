# Revelio API Changes — v1 Security Hardening

Scope: backend Track 1 changes that affect the iOS (and future Android) client contract. Read top-to-bottom before integrating.

## New endpoints

### `POST /auth/refresh`
Exchange a refresh token for a new `(token, refreshToken)` pair. Implements rotation — the submitted refresh token is revoked on use. Reuse of a revoked token revokes every outstanding token for the user (presumed theft).

Request:
```json
{ "refreshToken": "<base64url string>" }
```
Response `200`:
```json
{
  "ok": true,
  "token": "<access JWT, 15m TTL>",
  "refreshToken": "<new rotated refresh token>",
  "expiresIn": 900,
  "user": { "id": "...", "phone": "+1...", "tier": "free" }
}
```
Errors: `400` (missing/malformed), `401` (expired/revoked/unknown).

### `POST /auth/logout`
Authenticated. Revokes every refresh token for the caller and blacklists the current access JWT in Redis until its natural expiry. Returns `204`.

### `DELETE /auth/account`
Authenticated. Hard-deletes the caller's data: `scans`, `pantry_items`, `family_members`, `refresh_tokens`, `referral_attributions`, `referral_codes`, `user_profiles`. Wrapped in a single DB transaction. Also blacklists the access token. Returns `204`. **There is no recovery.** UI must confirm.

### `GET /auth/export`
Authenticated. Returns a downloadable JSON dump of every row owned by the caller (`application/json`, `Content-Disposition: attachment; filename="revelio-export-<userId>-<date>.json"`). Fields named `token_hash` are replaced with `"[redacted]"` — tokens themselves were never stored in plaintext.

Payload shape:
```json
{
  "exportedAt": "<ISO>",
  "profile": { ... },
  "familyMembers": [ ... ],
  "scans": [ ... ],
  "pantry": [ ... ],
  "referrals": { "attributions": [...], "codes": [...] },
  "refreshTokens": [ { "id": "...", "expires_at": "...", "revoked_at": null, "created_at": "...", "token_hash": "[redacted]" } ]
}
```

## Changed endpoints

### `POST /auth/verify-otp`
- Access token expiry shortened from **30d → 15m**.
- Response now additionally returns `refreshToken` and `expiresIn` (seconds).
- New response shape:
  ```json
  {
    "ok": true,
    "token": "<15m access JWT>",
    "refreshToken": "<base64url string>",
    "expiresIn": 900,
    "user": { "id": "...", "phone": "...", "tier": "free" }
  }
  ```
- **iOS action required:** store `refreshToken` in the Keychain alongside the access token. Call `POST /auth/refresh` ~60 seconds before `expiresIn` elapses (or on any 401 from a protected route, then retry).

### `POST /auth/request-otp`
- Now rate-limited: **5 requests/hour per IP**. Excess requests return `429` with a `Retry-After` header.
- Phone validation tightened via zod; returns `400` on malformed E.164.

### All authenticated routes
- JWTs now carry a `jti` claim. The server checks Redis `blacklist:jwt:<jti>` and rejects revoked tokens. Redis-down → fail-open (request allowed; access tokens still expire on their own within 15 min).

## Rate limits (global)

| Scope | Limit | Notes |
|---|---|---|
| All routes | 60 req/min per IP | `globalLimiter` in `middleware/rateLimit.ts` |
| `POST /auth/request-otp` | 5/hour per IP | `otpRequestLimiter` |
| Scan routes (exported, not yet wired) | 60/min per IP | `scanLimiter` — wire into `scan.ts` when that file is next edited |

Responses when throttled: HTTP `429`, body `{ "error": "Too many requests..." }`, standard `RateLimit-*` draft-7 headers.

## Environment variables (no NEW vars required)

Existing vars continue to be honored:
- `JWT_SECRET` — required; ≥32 chars in production.
- `REDIS_URL` — optional; enables distributed rate limiting and JWT revocation. Without it, rate limits are per-process and logout cannot blacklist access tokens (they still expire in 15m).
- `NODE_ENV` — `production` tightens startup guards.
- `OPENAI_API_KEY`, `REVENUECAT_WEBHOOK_SECRET` — required in production, existing guard.
- `LOG_LEVEL` — optional; defaults to `info` in prod, `debug` otherwise.
- `CORS_EXTRA_ORIGINS` — optional comma list.

## Logging

Server now uses pino. Every request is logged with PII redacted (phone, email, OTP, tokens, authorization headers, user IDs are replaced with `[REDACTED]`). Client-observable behaviour does not change.

## iOS integration checklist

- [ ] Store `refreshToken` in Keychain (same item group as access token).
- [ ] Add a refresh interceptor: on `401`, attempt `POST /auth/refresh`; on success retry once.
- [ ] Surface "Delete my account" and "Export my data" in `SettingsView` calling `DELETE /auth/account` and `GET /auth/export` respectively.
- [ ] Handle `429` with a user-visible cooldown message on OTP request screen.
