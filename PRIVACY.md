# Privacy

MacB has no account, analytics, telemetry or advertising. Window previews, clipboard items, file references, tasks, camera frames and system information remain on the Mac.

MacB makes network requests only to:

- GitHub Releases, once per day at most, to check whether a newer MacB version exists.
- Spotify artwork hosts when Spotify reports artwork for the playing track.
- Open-Meteo's geocoding and forecast services when the weather widget is visible. MacB sends the city name entered by the user and the resolved coordinates; it does not request precise device location.
- OpenAI's API (`api.openai.com`), only when the user has stored an API key and asks something. What is sent is the typed or spoken question, the last few exchanges of the same conversation, and — only when the user picks "summarise" or "fix" on the ring — the text they had selected, capped at 12,000 characters. Requests are made with `store: false`. The key lives in the Keychain and is never written to a file or a log.

Speech for "Sesle sor" is recognised on the Mac with on-device recognition only; if the language has no local model, MacB refuses rather than using a server. Audio is never recorded to disk or sent anywhere; only the resulting text is used. Translation of selected text uses macOS's on-device Translation models and sends nothing.

Reading selected text uses Accessibility. Password fields and secure input are never read, nothing is read while the screen is locked, and when an application does not expose its selection MacB sends ⌘C to that application only and then puts the previous clipboard back. Saved window arrangements (application identifiers, window titles and frames) are stored in `~/Library/Application Support/MacB/window-arrangements.json`, readable by the user only.

Shelf conversions (JPEG copy, smaller copy, merged PDF) write new files beside the originals and never overwrite or modify any file. The smaller copy is written without the original's metadata, such as photo location.

Window previews and camera frames are held in memory and are not written to disk. Clipboard history and file-shelf references are stored in `~/Library/Application Support/MacB`. Removing an item from the shelf does not delete its source file.

Permissions are optional and can be revoked in System Settings. Features that do not need a revoked permission continue to work.

Numbered Mission Control desktop grouping uses dynamically loaded, read-only SkyLight symbols when available. This unsupported system interface is used locally and sends no data anywhere. If it is unavailable, MacB falls back to public window visibility information.
