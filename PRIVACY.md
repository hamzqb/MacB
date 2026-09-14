# Privacy

MacB has no account, analytics, telemetry or advertising. Window previews, clipboard items, file references, tasks, camera frames and system information remain on the Mac.

MacB makes network requests only to:

- GitHub Releases, once per day at most, to check whether a newer MacB version exists.
- Spotify artwork hosts when Spotify reports artwork for the playing track.
- Open-Meteo's geocoding and forecast services when the weather widget is visible. MacB sends the city name entered by the user and the resolved coordinates; it does not request precise device location.

Window previews and camera frames are held in memory and are not written to disk. Clipboard history and file-shelf references are stored in `~/Library/Application Support/MacB`. Removing an item from the shelf does not delete its source file.

Permissions are optional and can be revoked in System Settings. Features that do not need a revoked permission continue to work.

Numbered Mission Control desktop grouping uses dynamically loaded, read-only SkyLight symbols when available. This unsupported system interface is used locally and sends no data anywhere. If it is unavailable, MacB falls back to public window visibility information.
