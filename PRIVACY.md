# Privacy

MacB has no account, analytics, telemetry or advertising. Window previews, clipboard items, file references, tasks, camera frames and system information remain on the Mac.

MacB makes network requests only to:

- GitHub Releases, once per day at most, to check whether a newer MacB version exists.
- Spotify artwork hosts when Spotify reports artwork for the playing track.
- Open-Meteo's geocoding and forecast services when the weather widget is visible. MacB sends the city name entered by the user and the resolved coordinates; it does not request precise device location.
- OpenAI's API (`api.openai.com`), only when the user has stored an API key and asks something. What is sent is the typed or spoken question, the last few exchanges of the same conversation, and — only when the user picks "summarise" or "fix" on the ring — the text they had selected, capped at 12,000 characters. Requests are made with `store: false`. The key lives in the Keychain and is never written to a file or a log.

Jarvis is different on purpose: while its panel is open, microphone audio is streamed live to OpenAI's Realtime API (`wss://api.openai.com/v1/realtime`) so it can answer by voice and be interrupted. It is opened only by the user (⌃⌥Space, the ring or the menu), macOS shows its microphone indicator throughout, and the connection closes when the panel closes or after 90 seconds of silence. Audio is not recorded. Jarvis can send a screenshot of the display (downscaled, never written to disk) only after the user presses "İzin ver" for that one request, and it adds calendar events or reminders only after the same kind of confirmation. After it has read anything from outside — a web result, the screen, a selection — any action that reaches beyond the conversation (opening an app or address, the clipboard, notes, its memory) also waits for a yes, so text on a page cannot steer it. Facts the user asks Jarvis to remember are kept in `~/Library/Application Support/MacB/jarvis-memory.md` (readable by the user only), shown in Settings, and sent to OpenAI at the start of each conversation.

Known limits of that protection: speech from another device in the room (a video saying "Jarvis, open…") reaches Jarvis like the user's own voice, and harmless actions such as timers or keeping the Mac awake are never gated. Jarvis cannot delete files, send messages, buy anything or enter passwords.

Speech for "Sesle sor" is recognised on the Mac with on-device recognition only; if the language has no local model, MacB refuses rather than using a server. Audio is never recorded to disk or sent anywhere; only the resulting text is used. Translation of selected text uses macOS's on-device Translation models and sends nothing.

Reading selected text uses Accessibility. Password fields and secure input are never read, nothing is read while the screen is locked, and when an application does not expose its selection MacB sends ⌘C to that application only and then puts the previous clipboard back. Saved window arrangements (application identifiers, window titles and frames) are stored in `~/Library/Application Support/MacB/window-arrangements.json`, readable by the user only.

Shelf conversions (JPEG copy, smaller copy, merged PDF) write new files beside the originals and never overwrite or modify any file. The smaller copy is written without the original's metadata, such as photo location.

Window previews and camera frames are held in memory and are not written to disk. Clipboard history and file-shelf references are stored in `~/Library/Application Support/MacB`. Removing an item from the shelf does not delete its source file.

Permissions are optional and can be revoked in System Settings. Features that do not need a revoked permission continue to work.

Numbered Mission Control desktop grouping uses dynamically loaded, read-only SkyLight symbols when available. This unsupported system interface is used locally and sends no data anywhere. If it is unavailable, MacB falls back to public window visibility information.
