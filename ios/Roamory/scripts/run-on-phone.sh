#!/bin/sh
# Builds Roamory, installs it on the first connected iPhone and launches it.
# Overrides team, bundle ID and deployment target on the command line, so the project stays untouched.
# Usage: ios/Roamory/scripts/run-on-phone.sh [TEAM_ID] [BUNDLE_ID]
set -e
cd "$(dirname "$0")/.."

TEAM="${1:-3492BVD75A}"
BUNDLE="${2:-com.ianstewart.Roamory}"
DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/connected/ && /physical/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]+$/) print $i}' | head -1)
[ -n "$DEVICE" ] || { echo "No connected iPhone found (plug it in and unlock it)." >&2; exit 1; }

xcodebuild build -scheme Roamory -configuration Debug -destination 'generic/platform=iOS' \
    -derivedDataPath build/device -allowProvisioningUpdates -quiet \
    IPHONEOS_DEPLOYMENT_TARGET=26.0 DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE"
xcrun devicectl device install app --device "$DEVICE" build/device/Build/Products/Debug-iphoneos/Roamory.app
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE"
