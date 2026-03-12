#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Revelio — App Store Screenshot Capture Script
# ─────────────────────────────────────────────────────────────────────────────
# Usage:
#   ./scripts/capture-screenshots.sh [--device 6.7|6.1|all] [--skip-build]
#
# Requirements:
#   - Xcode + Command Line Tools installed
#   - Revelio.xcodeproj builds cleanly
#   - Simulator runtimes for iPhone 17 Pro Max and iPhone 16e available
#
# App Store display requirements:
#   6.9" / 6.7" → iPhone 17 Pro Max  (required for new submissions)
#   6.1"        → iPhone 16e         (covers 6.5" and smaller requirements)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKSPACE="$PROJECT_DIR/ios"
SCHEME="Revelio"
BUNDLE_ID="com.revelio.app"
OUTPUT_BASE="$HOME/.openclaw/workspace/artifacts/revelio-screenshots"

# Simulator UDIDs (update if Xcode runtime changes)
DEVICE_67_NAME="iPhone 17 Pro Max"
DEVICE_67_UDID="DC34193E-9DEF-4A2F-8AFC-B8E060924492"
DEVICE_61_NAME="iPhone 16e"
DEVICE_61_UDID="09AFBB99-096C-4122-AE91-2781813FFA2F"

# Screenshot delay after navigation (seconds)
CAPTURE_DELAY=3

# ── Args ──────────────────────────────────────────────────────────────────────
TARGET_SIZE="all"
SKIP_BUILD=false
for arg in "$@"; do
  case $arg in
    --device) TARGET_SIZE="$2"; shift 2 ;;
    --device=*) TARGET_SIZE="${arg#*=}" ;;
    --skip-build) SKIP_BUILD=true ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "▶ $*"; }
ok()   { echo "✅ $*"; }
warn() { echo "⚠️  $*"; }
die()  { echo "❌ $*" >&2; exit 1; }

wait_for_boot() {
  local udid="$1"
  local max=60
  local count=0
  log "Waiting for simulator $udid to boot..."
  while [[ "$(xcrun simctl list devices | grep "$udid" | grep -c "Booted")" -eq 0 ]]; do
    sleep 2
    count=$((count + 2))
    [[ $count -ge $max ]] && die "Simulator did not boot in ${max}s"
  done
  ok "Simulator booted"
  sleep 3  # Extra settle time
}

build_app() {
  local udid="$1"
  local device_name="$2"
  log "Building Revelio for simulator: $device_name"

  # Regenerate xcodeproj from project.yml (ensures all source files are included)
  if command -v xcodegen &>/dev/null; then
    log "Running xcodegen generate..."
    (cd "$WORKSPACE" && xcodegen generate)
    ok "xcodegen done"
  else
    warn "xcodegen not found — using existing .xcodeproj (may be missing files)"
  fi

  xcodebuild \
    -project "$WORKSPACE/Revelio.xcodeproj" \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -destination "id=$udid" \
    -configuration Debug \
    build

  ok "Build succeeded"
}

install_app() {
  local udid="$1"
  local app_path
  # Look in Xcode's default DerivedData location for the simulator build
  app_path=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -name "Revelio.app" -type d \
    -path "*/Debug-iphonesimulator/*" \
    2>/dev/null | head -1)
  [[ -z "$app_path" ]] && die "Revelio.app not found in DerivedData. Did the build succeed?"
  log "Installing app: $app_path"
  xcrun simctl install "$udid" "$app_path"
  ok "App installed"
}

launch_app() {
  local udid="$1"
  log "Launching Revelio..."
  xcrun simctl launch "$udid" "$BUNDLE_ID"
  sleep 5  # Wait for app to fully launch
}

capture() {
  local udid="$1"
  local outdir="$2"
  local name="$3"
  local filepath="$outdir/${name}.png"
  log "Capturing: $name"
  xcrun simctl io "$udid" screenshot "$filepath"
  ok "Saved → $filepath"
}

# ── Screenshot Sequence ───────────────────────────────────────────────────────
# NOTE: Revelio uses tab-based navigation and deep-link-style state.
# The capture sequence below uses xcrun simctl openurl for URL-scheme deep links
# when available, falling back to timed waits.
#
# If the app doesn't have deep links configured, screenshots must be captured
# manually after navigating to each screen. See SCREENSHOT-SPEC.md for manual steps.

