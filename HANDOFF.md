# MacB — current handoff

Version 0.3.0. `./scripts/test.sh` passes 99/99 core scenarios. The signed
Release bundle is installed at `~/Applications/MacB.app`. The build number is
now the git commit count, written into the bundle by `scripts/build.sh`, so it
rises on its own and nobody has to remember it.

## Done recently

- **Lid hinge.** The island folds with the lid, driven straight from the hinge
  sensor with no canned animation. The fold starts at an angle the user picks
  (20–110°, default 60) and a farewell line is put on screen so there is
  something to fold, because the island is collapsed to nothing when idle.
- **Screen blur.** The whole built-in display blurs as the lid comes down.
  Three stacked panes of the system's material, arriving one after another, so
  the radius genuinely compounds rather than a single pane fading in, which
  reads as dimming. Nothing is captured and no Screen Recording permission is
  involved. Clamshell is respected: an external monitor is never covered.
- **Real Liquid Glass.** The panel uses `glassEffect` with a macOS 26 check, and
  the widget cards now take clear glass behind their content. Regular glass was
  what smeared them before; clear refracts instead of frosting.
- **Automation.** Ten triggers, six actions, no shell. See README.
- **Lid lines.** The greeting and the farewell are fields in Appearance, empty
  by default and falling back to the time of day.

## Known gaps

- **Face Unlock has never run against a real face.** Nine-pose enrollment, the
  Keychain `userPresence` prompt and the matching threshold are proven only in
  unit tests. This is the largest untested area in the app.
- **Automation has not been seen firing on a real event.** The engine is
  covered by tests and the settings page builds, but no rule has been watched
  running against a real charger, lid or application event, and the settings
  page has not been looked at on screen.
- Charger and battery-low island events have never been triggered with a real
  cable; the track-change event has never been seen live.
- Brightness never had a producer, so the dead `IslandEvent` branch for it was
  removed. MacB shows nothing for brightness, and while the volume HUD
  suppression is on, macOS shows nothing either. The settings copy says so.
- Untested: very long text, empty data, external and mixed-scale displays,
  sleep/wake, permission revocation mid-session.
- Nothing has been pushed to `origin`.

## Manual checks worth doing

Close and open the lid and watch the fold and the blur. Switch a rule on and
let it fire. Complete face enrollment. Then Finder, Safari, Terminal and
Spotify with duplicate window titles, minimized windows, Space changes,
permission denial, canceled drags, sleep/wake and a second display.
