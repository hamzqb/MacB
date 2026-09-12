#!/bin/bash
# Prints an SDKROOT to build against, or nothing to use the default.
#
# Command Line Tools 27 ships an SDK whose SwiftUI declares @State as a macro,
# but no SwiftUIMacros plugin to implement it, so every SwiftUI view in the
# project fails to compile with "plugin for module 'SwiftUIMacros' not found".
# Full Xcode carries the plugin; a Command Line Tools install does not. When the
# plugin is missing, fall back to the newest installed SDK that predates the
# change and still compiles.
#
# Once Apple ships the plugin, or Xcode is installed, this prints nothing and
# the default SDK is used again.
set -euo pipefail
developer="$(xcode-select -p 2>/dev/null || true)"
[[ -n "$developer" ]] || exit 0
plugins="$developer/usr/lib/swift/host/plugins"
[[ -f "$plugins/libSwiftUIMacros.dylib" ]] && exit 0
for candidate in "$developer/SDKs"/MacOSX26.5.sdk "$developer/SDKs"/MacOSX26.sdk; do
    [[ -d "$candidate" ]] || continue
    echo "$candidate"
    exit 0
done
