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
# 3. Secrets / runtime configuration
# ─────────────────────────────────────────

# NOTE: ios/Revelio/Config.xcconfig is NOT referenced in project.pbxproj,
# so xcconfig injection has no effect on the build.
#
# The app resolves API_BASE_URL at runtime via:
#   ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
#
# Xcode Cloud injects environment variables (set in App Store Connect →
# Xcode Cloud → Workflow → Environment Variables) directly into the process
# environment, so no xcconfig wiring is needed — the fallback URL covers
# production and the env var overrides it when set (e.g. staging workflows).
#
# RevenueCat is not integrated; the app uses native StoreKit directly.
# No REVENUECAT_API_KEY injection is required.
echo "ℹ️  API_BASE_URL fallback: https://api.revelio.app (override via Xcode Cloud env var)"

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
