# MacB

Native macOS Dock previews, a keyboard window switcher, and a notch panel with automatic media controls, smart status, and a persistent file shelf. Free, MIT licensed. The interface is Turkish.

[Download the latest release](https://github.com/hamzqb/MacB/releases/latest) · [Privacy](PRIVACY.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md)

The local build also includes an advanced clipboard, a persistent task list, animated confirmations,
recent drop targets, window layouts, local productivity tools, an optional system-authentication lock,
and a two-stage camera preview.

## Install

Download the latest DMG from GitHub Releases, drag MacB into Applications, and open it. The first-run guide explains the menu bar icon and requests only the permissions needed by the features you enable.

Releases signed with a Developer ID and notarized by Apple open normally. Development or community builds that are not notarized may require Control-clicking MacB and choosing **Open** once. Never bypass Gatekeeper for an archive whose checksum does not match `SHA256SUMS.txt` on the release.

MacB checks GitHub Releases at most once per day. When a new version exists, the menu and Settings show an download action. Installation remains user-controlled until signed Sparkle updates are enabled.

## Build from source

Requires macOS 14+, Swift 6 Command Line Tools. The initial target is Apple Silicon macOS 26. No third-party packages or paid API keys are needed.

```sh
./scripts/build.sh
open "$HOME/Applications/MacB.app"
```

For daily use on this machine, build outside the Desktop/File Provider folder:

```sh
./scripts/build.sh
open "$HOME/Applications/MacB.app"
```

The build creates a locally ad-hoc signed app in `~/Applications`. Run that bundled app rather than the bare Swift executable so macOS permissions attach to `dev.hamzababal.MacB`. The first-run guide requests Accessibility for Dock/window control, Screen Recording for thumbnails, and Input Monitoring when `⌘ Tab` is enabled. Media and camera permissions are requested only when their features are used. Local source builds are not notarized.

Create local ZIP and DMG artifacts with:

```sh
./scripts/package-release.sh
```

Full Xcode can produce a universal Apple Silicon + Intel build with `MACB_UNIVERSAL=1`. Release tags use this mode in GitHub Actions. Developer ID and notarization credentials are optional for local packaging and required for a warning-free public release.

## Use

- Hover a running application's Dock icon for 250 ms; click a preview to focus it. Right, left and bottom Dock placement are supported without changing Dock preferences.
- Hold Command and press Tab to cycle windows with live previews. Release Command to select; Escape cancels. Change or disable the shortcut in settings if macOS rejects `⌘ Tab` on your machine.
- Hover or click the notch panel. On displays without a notch it appears at the top center.
- The notch can surface the right context automatically: music, files, recent downloads, recent local files and clipboard snippets.
- Add local files/folders to the shelf with drag-and-drop or “Dosya ekle…”. Drag a shelf item over a Dock preview for 500 ms to bring the real target window forward, then drop into that window.
- Star a window card to keep that window title near the front in Dock previews and the keyboard switcher.
- Hover a window card briefly to highlight the real window location without focusing it.
- Enable focus mode to hide other regular apps when MacB focuses the selected window.
- Use Appearance settings to choose Compact, Balanced or Spacious density.
- Choose Automatic, Pure Black or Liquid Glass for the island surface.
- Enable Window Management for Control–Option layout shortcuts: arrows tile halves, U/I/J/K tile corners, Return maximizes, C centers, Backspace restores and N moves the window to the next display.
- The Clipboard tab keeps local text, links, images and file references, supports search and favorites, and filters common password, token, private-key and payment-card patterns.
- The Tools tab shows Claude/Codex desktop and terminal activity, CPU/RAM/disk/battery/thermal state, creates and extracts ZIP files, sends audio/video to MacWhisper, finds exact application leftovers for review, and offers a timed keyboard-cleaning lock.
- “Raftan kaldır” removes only the saved reference. It never deletes the source file. Missing files remain visible; shelf data is stored in `~/Library/Application Support/MacB/shelf.json`.
- Playing media appears automatically in the notch. Spotify and Apple Music expose track details through local automation. Safari and supported Chromium browsers are queried locally for an HTML audio/video element that is actually playing; a paused tab never appears merely because of its title. Browser JavaScript from Apple Events must be enabled in the browser's Developer menu. If nothing is playing, the media area stays quiet. MacB never silently launches media apps. Only Spotify album artwork is fetched from Spotify CDN hosts; file/window data remains local.

## Verification

```sh
./scripts/test.sh
"$HOME/Applications/MacB.app/Contents/MacOS/MacB" --diagnostics
"$HOME/Applications/MacB.app/Contents/MacOS/MacB" --smoke-test
```

The real UI can be opened in fixed review states with `--preview-onboarding`, `--preview-glance`,
`--show-panel`, `--preview-files`, `--preview-clipboard`, `--preview-tools`, or `--preview-switcher`.

`test.sh` runs all core policy and persistence scenarios without XCTest, which is absent from standalone Command Line Tools. Equivalent XCTest cases are kept in `Tests/MacBCoreTests` for `swift test` on a full Xcode toolchain.

Before treating a build as daily-use ready, manually check Finder, Safari, Terminal and Spotify with duplicate window titles, minimized windows, Space changes, permission denial/revocation, canceled file drags, sleep/wake and multiple displays. Public macOS APIs cannot guarantee discovery of every window on every Space. Ambiguous preview matches show an icon instead of guessing. Minimized windows may show their last image or an icon.

Capture is limited to four visible streams at 8 FPS, stops when panels close, and never records audio or writes screenshots to disk. The release idle CPU target is below 1% on the M4; GUI and permission-dependent acceptance tests require actual OS permission grants.

## Structure

- `MacBCore`: deterministic matching, window-layout math, panel/selection state and bookmark persistence.
- `MacB`: AppKit controllers, SwiftUI views, Accessibility, ScreenCaptureKit, media automation and local productivity services.
- `scripts/build.sh`: release compilation, icon generation, app packaging and local signing.

No private window-server APIs, Dock replacement, telemetry or accounts. Hardware fan control is intentionally absent; the system monitor uses public, read-only macOS information. See [PRIVACY.md](PRIVACY.md) for the two narrowly scoped network requests.
