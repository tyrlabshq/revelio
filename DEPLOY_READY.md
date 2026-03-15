# Revelio Backend Deployment Guide

The fly.toml has been updated to correctly reference the backend Dockerfile with the proper build context.

## Pre-Deployment Checklist

- [ ] Docker build verified: `docker build -t revelio-test -f backend/Dockerfile .`
- [ ] fly.toml updated with correct paths

## Manual Deployment Steps

Ty must complete these steps to deploy:

### 1. Install Fly CLI
```bash
curl -L https://fly.io/install.sh | sh
```

### 2. Authenticate with Fly.io
```bash
fly auth login
```
> This will open a browser for authentication.

### 3. Deploy the App
```bash
cd ~/.openclaw/workspace/projects/revelio
fly deploy
```

## Post-Deployment DNS Configuration

After successful deployment, add this CNAME record in Cloudflare:

| Type | Name | Target |
|------|------|--------|
| CNAME | api | revelio-api.fly.dev |

This will make the API accessible at `https://api.revelio.app`

## Fly.toml Configuration

```toml
app = 'revelio-api'
primary_region = 'iad'

[build]
  dockerfile = "backend/Dockerfile"
  context = "."

[env]
  PORT = '8430'
  CORS_ORIGINS = 'https://revelio.app,https://www.revelio.app,capacitor://localhost,ionic://localhost'

[http_service]
  internal_port = 8430
  force_https = true
  auto_stop_machines = 'stop'
  auto_start_machines = true
  min_machines_running = 1
  processes = ['app']

[[vm]]
  memory = '512mb'
  cpu_kind = 'shared'
  cpus = 1

[mounts]
  source = "revelio_data"
  destination = "/data"
```

## Notes

- The backend depends on the `shared/` directory at project root for scoring logic
- Build context is the project root (`.`) to include both `backend/` and `shared/`
- PostgreSQL database needs to be created separately via `fly postgres create` and attached