capture_sequence() {
  local udid="$1"
  local size_label="$2"  # "6.7" or "6.1"
  local outdir="$OUTPUT_BASE/$size_label"

  mkdir -p "$outdir"

  log "=== Starting capture sequence for $size_label\" ==="

  # Screenshot 1: Scan View (app launch screen)
  log "[1/6] Scan screen — app opens on this tab by default"
  sleep "$CAPTURE_DELAY"
  capture "$udid" "$outdir" "01-scan"

  # Screenshot 2: Product Detail
  # Requires a scan result in history. Navigate to History tab first, open top item.
  log "[2/6] Product Detail — open via History"
  # Attempt deep link if scheme is registered; graceful fallback
  xcrun simctl openurl "$udid" "revelio://product-detail" 2>/dev/null || true
  sleep "$CAPTURE_DELAY"
  capture "$udid" "$outdir" "02-product-detail"

  # Screenshot 3: Personalized Score (toggle on Product Detail)
  log "[3/6] Personalized Score — toggle on same screen"
  sleep "$CAPTURE_DELAY"
  capture "$udid" "$outdir" "03-personalized-score"

  # Screenshot 4: History & Trends
  log "[4/6] History & Trends"
  xcrun simctl openurl "$udid" "revelio://trends" 2>/dev/null || true
  sleep "$CAPTURE_DELAY"
  capture "$udid" "$outdir" "04-history-trends"

  # Screenshot 5: Pantry
  log "[5/6] Pantry"
  xcrun simctl openurl "$udid" "revelio://pantry" 2>/dev/null || true
  sleep "$CAPTURE_DELAY"
  capture "$udid" "$outdir" "05-pantry"

  # Screenshot 6: Alternatives
  log "[6/6] Alternatives"
  xcrun simctl openurl "$udid" "revelio://alternatives" 2>/dev/null || true
  sleep "$CAPTURE_DELAY"
  capture "$udid" "$outdir" "06-alternatives"

  ok "=== Captured 6 screenshots → $outdir ==="
  ls -lh "$outdir"
}

# ── Per-Device Flow ───────────────────────────────────────────────────────────
run_for_device() {
  local udid="$1"
  local name="$2"
  local size="$3"

  log "──────────────────────────────────────────────"
  log "Device: $name  ($size\")"
  log "UDID:   $udid"
  log "──────────────────────────────────────────────"

  # Boot if needed
  local state
  state=$(xcrun simctl list devices | grep "$udid" | grep -oE "(Booted|Shutdown|Booting)")
  if [[ "$state" == "Shutdown" ]]; then
    log "Booting simulator..."
    xcrun simctl boot "$udid"
    wait_for_boot "$udid"
  elif [[ "$state" == "Booted" ]]; then
    ok "Simulator already booted"
  fi

  # Open Simulator.app so we can see it
  open -a Simulator --args -CurrentDeviceUDID "$udid" 2>/dev/null || true
  sleep 2

  # Build + Install (skip with --skip-build)
  if [[ "$SKIP_BUILD" == false ]]; then
    build_app "$udid" "$name"
    install_app "$udid"
  else
    warn "Skipping build (--skip-build). App must already be installed."
  fi

  # Launch
  launch_app "$udid"

  # Capture
  capture_sequence "$udid" "$size"
}

# ── Main ──────────────────────────────────────────────────────────────────────
log "Revelio Screenshot Capture"
log "Output: $OUTPUT_BASE"
log ""

mkdir -p "$OUTPUT_BASE"

case "$TARGET_SIZE" in
  "6.7"|"6.9") run_for_device "$DEVICE_67_UDID" "$DEVICE_67_NAME" "6.7" ;;
  "6.1"|"6.5") run_for_device "$DEVICE_61_UDID" "$DEVICE_61_NAME" "6.1" ;;
  "all")
    run_for_device "$DEVICE_67_UDID" "$DEVICE_67_NAME" "6.7"
    run_for_device "$DEVICE_61_UDID" "$DEVICE_61_NAME" "6.1"
    ;;
  *) die "Unknown device size: $TARGET_SIZE. Use 6.7, 6.1, or all." ;;
esac

log ""
ok "All done. Screenshots saved to $OUTPUT_BASE"
echo ""
echo "Next steps:"
echo "  1. Review screenshots in Finder: open $OUTPUT_BASE"
echo "  2. Add marketing headline overlays (see SCREENSHOT-SPEC.md)"
echo "  3. Export as PNG at required App Store dimensions"
echo "  4. Upload via App Store Connect → App Screenshots"
