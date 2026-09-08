# Plan: MacB Dynamic Island Redesign

**Generated**: 2026-09-08
**Estimated Complexity**: High

## Overview

MacB should move away from a large tabbed control panel and become a calmer, more fluid Dynamic Island style surface. The new direction keeps Dock previews and window switching, but the notch experience becomes the emotional center: compact most of the time, rich only when needed, and visually quieter.

The design inspiration is Atoll's modular command surface and dynamic-island's focused music-first behavior. MacB should not copy source code or exact UI, especially because Atoll is GPL-3.0. We will borrow product ideas and rebuild them in MacB's own SwiftUI/AppKit design language.

## Design Direction

MacB's new visual language is "polished black glass with soft depth." The surface stays almost black, but uses layered material, subtle inner highlights, compact iconography, and motion that feels like one shape breathing instead of separate views appearing.

Hover should never show the full product. Hover only answers the immediate question:

- What is playing?
- What window is under this Dock icon?
- Is there one useful thing waiting for me?

Click opens the richer surface.

## Sprint 1: Notch Island Foundation

**Goal**: Replace the current heavy notch panel with a smaller, staged island.

**Demo/Validation**:
- Hover notch for music glance.
- Click notch for expanded island.
- Drag file to notch and verify files view opens directly.

### Task 1.1: Create Island Geometry Tokens
- **Location**: `Sources/MacB/App/MacBDesign.swift`
- **Description**: Add fixed geometry tokens for island width, collapsed height, glance height, expanded music height, expanded files height, corner radius, icon sizes, inner shadow opacity, and blur strengths.
- **Dependencies**: None
- **Acceptance Criteria**:
  - All notch sizes come from design tokens.
  - No magic layout numbers remain in `NotchView`.
- **Validation**: `swift build`

### Task 1.2: Split Hover and Expanded Content
- **Location**: `Sources/MacB/Notch/NotchView.swift`, `Sources/MacB/Notch/NotchController.swift`
- **Description**: Hover should show only music glance or one status chip. Expanded view should contain Music, Files, Commands, and Activity.
- **Dependencies**: Task 1.1
- **Acceptance Criteria**:
  - Hover has no tabs.
  - Expanded state has tabs or segmented navigation.
  - Empty music view is small and elegant.
- **Validation**: Open with `--preview-glance` and `--show-panel`, inspect screenshots.

### Task 1.3: Add Island Surface Treatment
- **Location**: `Sources/MacB/Notch/NotchView.swift`
- **Description**: Replace flat black panel with layered black material: base black, faint top shine, soft bottom fade, 1px inner border, and controlled shadow.
- **Dependencies**: Task 1.1
- **Acceptance Criteria**:
  - Panel still blends with the physical notch.
  - No visible gray box feeling.
  - Text remains readable over the surface.
- **Validation**: Screenshot on light and dark wallpapers.

## Sprint 2: Music First Experience

**Goal**: Make music the best looking part of the app.

**Demo/Validation**:
- Spotify closed.
- Spotify running without permission.
- Spotify playing with artwork.
- Long track and artist names.

### Task 2.1: Redesign Music Glance
- **Location**: `Sources/MacB/Notch/NotchView.swift`
- **Description**: Use artwork left, title/artist center, play/pause right. Keep width around 360px and remove all secondary buttons from hover.
- **Dependencies**: Sprint 1
- **Acceptance Criteria**:
  - One-line title and artist truncate cleanly.
  - Play button is reachable by mouse and VoiceOver.
  - Spotify closed state shows one small action.
- **Validation**: Visual screenshots with Spotify states.

### Task 2.2: Add Interactive Wave/Scrub Visual
- **Location**: `Sources/MacB/Notch/NotchView.swift`, `Sources/MacB/Services/SpotifyService.swift`
- **Description**: Add a subtle dotted waveform/progress strip in expanded music view. It should animate only while panel is open and Spotify is playing.
- **Dependencies**: Task 2.1
- **Acceptance Criteria**:
  - No idle animation when panel is closed.
  - Reduced Motion shows static progress.
  - CPU remains low.
- **Validation**: Measure idle CPU, inspect animation.

### Task 2.3: Add Gesture-Like Controls
- **Location**: `Sources/MacB/Notch/NotchHostingView.swift`, `Sources/MacB/Notch/NotchView.swift`
- **Description**: Horizontal swipe on music area moves previous/next. Vertical swipe collapses or expands where macOS events allow it.
- **Dependencies**: Task 2.1
- **Acceptance Criteria**:
  - Swipes do not interfere with file drag.
  - Buttons still work.
- **Validation**: Manual Mac test.

## Sprint 3: Dock Hover Redesign

**Goal**: Make Dock hover simple, fast, and visually aligned with the notch.

**Demo/Validation**:
- Hover Finder/Safari/Terminal Dock icons.
- Move between Dock icons.
- Test right, left, and bottom Dock.

### Task 3.1: Compact Preview Strip
- **Location**: `Sources/MacB/Windows/DockController.swift`, `Sources/MacB/Windows/WindowCardView.swift`
- **Description**: Convert Dock hover from a large card stack into a compact strip. Show app icon, app name, count, and up to three preview cards.
- **Dependencies**: Sprint 1 design tokens
- **Acceptance Criteria**:
  - No more than three cards visible by default.
  - Extra windows show as a small count chip.
  - Actions stay hidden until hover/focus.
- **Validation**: Visual screenshot and window action test.

### Task 3.2: Window Peek Polish
- **Location**: `Sources/MacB/Windows/DockController.swift`
- **Description**: Replace current outline peek with a softer spotlight: dim outside target window slightly and add a thin accent ring.
- **Dependencies**: Task 3.1
- **Acceptance Criteria**:
  - Peek does not focus or raise the window.
  - Peek closes immediately when leaving the card.
  - Reduced Motion avoids fade movement.
