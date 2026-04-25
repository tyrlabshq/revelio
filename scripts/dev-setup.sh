#!/usr/bin/env bash
# =============================================================================
# Revelio Dev Setup Script
# Installs deps, starts PostgreSQL, runs migrations, starts server
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="${PROJECT_ROOT}/backend"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}  → $1${NC}"; }
success() { echo -e "${GREEN}  ✓ $1${NC}"; }
warn()    { echo -e "${YELLOW}  ⚠ $1${NC}"; }
error()   { echo -e "${RED}  ✗ $1${NC}"; exit 1; }

echo -e "${YELLOW}═══ Revelio Backend Dev Setup ═══${NC}"
echo ""

# =============================================================================
# 1. Check prerequisites
# =============================================================================
info "Checking prerequisites..."

command -v node  >/dev/null 2>&1 || error "node not found — install Node.js 18+"
command -v npm   >/dev/null 2>&1 || error "npm not found"
command -v psql  >/dev/null 2>&1 || warn "psql not found — you'll need PostgreSQL for full functionality"

NODE_VER=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
if [[ "$NODE_VER" -lt 18 ]]; then
  error "Node.js 18+ required (found v${NODE_VER})"
fi
success "Node.js $(node --version)"

# =============================================================================
# 2. Install dependencies
# =============================================================================
info "Installing backend dependencies..."
cd "${BACKEND_DIR}"
npm install --silent
success "Dependencies installed"

# =============================================================================
# 3. Set up environment file
# =============================================================================
ENV_FILE="${BACKEND_DIR}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  info "Creating .env from template..."
  cat > "$ENV_FILE" << 'EOF'
# ─── Required ────────────────────────────────────────────────────────────────
NODE_ENV=development
PORT=8430

# PostgreSQL — local default. Fly.io will inject DATABASE_URL automatically.
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/revelio_dev

# JWT — change this! Must be set in production.
JWT_SECRET=dev-secret-change-in-prod

# ─── Optional (leave blank to use dev/mock mode) ──────────────────────────────

# Twilio (OTP SMS). Without this, any 6-digit code works in dev.
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_VERIFY_SID=

# RevenueCat webhook signature verification secret.
# Without this, webhook endpoint accepts all POSTs in dev.
REVENUECAT_WEBHOOK_SECRET=

# OpenAI API key — required for /ingredients/:name/explain AI feature.
OPENAI_API_KEY=

# CORS origins (comma-separated)
CORS_ORIGINS=http://localhost:3000,https://revelio.app,https://www.revelio.app
EOF
  success ".env created at ${ENV_FILE}"
  warn "Review .env — add OPENAI_API_KEY if you want AI ingredient explains"
else
  success ".env already exists — skipping"
fi

# =============================================================================
# 4. Start PostgreSQL (macOS Homebrew or Docker)
# =============================================================================
info "Checking PostgreSQL..."

PG_RUNNING=false

# Try brew services first
if command -v brew >/dev/null 2>&1; then
  PG_STATUS=$(brew services list 2>/dev/null | grep postgresql | awk '{print $2}' || echo "")
  if [[ "$PG_STATUS" == "started" ]]; then
    PG_RUNNING=true
    success "PostgreSQL running (Homebrew)"
  elif [[ -n "$PG_STATUS" ]]; then
    info "Starting PostgreSQL via Homebrew..."
    brew services start postgresql@14 2>/dev/null || brew services start postgresql 2>/dev/null || true
    sleep 2
    PG_RUNNING=true
    success "PostgreSQL started"
  fi
fi

# Try system postgres
if ! $PG_RUNNING; then
  if pg_isready -q 2>/dev/null; then
    PG_RUNNING=true
    success "PostgreSQL already running"
  fi
fi

# Try Docker Compose
if ! $PG_RUNNING; then
  if [[ -f "${PROJECT_ROOT}/docker-compose.yml" ]]; then
    info "Starting PostgreSQL via Docker Compose..."
    cd "${PROJECT_ROOT}"
    docker compose up -d postgres 2>/dev/null || docker-compose up -d postgres 2>/dev/null || true
    sleep 3
    PG_RUNNING=true
    success "PostgreSQL started via Docker"
    cd "${BACKEND_DIR}"
  fi
fi

if ! $PG_RUNNING; then
  warn "Could not start PostgreSQL automatically."
  warn "Start it manually, then re-run this script."
  warn "Quick option: docker run -d --name revelio-pg -e POSTGRES_DB=revelio_dev -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:15"
fi

# =============================================================================
# 5. Create database if it doesn't exist
# =============================================================================
if $PG_RUNNING; then
  info "Ensuring database 'revelio_dev' exists..."
  # Source DATABASE_URL from .env
  DB_URL=$(grep "^DATABASE_URL=" "$ENV_FILE" | cut -d= -f2-)
  DB_NAME=$(echo "$DB_URL" | sed 's/.*\///')

  # Try createdb, ignore error if already exists
  createdb "$DB_NAME" 2>/dev/null && success "Database '${DB_NAME}' created" || success "Database '${DB_NAME}' already exists"
fi

