#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
    echo "Usage: scripts/build.sh [release|debug]" >&2
    exit 1
fi
swift build --configuration "$configuration"
binary_dir="$(swift build --configuration "$configuration" --show-bin-path)"
app_dir="${MACB_APP_DIR:-$project_dir/dist/MacB.app}"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/MacB" "$app_dir/Contents/MacOS/MacB"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
swift scripts/generate-icon.swift "$project_dir/.build/MacB.iconset"
iconutil -c icns "$project_dir/.build/MacB.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
# Finder/File Provider metadata on generated bundles prevents local signing.
xattr -cr "$app_dir"
xattr -d -r com.apple.provenance "$app_dir" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$app_dir" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$app_dir" 2>/dev/null || true
signing_identity="${MACB_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    # Keep a stable designated requirement for local ad-hoc builds. Without this,
    # every rebuild is identified only by its changing CDHash and macOS drops the
    # Accessibility, Screen Recording, and Input Monitoring grants.
    codesign --force --sign - --options runtime \
        --identifier dev.hamzababal.MacB \
        --requirements '=designated => identifier "dev.hamzababal.MacB"' \
        --entitlements Resources/MacB.entitlements "$app_dir"
else
    codesign --force --sign "$signing_identity" --options runtime \
        --entitlements Resources/MacB.entitlements "$app_dir"
fi
# Some Desktop/File Provider locations can attach metadata immediately after signing.
xattr -cr "$app_dir"
xattr -d -r com.apple.provenance "$app_dir" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$app_dir" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$app_dir" 2>/dev/null || true
codesign --verify --deep --strict "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist"
echo "Ready: $app_dir"
