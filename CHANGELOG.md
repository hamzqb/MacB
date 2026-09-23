# Changelog

## Unreleased

- The island is Atoll's shape: home is the player alone — a large cover with the
  playing app's icon, the artist in the cover's colour, a progress bar that can
  be dragged — and a new stats page draws CPU, memory, GPU, network and disk as
  running lines. The widget strip moved to its own tab and the battery sits at
  the end of the navigation row.
- What is playing now comes from the system, so a YouTube tab in Chrome, a
  podcast or anything else shows up with its cover, not only Spotify and Music.
- Liquid Glass is Apple's glass with nothing over it: the black gradient is gone
  and the glass can see the desktop again.
- The island can be the only volume and brightness indicator: MacB takes those
  keys, sets the level itself and macOS has nothing to announce. Never at the
  lock screen, and the switch is in Settings.
- Widgets can live on the desktop, in Apple's three sizes, dragged anywhere.
- The hover strip carries the track, the running timer, the last thing copied
  and the shelf — each only while it exists — and three buttons: ask MacB, take
  a selection screenshot, keep the Mac awake.
- The shelf and the clipboard are lists rather than walls of cards, and the
  settings window trades its card chrome for grouped rows, a search field and a
  note under each permission saying which features use it.
- The camera preview fills the panel instead of sitting above a list, and
  recovers by itself when another app had the camera.
- NVIDIA joins the AI providers, and MacB can look at the window in front and
  answer about it with a vision model.
- MacB looks things up before answering a question about now, and names its
  sources — for every provider, not just the one that can search.
- Face unlock uses a real face model, SFace under Apache 2.0, shipped with the
  app and compiled by Core ML on the Mac at first use.
- The assistant can press what it can see. Everything on screen is listed with
  a number, and it clicks by number instead of by name — a name is a guess, and
  a wrong guess presses the wrong button. Where the Accessibility API sees
  nothing, as in a browser's page, the page itself is read and appears in the
  same list; where something has no name at all, the numbers are drawn on the
  screenshot it is looking at.
- Clicking or filling something in a web page no longer takes MacB down with
  it: the name was being escaped with a call that raises rather than returns,
  so every attempt crashed the application instead of pressing the button.
- When a name is not found, the answer says what is there, so the next try is
  right instead of another guess.
- Each question goes to the provider and model that suit it — a chat, a hard
  question, a picture, the assistant's own tool calls — and moves on by itself
  when one cannot answer. NVIDIA's models were corrected to the ones that
  actually reply: the model MacB had been asking for was retired months ago and
  every request to it failed. A paid provider is never used as a silent
  fallback.
- Settings shows which model each provider would be asked for which job, and
  says when one has been failing or answering slowly.
- Removed: "quit when the last window closes". The close button closes a
  window; Command-Q quits, as macOS intends.

## 0.4.0

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
- MacB can put the Mac to sleep, sleep just the display or lock the screen (each asked about every time), and switch macOS between dark and light. It will not shut down or restart: those close unsaved work, and a voice assistant that mishears should not be able to end a session.
- "Play X": MacB opens the first matching video on YouTube and it starts playing, or opens Spotify or Music on the search. Only a video identifier is read out of the results page, so nothing written on YouTube reaches the model.
- MacB talks the way you talk: length, register, slang and pace are taken from the person in front of it, turn by turn. Fixed characters are still there if you want one; matching you is the default.
- MacB can open any page of System Settings by name for the things macOS will not let an application change, and can turn Wi-Fi on and off itself.
- The assistant in the island is a badge: an orb and one word. Tap it for the line to type into, turn subtitles on when you want to read along, and it grows by exactly that much.
- The assistant in the island is about half the size it was: an orb, what it is doing, and the one line being said — no transcript, since the answer is in the air. What has to be read gets its own card.
- Voice scenarios: a name for several steps — windows, stay-awake, apps, volume, music, timers and your own Shortcuts — run from the menu, from Settings or by asking MacB. MacB can run one but cannot write one.
- The assistant always answers in Turkish, has a character setting, a clearer voice list, and connects faster: the socket and the microphone now open at the same time.
- The island's assistant keeps the newest words in a fixed window instead of cutting them off, the orb carries the state in its colour, and a closed island shows it as a small pulsing dot with no transcript.
- MacB can appear in the Dock and the ⌘Tab switcher, for anyone who goes looking for it there.
- Weather falls back to OpenWeatherMap when Open-Meteo does not answer and a key is stored.
- Added local watcher cards for website prices, website text changes, GitHub releases and CPU/RAM/battery thresholds, with notch alerts and a dedicated Settings page.
- Added a visible MacB agent cursor badge so background checks can show what MacB is doing without moving the real mouse.
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
