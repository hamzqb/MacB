#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
    echo "Usage: scripts/build.sh [release|debug]" >&2
    exit 1
fi
app_dir="${MACB_APP_DIR:-$HOME/Applications/MacB.app}"
case "$app_dir" in
    /*.app) ;;
    *) echo "MACB_APP_DIR must be an absolute .app path" >&2; exit 1 ;;
esac
if [[ "$app_dir" == "/" || "$app_dir" == "$HOME" || "$app_dir" == "/Applications.app" ]]; then
    echo "Refusing unsafe MACB_APP_DIR: $app_dir" >&2
    exit 1
fi
sdk="$(bash "$project_dir/scripts/select-sdk.sh")"
if [[ -n "$sdk" ]]; then
    export SDKROOT="$sdk"
    echo "Using $sdk (this toolchain has no SwiftUI macro plugin)."
fi
build_args=(--configuration "$configuration")
if [[ "${MACB_UNIVERSAL:-0}" == "1" ]]; then
    if ! xcodebuild -version >/dev/null 2>&1; then
        echo "Universal build requires full Xcode." >&2
        exit 1
    fi
    build_args+=(--arch arm64 --arch x86_64)
fi
swift build "${build_args[@]}"
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
if [[ "${MACB_UNIVERSAL:-0}" == "1" ]]; then
    lipo -verify_arch arm64 x86_64 "$binary_dir/MacB"
fi
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/MacB" "$app_dir/Contents/MacOS/MacB"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
# The local model's GPU kernels, as source: ggml compiles them on this Mac's
# GPU driver when a model first loads (see scripts/vendor-llama.sh).
cp -R Vendor/llama-metal "$app_dir/Contents/Resources/ggml-metal"
# The Now Playing reader /usr/bin/perl loads (see NowPlayingService.swift).
clang -dynamiclib -fobjc-arc -O2 -mmacosx-version-min=14.0 -framework Foundation \
    Helpers/NowPlaying/nowplaying.m -o "$app_dir/Contents/Resources/nowplaying.dylib"
# The build number is the commit count, so every build of a new commit reports a
# number nobody had to remember to raise. A dirty or gitless tree keeps whatever
# the checked-in plist says, rather than inventing a number.
if build_number="$(git rev-list --count HEAD 2>/dev/null)" && [[ -n "$build_number" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" \
        "$app_dir/Contents/Info.plist" >/dev/null
fi
swift scripts/generate-icon.swift "$project_dir/.build/MacB.iconset"
iconutil -c icns "$project_dir/.build/MacB.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
# Finder/File Provider metadata on generated bundles prevents local signing.
xattr -cr "$app_dir"
xattr -d -r com.apple.provenance "$app_dir" 2>/dev/null || true
xattr -d com.apple.FinderInfo "$app_dir" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$app_dir" 2>/dev/null || true
# A real identity keeps macOS's permission grants across rebuilds: TCC and the
# Keychain remember an app by its signing certificate, and an ad-hoc signature
# has none, so every rebuild looked like a new app. `MacB Local Signing` is a
# self-signed certificate that lives only in this Mac's login keychain; it is
# used when present, and a machine without it falls back to ad-hoc as before.
default_identity="-"
# Prefer the concrete hash of the local identity. Using the common name can be
# ambiguous after a certificate is recreated, and then codesign fails even
# though a valid identity exists.
if identity_hash="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"MacB Local Signing"/ { print $2; exit }')" && [[ -n "$identity_hash" ]]; then
    default_identity="$identity_hash"
elif security find-certificate -c "MacB Local Signing" >/dev/null 2>&1; then
    default_identity="MacB Local Signing"
fi
signing_identity="${MACB_SIGNING_IDENTITY:-$default_identity}"
codesign --force --sign "$signing_identity" "$app_dir/Contents/Resources/nowplaying.dylib"
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
