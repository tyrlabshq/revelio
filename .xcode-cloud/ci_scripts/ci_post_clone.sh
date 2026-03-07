#!/bin/sh

# ci_post_clone.sh — Revelio Xcode Cloud Bootstrap
# Runs after Xcode Cloud clones the repo, before building.
# Reference: https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

set -e

echo "▶ [ci_post_clone] Starting Revelio bootstrap..."

# ─────────────────────────────────────────
# 1. Environment info
# ─────────────────────────────────────────
echo "CI_COMMIT:       $CI_COMMIT"
echo "CI_BRANCH:       $CI_BRANCH"
echo "CI_TAG:          $CI_TAG"
echo "CI_BUILD_NUMBER: $CI_BUILD_NUMBER"
echo "CI_WORKFLOW:     $CI_WORKFLOW"
echo "CI_XCODE_SCHEME: $CI_XCODE_SCHEME"
echo "CI_PRODUCT_PLATFORM: $CI_PRODUCT_PLATFORM"

# ─────────────────────────────────────────
# 2. Install Homebrew packages (if needed)
# ─────────────────────────────────────────
# Xcode Cloud agents have Homebrew available.
# Add any CLI tools your build needs here.

# Example: mint for Swift Package Manager tools
# brew install mint 2>/dev/null || true
# mint bootstrap

# ─────────────────────────────────────────
# 3. Inject secrets from Xcode Cloud env vars
#    (set these in App Store Connect → Xcode Cloud → Workflow → Environment Variables)
# ─────────────────────────────────────────

# These vars are set in App Store Connect as secrets — never hardcode values here.
# The app reads these at build time via xcconfig or at runtime via Info.plist injection.

# Export API base URL for build (injected into xcconfig)
if [ -n "$REVELIO_API_BASE_URL" ]; then
    echo "REVELIO_API_BASE_URL=$REVELIO_API_BASE_URL" >> ios/Revelio/Config.xcconfig
    echo "✅ Injected REVELIO_API_BASE_URL"
fi

# RevenueCat API key (injected into xcconfig for build-time embedding)
if [ -n "$REVENUECAT_API_KEY" ]; then
    echo "REVENUECAT_API_KEY=$REVENUECAT_API_KEY" >> ios/Revelio/Config.xcconfig
    echo "✅ Injected REVENUECAT_API_KEY"
fi

# ─────────────────────────────────────────
# 4. SPM package resolution (Xcode Cloud
#    resolves packages automatically, but
#    you can force it here if needed)
# ─────────────────────────────────────────

# echo "▶ Resolving Swift Package Manager dependencies..."
# xcodebuild -resolvePackageDependencies \
#   -scheme Revelio \
#   -project ios/Revelio.xcodeproj

# ─────────────────────────────────────────
# 5. Bump build number from CI_BUILD_NUMBER
#    (Xcode Cloud sets this automatically,
#    but you can also do it manually here)
# ─────────────────────────────────────────

if [ -n "$CI_BUILD_NUMBER" ]; then
    echo "▶ Setting CFBundleVersion to $CI_BUILD_NUMBER..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CI_BUILD_NUMBER" \
        ios/Revelio/Info.plist
    echo "✅ Build number set to $CI_BUILD_NUMBER"
fi

# ─────────────────────────────────────────
# Done
# ─────────────────────────────────────────
echo "✅ [ci_post_clone] Bootstrap complete."
