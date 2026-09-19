# Changelog

## Unreleased

- Radial shortcut ring (Fn + two-finger click or three-finger tap) with app, file and per-application slices.
- AI panel with web search and sources; selected text can be summarised or corrected from the ring, copied and written back in place.
- Voice questions with on-device speech recognition; on-device translation of selected text.
- Shelf conversions (JPEG copy, smaller copy, PDF merge) and AirDrop; screenshots can land on the shelf.
- Stay-awake timer with an island countdown; saved window arrangements restored by hand or when displays change.
- Searchable, optionally persistent clipboard history; a charging-level automation trigger.
- MacB voice assistant (pronounced "Mek bi"), inside the island: a live, interruptible assistant on OpenAI's Realtime API, with web research, a per-use screen look, calendar and reminders, apps, media, volume, timers, windows, Claude/Codex session status, weather and an editable long-term memory; outward actions after reading outside content need a yes.
- Free AI providers: Groq, Google Gemini, OpenRouter and Hugging Face answer the panel, the ring's text slices and the selection tasks with no OpenAI bill. Each key lives in its own Keychain item and is only sent to the service it belongs to; the provider is chosen automatically, free before paid, and models are picked from a list.
- Cost meter: an estimate of what OpenAI has cost today and this month, from the provider's own token counts. Only numbers are stored — never a question or an answer.
- `read_screen_text`: the assistant can read what is on screen with Apple's own recognition on this Mac and send only the words, which is cheaper than a screenshot and shows far less. Still confirmed every time.
- Morning briefing: one greeting a day in the island with the weather, what is on today and anything waiting, read aloud by macOS's own voice. Costs nothing and needs no key.
- Voice scenarios: a name for several steps — windows, stay-awake, apps, volume, music, timers and your own Shortcuts — run from the menu, from Settings or by asking MacB. MacB can run one but cannot write one.
- The assistant always answers in Turkish, has a character setting, a clearer voice list, and connects faster: the socket and the microphone now open at the same time.
- The island's assistant keeps the newest words in a fixed window instead of cutting them off, the orb carries the state in its colour, and a closed island shows it as a small pulsing dot with no transcript.
- MacB can appear in the Dock and the ⌘Tab switcher, for anyone who goes looking for it there.
- Weather falls back to OpenWeatherMap when Open-Meteo does not answer and a key is stored.
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