# =============================================================================
# 6. Run schema migrations
# The app auto-creates tables on startup via ensureAlternativesTable() and
# the per-route ensureTables() calls. But we can also run the base schema here.
# =============================================================================
if $PG_RUNNING; then
  info "Running schema bootstrap..."

  # Source env vars
  export $(grep -v '^#' "$ENV_FILE" | xargs 2>/dev/null)

  # Run inline migrations (these match what the app auto-creates)
  psql "${DATABASE_URL}" << 'SQL' 2>/dev/null || warn "Some migrations may have failed (table may already exist)"

CREATE TABLE IF NOT EXISTS user_profiles (
  id UUID PRIMARY KEY,
  phone VARCHAR(20) UNIQUE NOT NULL,
  tier VARCHAR(20) DEFAULT 'free',
  priorities TEXT[] DEFAULT '{}',
  allergies TEXT[] DEFAULT '{}',
  goals TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS scan_usage (
  user_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  count INTEGER DEFAULT 0,
  PRIMARY KEY (user_id, date)
);

CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  barcode VARCHAR UNIQUE NOT NULL,
  name VARCHAR,
  brand VARCHAR,
  category VARCHAR DEFAULT 'food',
  image_url TEXT,
  ingredients JSONB DEFAULT '[]',
  off_data JSONB,
  score INTEGER,
  grade VARCHAR,
  scan_count INTEGER DEFAULT 0,
  last_fetched TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);

CREATE TABLE IF NOT EXISTS scans (
  id SERIAL PRIMARY KEY,
  user_id UUID,
  barcode VARCHAR NOT NULL,
  product_name VARCHAR,
  brand VARCHAR,
  category VARCHAR DEFAULT 'food',
  image_url TEXT,
  score INTEGER,
  grade VARCHAR,
  flags JSONB DEFAULT '[]',
  scanned_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_scans_user_id ON scans(user_id);
CREATE INDEX IF NOT EXISTS idx_scans_barcode ON scans(barcode);

CREATE TABLE IF NOT EXISTS pantry_items (
  id SERIAL PRIMARY KEY,
  user_id VARCHAR NOT NULL,
  barcode VARCHAR NOT NULL,
  product_name VARCHAR,
  brand VARCHAR,
  score INTEGER DEFAULT 0,
  grade VARCHAR DEFAULT 'C',
  image_url TEXT,
  category VARCHAR DEFAULT 'food',
  added_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, barcode)
);
CREATE INDEX IF NOT EXISTS idx_pantry_user ON pantry_items(user_id);

CREATE TABLE IF NOT EXISTS family_members (
  id SERIAL PRIMARY KEY,
  owner_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  name VARCHAR NOT NULL,
  is_child BOOLEAN DEFAULT FALSE,
  goals TEXT[] DEFAULT '{}',
  allergies TEXT[] DEFAULT '{}',
  avatar_color VARCHAR DEFAULT '#00B87C',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS alternatives (
  id SERIAL PRIMARY KEY,
  barcode VARCHAR NOT NULL,
  alternative_barcode VARCHAR NOT NULL,
  name VARCHAR,
  brand VARCHAR,
  score INTEGER DEFAULT 85,
  grade VARCHAR DEFAULT 'A',
  image_url TEXT,
  affiliate_url TEXT,
  affiliate_network TEXT,
  price_cents INTEGER,
  verified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_alternatives_barcode ON alternatives(barcode);

CREATE TABLE IF NOT EXISTS referral_codes (
  code VARCHAR PRIMARY KEY,
  user_id UUID REFERENCES user_profiles(id),
  status VARCHAR DEFAULT 'pending',
  follower_count INTEGER,
  platform VARCHAR,
  social_handle VARCHAR,
  total_earnings_cents INTEGER DEFAULT 0,
  pending_payout_cents INTEGER DEFAULT 0,
  applied_at TIMESTAMPTZ DEFAULT NOW(),
  approved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS referral_attributions (
  id SERIAL PRIMARY KEY,
  referral_code VARCHAR REFERENCES referral_codes(code),
  referred_user_id UUID REFERENCES user_profiles(id),
  attributed_at TIMESTAMPTZ DEFAULT NOW(),
  lifetime_revenue_cents INTEGER DEFAULT 0,
  is_active_subscriber BOOLEAN DEFAULT FALSE,
  UNIQUE(referred_user_id)
);

CREATE TABLE IF NOT EXISTS referral_earnings_log (
  id SERIAL PRIMARY KEY,
  referral_code VARCHAR REFERENCES referral_codes(code),
  referred_user_id UUID,
  event_type VARCHAR,
  gross_cents INTEGER,
  commission_cents INTEGER,
  revenue_cat_event_id VARCHAR UNIQUE,
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);

SQL

  success "Schema bootstrap complete"
fi

# =============================================================================
# 7. Start the server
# =============================================================================
echo ""
echo -e "${YELLOW}═══ Starting Revelio API ═══${NC}"
info "Server will start on port 8430 (http://localhost:8430)"
info "Health check: curl http://localhost:8430/health"
info "Ctrl+C to stop"
echo ""

cd "${BACKEND_DIR}"
npm run dev
