#!/bin/zsh
# Builds Facet, installs it on a simulator and launches it.
#   scripts/run-sim.sh [simulator name or UDID] [file below Documents to open]
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${1:-iPhone 18 Pro}"
if [[ "$SIM" =~ ^[0-9A-F-]{36}$ ]]; then DEST="id=$SIM"; else DEST="name=$SIM"; fi
xcodegen generate --quiet
xcodebuild -project Facet.xcodeproj -scheme Facet -destination "platform=iOS Simulator,$DEST" \
  -derivedDataPath .build/DerivedData build -quiet 2>&1 | grep -v appintentsmetadataprocessor || true
APP=.build/DerivedData/Build/Products/Debug-iphonesimulator/Facet.app
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
xcrun simctl install "$SIM" "$APP"
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
SIMCTL_CHILD_FACET_OPEN="${2:-}" xcrun simctl launch "$SIM" "$BUNDLE"
