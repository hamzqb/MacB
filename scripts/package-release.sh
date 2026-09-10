#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
output_dir="${MACB_DIST_DIR:-$project_dir/dist}"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/MacB-release.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT

rm -rf "$output_dir"
mkdir -p "$output_dir" "$stage_dir/dmg"
export MACB_APP_DIR="$stage_dir/MacB.app"
export MACB_UNIVERSAL="${MACB_UNIVERSAL:-0}"
"$project_dir/scripts/build.sh" release

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    ditto -c -k --keepParent "$MACB_APP_DIR" "$stage_dir/notarization.zip"
    xcrun notarytool submit "$stage_dir/notarization.zip" --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
    xcrun stapler staple "$MACB_APP_DIR"
    xcrun stapler validate "$MACB_APP_DIR"
    spctl --assess --type execute --verbose=2 "$MACB_APP_DIR"
fi

arch="$(file "$MACB_APP_DIR/Contents/MacOS/MacB")"
if [[ "$arch" == *"x86_64"* && "$arch" == *"arm64"* ]]; then platform="universal"
elif [[ "$arch" == *"arm64"* ]]; then platform="apple-silicon"
else platform="intel"
fi

zip_name="MacB-${version}-macOS-${platform}.zip"
dmg_name="MacB-${version}-macOS-${platform}.dmg"
ditto -c -k --sequesterRsrc --keepParent "$MACB_APP_DIR" "$output_dir/$zip_name"
cp -R "$MACB_APP_DIR" "$stage_dir/dmg/MacB.app"
ln -s /Applications "$stage_dir/dmg/Applications"
hdiutil create -quiet -volname "MacB ${version}" -srcfolder "$stage_dir/dmg" -ov -format UDZO "$output_dir/$dmg_name"

(cd "$output_dir" && shasum -a 256 "$zip_name" "$dmg_name" > SHA256SUMS.txt)
echo "Release artifacts:"
ls -lh "$output_dir/$zip_name" "$output_dir/$dmg_name" "$output_dir/SHA256SUMS.txt"
