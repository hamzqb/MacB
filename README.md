# MacB

Native macOS Dock previews, a keyboard window switcher, and a notch panel with automatic media controls, smart status, and a persistent file shelf. Free, MIT licensed. The interface is Turkish.

[Build from source](#build-from-source) · [Privacy](PRIVACY.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md)

The local build also includes an advanced clipboard, a persistent task list, animated confirmations,
recent drop targets, window layouts, local productivity tools, local watcher cards, an optional
system-authentication lock, and a two-stage camera preview.

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
- Hold Command and press Tab to cycle windows with live previews. Windows on the active desktop and other desktops appear in separate sections; selecting an offscreen window lets macOS move to its desktop. Release Command to select; Escape cancels. Change or disable the shortcut in settings if macOS rejects `⌘ Tab` on your machine.
- Hover or click the notch panel. On displays without a notch it appears at the top center.
- The notch can surface the right context automatically: music, files, recent downloads, recent local files and clipboard snippets.
- Add local files/folders to the shelf with drag-and-drop or “Dosya ekle…”. Drag a shelf item over a Dock preview for 500 ms to bring the real target window forward, then drop into that window.
- Star a window card to keep that window title near the front in Dock previews and the keyboard switcher.
- Hover a window card briefly to highlight the real window location without focusing it.
- Enable focus mode to hide other regular apps when MacB focuses the selected window.
- Use Appearance settings to choose Compact, Balanced or Spacious density.
- Choose Automatic, Pure Black or Liquid Glass for the island surface.
- Choose among four responsive media cards and four weather treatments. Cards reflow at narrow sizes instead of clipping, and the island measures visible content instead of reserving an empty canvas.
- The Apps area searches pinned apps and folders and groups them automatically into productivity, development, design, communication, media, utilities, and folders.
- Enable Window Management for Control–Option layout shortcuts: arrows tile halves, U/I/J/K tile corners, Return maximizes, C centers, Backspace restores and N moves the window to the next display.
- The Clipboard tab keeps local text, links, images and file references, supports search and favorites, and filters common password, token, private-key and payment-card patterns.
- The Tools tab shows Claude/Codex desktop and terminal activity, CPU/RAM/disk/battery/thermal state, which applications are using the most memory and processor, creates and extracts ZIP files, sends audio/video to MacWhisper, finds application leftovers for review, reclaims cache and log folders, and offers a timed keyboard-cleaning lock.
- The Watchers tab adds local “Jarvis eye” cards for product prices, website text changes, GitHub release tags and system thresholds. Checks run on a quiet schedule, store only the last value/baseline locally, and surface changes in the notch.
- The uninstaller rates every find as exact, likely or possible, and only the first two are ticked for you. It looks one level inside a vendor folder such as `Application Support/Google`, never offers the vendor folder itself, and shows `/Library` items without ever asking for administrator rights. Nothing is deleted; everything is moved to the Trash.
- On Apple silicon MacBooks with a readable hinge sensor, the island folds down with the lid as it closes and unfolds with a one-line greeting when it comes back up. The sensor is only read, never written to, and the feature turns itself off where the sensor is missing. The angle where the fold starts, the two lines the island says, and whether the whole screen blurs with it are all set under Menteşe in Appearance settings.
- The screen blur is stacked panes of the system's own material, which blur what the window server has already drawn behind them. Nothing is captured, no Screen Recording permission is asked for, and with an external monitor attached only the MacBook's own display is covered. The panes never take the mouse and are removed if the hinge stops reporting.
- Rules run things for you: ten triggers such as the lid opening, the charger arriving, the battery crossing a level you pick, or an application quitting; six actions such as opening an app or a link, showing a line on the island, starting a timer, pausing what is playing, or running one of your own Shortcuts. There is no shell. Links are limited to http, https and files on this Mac, checked when the rule is saved and again when it runs. A rule rests for a minute after firing and a battery rule fires once per crossing, so nothing can loop. Rules live in `~/Library/Application Support/MacB/automation.json` and are off until you switch them on.
- Resource use is read with libproc and grouped by application, so twenty Chrome helpers read as one line. Quitting asks the application the way the Dock does; nothing is force-killed, and daemons are never offered.
- Cache cleaning scans `Library/Caches`, `Library/Logs` and the usual build-tool caches, one level deep. Documents, containers, preferences and application support are never scanned, a cache whose application is running is listed but left unticked, and the folders go to the Trash rather than being deleted.
- “Raftan kaldır” removes only the saved reference. It never deletes the source file. Missing files remain visible; shelf data is stored in `~/Library/Application Support/MacB/shelf.json`.
- Playing media appears automatically in the notch. Spotify and Apple Music expose track details through local automation. Safari and supported Chromium browsers are queried locally for an HTML audio/video element that is actually playing; a paused tab never appears merely because of its title. Browser JavaScript from Apple Events must be enabled in the browser's Developer menu. If nothing is playing, the media area stays quiet. MacB never silently launches media apps. Only Spotify album artwork is fetched from Spotify CDN hosts; file/window data remains local.

## Verification

```sh
./scripts/test.sh
"$HOME/Applications/MacB.app/Contents/MacOS/MacB" --diagnostics
"$HOME/Applications/MacB.app/Contents/MacOS/MacB" --smoke-test
```

The real UI can be opened in fixed review states with `--preview-onboarding`, `--preview-peek`,
`--preview-home`, `--preview-active-timer`, `--preview-apps`, `--preview-files`, `--preview-clipboard`, `--preview-drop`,
`--preview-timer`, `--preview-lid`, `--preview-automation`, or `--preview-switcher`. `--blur-probe <0-1>` holds the lid blur at a fixed strength so it can be looked at without a lid.

`test.sh` runs all core policy and persistence scenarios without XCTest, which is absent from standalone Command Line Tools. Equivalent XCTest cases are kept in `Tests/MacBCoreTests` for `swift test` on a full Xcode toolchain.

Before treating a build as daily-use ready, manually check Finder, Safari, Terminal and Spotify with duplicate window titles, minimized windows, Space changes, permission denial/revocation, canceled file drags, sleep/wake and multiple displays. The switcher reads Mission Control's Space topology dynamically and shows numbered `Masaüstü` sections; if that unsupported system interface changes, it safely falls back to the public current/other view. Ambiguous preview matches show an icon instead of guessing. Minimized windows may show their last image or an icon.

Capture is limited to four visible streams at 8 FPS, stops when panels close, and never records audio or writes screenshots to disk. The release idle CPU target is below 1% on the M4; GUI and permission-dependent acceptance tests require actual OS permission grants.

## Structure

- `MacBCore`: deterministic matching, window-layout math, panel/selection state and bookmark persistence.
- `MacB`: AppKit controllers, SwiftUI views, Accessibility, ScreenCaptureKit, media automation and local productivity services.
- `scripts/build.sh`: release compilation, icon generation, app packaging and local signing.

MacB has no Dock replacement, telemetry or accounts. Numbered desktop grouping dynamically reads unsupported, private SkyLight Space information and falls back safely when it is unavailable. Hardware fan control is intentionally absent; the system monitor uses read-only macOS information. See [PRIVACY.md](PRIVACY.md) for the three narrowly scoped network request types.
