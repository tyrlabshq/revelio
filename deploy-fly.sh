#!/bin/bash
# Deploy Revelio backend to Fly.io
# Run this after: fly auth login

set -e

echo "🚀 Revelio Backend Deployment Script"
echo "====================================="

# Check if flyctl is installed
if ! command -v flyctl &> /dev/null; then
    echo "❌ flyctl not found. Installing..."
    curl -L https://fly.io/install.sh | sh
    export PATH="$HOME/.fly/bin:$PATH"
fi

# Check if logged in
if ! flyctl auth whoami &> /dev/null; then
    echo "❌ Not logged in to Fly.io. Please run: fly auth login"
    exit 1
fi

echo "✅ Logged in as: $(flyctl auth whoami)"

# Check if app exists
if ! flyctl apps list | grep -q "revelio-api"; then
    echo "📦 Creating app..."
    flyctl apps create revelio-api
else
    echo "✅ App exists"
fi

# Check if database exists
if ! flyctl postgres list | grep -q "revelio-db"; then
    echo "🗄️  Creating PostgreSQL database..."
    flyctl postgres create --name revelio-db --region iad --vm-size shared-cpu-1x
    
    echo "🔗 Attaching database to app..."
    flyctl postgres attach revelio-db --app revelio-api
else
    echo "✅ Database exists"
fi

# Set secrets
echo "🔐 Setting environment variables..."
flyctl secrets set JWT_SECRET="$(openssl rand -base64 32)" --app revelio-api

# Deploy
echo "🚀 Deploying..."
flyctl deploy --app revelio-api

# Check status
echo "✅ Deployment complete!"
echo ""
echo "App URL: https://revelio-api.fly.dev"
echo "Health check: https://revelio-api.fly.dev/health"
echo ""
echo "Next steps:"
echo "1. Add custom domain: fly certs add api.revelio.app"
echo "2. Configure DNS: CNAME api.revelio.app → revelio-api.fly.dev"
