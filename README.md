# MacB

Native macOS Dock previews, a keyboard window switcher, and a notch panel with Spotify controls, quick commands, smart status, and a persistent file shelf. Free, MIT licensed. The interface is Turkish.

## Build and run

Requires macOS 14+, Swift 6 Command Line Tools. The initial target is Apple Silicon macOS 26. No third-party packages or paid API keys are needed.

```sh
./scripts/build.sh
open dist/MacB.app
```

For daily use on this machine, build outside the Desktop/File Provider folder:

```sh
MACB_APP_DIR="$HOME/Applications/MacB.app" ./scripts/build.sh
open "$HOME/Applications/MacB.app"
```

The build creates a locally ad-hoc signed app. Run the bundled app rather than the bare Swift executable so macOS permissions attach to `dev.hamzababal.MacB`. In the first-run settings window, enable Accessibility for Dock/window control, Screen Recording for thumbnails, and Spotify Automation for music. Permissions are requested only through user actions. Local rebuilds may require granting permissions again. This build is not notarized for public distribution.

## Use

- Hover a running application's Dock icon for 250 ms; click a preview to focus it. Right, left and bottom Dock placement are supported without changing Dock preferences.
- Hold Command and press Tab to cycle windows with live previews. Release Command to select; Escape cancels. Change or disable the shortcut in settings if macOS rejects `⌘ Tab` on your machine.
- Hover or click the notch panel. On displays without a notch it appears at the top center.
- The notch can surface the right context automatically: music, files, recent downloads, recent local files, clipboard snippets and quick commands.
- Add local files/folders to the shelf with drag-and-drop or “Dosya ekle…”. Drag a shelf item over a Dock preview for 500 ms to bring the real target window forward, then drop into that window.
- Star a window card to keep that window title near the front in Dock previews and the keyboard switcher.
- Hover a window card briefly to highlight the real window location without focusing it.
- Enable focus mode to hide other regular apps when MacB focuses the selected window.
- Use Appearance settings to choose Compact, Balanced or Spacious density.
- “Raftan kaldır” removes only the saved reference. It never deletes the source file. Missing files remain visible; shelf data is stored in `~/Library/Application Support/MacB/shelf.json`.
- Spotify must be installed and running for authorization and playback control. MacB never silently launches Spotify. Only album artwork is fetched from Spotify CDN hosts; file/window data remains local.

## Verification

```sh
./scripts/test.sh
./dist/MacB.app/Contents/MacOS/MacB --diagnostics
./dist/MacB.app/Contents/MacOS/MacB --smoke-test
```

The real notch UI can be opened in fixed review states with `--preview-glance`,
`--show-panel`, or `--preview-files`.

`test.sh` runs all core policy and persistence scenarios without XCTest, which is absent from standalone Command Line Tools. Equivalent XCTest cases are kept in `Tests/MacBCoreTests` for `swift test` on a full Xcode toolchain.

Before treating a build as daily-use ready, manually check Finder, Safari, Terminal and Spotify with duplicate window titles, minimized windows, Space changes, permission denial/revocation, canceled file drags, sleep/wake and multiple displays. Public macOS APIs cannot guarantee discovery of every window on every Space. Ambiguous preview matches show an icon instead of guessing. Minimized windows may show their last image or an icon.

Capture is limited to four visible streams at 8 FPS, stops when panels close, and never records audio or writes screenshots to disk. The release idle CPU target is below 1% on the M4; GUI and permission-dependent acceptance tests require actual OS permission grants.

## Structure

- `MacBCore`: deterministic matching, panel/selection state and bookmark persistence.
- `MacB`: AppKit controllers, SwiftUI views, Accessibility, ScreenCaptureKit and Spotify Apple Events.
- `scripts/build.sh`: release compilation, icon generation, app packaging and local signing.

No private window-server APIs, Dock replacement, telemetry, accounts or background updates. Calendar, layouts, HUD replacement and other media players are outside this version.
