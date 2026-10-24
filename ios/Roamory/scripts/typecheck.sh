#!/bin/sh
# Type-checks the app's sources against the iOS SDK without opening the Xcode project,
# for Macs whose Xcode cannot read its project format. Builds RoamoryKit for iOS first.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
scratch="${TMPDIR:-/tmp}/roamory-typecheck"

(cd "$here/../RoamoryKit" && swift build --target RoamoryKit --triple arm64-apple-ios26.0 --sdk "$sdk" \
    --scratch-path "$scratch" >/dev/null)

out=$(find "$here/Roamory" -name '*.swift' -print0 | xargs -0 xcrun swiftc -typecheck \
    -target arm64-apple-ios26.0 -sdk "$sdk" -swift-version 5 -default-isolation MainActor \
    -I "$scratch/arm64-apple-ios/debug/Modules" 2>&1 || true)
printf '%s\n' "$out" | grep -E 'warning:|error:' | grep -v '^ *|' || true
if printf '%s\n' "$out" | grep -q 'error:'; then
    echo "typecheck: failed"
    exit 1
fi
echo "typecheck: ok"
