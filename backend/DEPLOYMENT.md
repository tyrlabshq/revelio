# Revelio Backend Deployment Guide

## Current Status

| Component | Status | Notes |
|-----------|--------|-------|
| Domain (revelio.app) | ✅ Configured | Cloudflare nameservers active |
| DNS (api.revelio.app) | ❌ Missing | Needs CNAME or A record |
| SSL Certificate | ❌ Not configured | Will be handled by Cloudflare |
| Backend Hosting | ❌ Not deployed | Needs deployment target |
| PostgreSQL Database | ❌ Not configured | Needs provisioning |
| Cloudflare Tunnel | ❌ Not configured | Needs origin certificate |

## Deployment Options

### Option 1: Fly.io (Recommended)

**Pros:**
- Native PostgreSQL support
- Easy Docker deployments
- Automatic SSL
- Generous free tier
- Custom domain support

**Steps:**
1. Install flyctl: `curl -L https://fly.io/install.sh | sh`
2. Login: `fly auth login`
3. Create app: `fly apps create revelio-api`
4. Create PostgreSQL: `fly postgres create --name revelio-db`
5. Attach DB: `fly postgres attach revelio-db --app revelio-api`
6. Deploy: `fly deploy`
7. Add custom domain: `fly certs add api.revelio.app`

**DNS Record Required:**
```
Type: CNAME
Name: api
Target: revelio-api.fly.dev
```

### Option 2: Railway

**Steps:**
1. Install CLI: `npm install -g @railway/cli`
2. Login: `railway login`
3. Init: `railway init`
4. Add PostgreSQL: `railway add --database postgres`
5. Deploy: `railway up`
6. Add custom domain in Railway dashboard

### Option 3: Render

**Steps:**
1. Create `render.yaml` blueprint
2. Connect GitHub repo
3. Deploy via Render dashboard
4. Add custom domain

### Option 4: Cloudflare Tunnel (Local + Tunnel)

**Steps:**
1. Login to Cloudflare: `cloudflared login`
2. Create tunnel: `cloudflared tunnel create revelio-api`
3. Route DNS: `cloudflared tunnel route dns revelio-api api.revelio.app`
4. Configure tunnel in `~/.cloudflared/config.yml`
5. Start tunnel: `cloudflared tunnel run revelio-api`

**Config file (`~/.cloudflared/config.yml`):**
```yaml
tunnel: <TUNNEL_ID>
credentials-file: /Users/ty/.cloudflared/<TUNNEL_ID>.json

ingress:
  - hostname: api.revelio.app
    service: http://localhost:8430
  - service: http_status:404
```

## Environment Variables Required

```bash
PORT=8430
DATABASE_URL=postgresql://user:pass@host:5432/revelio
REDIS_URL=redis://host:6379
JWT_SECRET=<generate_strong_secret>
CORS_ORIGINS=https://revelio.app,https://www.revelio.app,capacitor://localhost
```

## Database Migrations

Migrations are in `migrations/` directory. Run order:
1. `001_initial.sql` - Core tables
2. `002_add_enumber_citations.sql` - E-number citations
3. `003_creator_referrals.sql` - Referral system
4. `004_personalization.sql` - User personalization
5. `005_scans_history.sql` - Scan history

## CORS Configuration

The backend now supports CORS for:
- `http://localhost:3000` (local development)
- `https://revelio.app` (production web)
- `https://www.revelio.app` (www subdomain)
- `capacitor://localhost` (iOS app)
- `ionic://localhost` (iOS app alternate)

Set `CORS_ORIGINS` env var to override.

## Health Check Endpoint

```
GET /health
Response: { "ok": true, "service": "revelio-api", "version": "1.0.0" }
```

## DNS Configuration Required

**Cloudflare DNS Record:**
```
Type: CNAME
Name: api
Target: <your-hosting-provider-domain>
Proxy Status: Enabled (orange cloud)
TTL: Auto
```

Or if using Cloudflare Tunnel:
```
Type: CNAME
Name: api
Target: <TUNNEL_ID>.cfargotunnel.com
Proxy Status: Enabled
TTL: Auto
```

## iOS App Configuration

Update the iOS app API base URL to:
```
https://api.revelio.app
```

Bundle ID: `com.revelio.app`

## Testing the Deployment

```bash
# Health check
curl https://api.revelio.app/health

# Test scan endpoint
curl https://api.revelio.app/scan/3017620422003
```

## Local Development

```bash
# Start PostgreSQL and Redis
docker-compose up -d

# Run migrations
# (Auto-run on startup via ensureAlternativesTable())

# Start dev server
npm run dev
```

## Production Checklist

- [ ] DNS record created for api.revelio.app
- [ ] SSL certificate active (Cloudflare or provider)
- [ ] Database provisioned and migrations run
- [ ] Environment variables configured
- [ ] CORS origins include iOS app
- [ ] Health endpoint responding
- [ ] Scan endpoint tested with real barcode
- [ ] Error monitoring (Sentry recommended)
- [ ] Logging configured
- [ ] Rate limiting enabled
- [ ] Backup strategy for database