# Changelog

## Unreleased

- Radial shortcut ring (Fn + two-finger click or three-finger tap) with app, file and per-application slices.
- AI panel with web search and sources; selected text can be summarised or corrected from the ring, copied and written back in place.
- Voice questions with on-device speech recognition; on-device translation of selected text.
- Shelf conversions (JPEG copy, smaller copy, PDF merge) and AirDrop; screenshots can land on the shelf.
- Stay-awake timer with an island countdown; saved window arrangements restored by hand or when displays change.
- Searchable, optionally persistent clipboard history; a charging-level automation trigger.
- MacB voice assistant (pronounced "Mek bi"), inside the island: a live, interruptible assistant on OpenAI's Realtime API, with web research, a per-use screen look, calendar and reminders, apps, media, volume, timers, windows, Claude/Codex session status, weather and an editable long-term memory; outward actions after reading outside content need a yes.
- Fixed: the window-layout hot key handler no longer swallows other MacB shortcuts.
- Fixed: launching no longer blocks on a Keychain prompt while checking for a stored API key.

## 0.3.0

- Rebuilt the notch panel around a responsive, customizable widget library with media, weather, system, timer, calendar, notes, tasks, apps, files and clipboard cards.
- Added Liquid Glass and pure-black appearances, shared design tokens, motion polish, focus rings, haptics and content-sized panel geometry.
- Added numbered Mission Control desktop sections to the window switcher with a safe public-API fallback.
- Added reviewed application removal with confidence ratings, leftover discovery, cache cleanup and Trash-only operations.
- Added opt-in local face protection for MacB surfaces, encrypted templates and a Keychain key guarded by system authentication.
- Added application resource monitoring, lid-angle island folding, optional screen blur and user-configurable greetings.
- Added local automation rules for app, lid, charging, battery and media events without shell execution.

## 0.2.0

- Added native three-step onboarding and contextual permission setup.
- Added Dock window previews, compact keyboard window switcher and duplicate helper-window filtering.
- Added automatic local media discovery for Spotify, Apple Music and supported browsers.
- Added persistent file shelf, clipboard history, tasks, window layouts, camera preview and local utilities.
- Added session-lock suspension, coalesced window scans and safer archive/application-removal flows.
- Added daily GitHub Release checks and reproducible ZIP/DMG release packaging.

## 0.1.0

- Initial local prototype.