- **Validation**: Manual Mac test.

## Sprint 4: Cmd Tab Preview Switcher

**Goal**: Make `⌘ Tab` feel like a true MacB window switcher with live previews.

**Demo/Validation**:
- Hold `⌘ Tab`.
- Tap Tab repeatedly.
- Release Command to focus selected window.
- Escape cancels.

### Task 4.1: Harden Command Tab Capture
- **Location**: `Sources/MacB/App/HotKeyController.swift`, `Sources/MacB/App/SettingsView.swift`
- **Description**: Keep CGEvent tap for `⌘ Tab`, show clear permission state, and fall back to `⌥ Tab` if macOS denies capture.
- **Dependencies**: None
- **Acceptance Criteria**:
  - User sees why `⌘ Tab` did or did not work.
  - App never steals Tab if switcher is disabled.
- **Validation**: Manual permission toggle test.

### Task 4.2: Premium Switcher Layout
- **Location**: `Sources/MacB/App/SwitcherController.swift`, `Sources/MacB/Windows/WindowCardView.swift`
- **Description**: Redesign switcher as a centered island-like shelf with large selected preview, smaller neighboring previews, app grouping, favorite pinning, and a small keyboard hint row.
- **Dependencies**: Task 4.1
- **Acceptance Criteria**:
  - Selected window is visually obvious.
  - Same app grouping is readable.
  - Long titles never overflow.
- **Validation**: Finder/Safari/Terminal with duplicate names.

## Sprint 5: Face ID Like Secure Moment

**Goal**: Add a secure unlock experience without pretending unsupported hardware exists.

**Demo/Validation**:
- Lock a protected action.
- Trigger unlock.
- Authenticate with Touch ID, Apple Watch, or password through macOS.

### Task 5.1: Add Local Authentication Service
- **Location**: `Sources/MacB/App/BiometricAuthService.swift`
- **Description**: Use `LAContext` and `LAPolicy.deviceOwnerAuthentication` to authenticate before sensitive actions such as revealing clipboard history, opening protected files, or enabling focus mode.
- **Dependencies**: None
- **Acceptance Criteria**:
  - Uses system authentication UI.
  - Supports Touch ID, Apple Watch, or password on macOS.
  - If Face ID appears on future Macs, display Face ID based on `LAContext.biometryType`.
- **Validation**: Manual authentication test.

### Task 5.2: Add Face ID Style Animation
- **Location**: `Sources/MacB/Notch/NotchView.swift`
- **Description**: Add a small face-scan visual inside the notch before invoking system authentication. This is visual feedback only; security comes from LocalAuthentication.
- **Dependencies**: Task 5.1
- **Acceptance Criteria**:
  - UI never claims real Face ID when macOS reports Touch ID or no biometrics.
  - Reduced Motion shows a static lock icon.
- **Validation**: Screenshots and authentication failure test.

## Sprint 6: Activity Modules

**Goal**: Bring Atoll-like utility without turning hover into clutter.

**Demo/Validation**:
- Start a download.
- Copy text.
- Add files to shelf.
- Open Activity tab.

### Task 6.1: Activity Tab
- **Location**: `Sources/MacB/Notch/NotchView.swift`, `Sources/MacB/App/FeatureStores.swift`
- **Description**: Add an Activity tab for downloads, clipboard, and quick commands. Keep Files tab only for persistent shelf and recent local files.
- **Dependencies**: Sprint 1
- **Acceptance Criteria**:
  - Hover remains minimal.
  - Activity tab has compact rows and status chips.
  - Folder access prompts only occur after enabling the feature.
- **Validation**: Permission and idle CPU test.

### Task 6.2: Better Empty States
- **Location**: `Sources/MacB/Notch/NotchView.swift`, `Sources/MacB/App/SettingsView.swift`
- **Description**: Replace explanatory blocks with compact empty visuals and one clear action.
- **Dependencies**: Sprint 1
- **Acceptance Criteria**:
  - No large instructional text in compact panels.
  - Buttons use icons and short labels.
- **Validation**: Screenshot review.

## Testing Strategy

- Run `swift build` after each sprint.
- Run `./scripts/test.sh` for core state and persistence.
- Add core tests for any new state transition, especially activity/auth/commands.
- Use debug arguments for visual screenshots: `--preview-glance`, `--show-panel`, `--preview-files`, and add `--preview-auth`.
- Manually verify on the real Mac: Accessibility on/off, Screen Recording on/off, Spotify closed/running/authorized, right Dock hover, `⌘ Tab`, sleep/wake, Space changes, Reduce Motion.

## Potential Risks & Gotchas

- Real Face ID is not generally available on current Macs through a custom camera implementation. MacB should use LocalAuthentication for real security and only use Face ID wording when macOS reports Face ID.
- `⌘ Tab` capture depends on Accessibility and may conflict with macOS behavior. Provide a visible fallback to `⌥ Tab`.
- Atoll is GPL-3.0, so copying source code would affect MacB's license. Rebuild ideas independently.
- Dynamic utility modules can make hover noisy. Keep hover minimal and move modules into expanded tabs.
- Downloads/recent file monitoring can trigger folder permissions. Keep these disabled until the user opts in.

## Rollback Plan

- Keep the current notch and Dock components behind existing preferences until the new island is stable.
- Add new preview/debug flags instead of replacing all visual states at once.
- If `⌘ Tab` capture causes issues, switch default back to `⌥ Tab` without removing the redesigned switcher.
