# MacB Design Language

MacB should feel like a focused macOS utility. Apple Human Interface Guidelines are the canonical reference. `macos_ui` is a visual reference for desktop hierarchy and `awesome-design-md` is a reference for documenting design decisions; neither defines MacB's native SwiftUI components.

## Foundations

- Use the system font, SF Symbols, semantic colors, native controls, and system materials.
- Follow the user's appearance, accent color, Increase Contrast, Reduce Transparency, and Reduce Motion settings.
- Use color for focus, selection, status, and destructive actions. Do not use decorative accent color.
- Keep transient surfaces compact. Show the selected window first and make secondary information quiet.
- The physical notch surface may remain pure black so it joins the camera housing. Other panels follow the system appearance.

## Geometry and rhythm

- Spacing: 4, 8, 12, 16, and 24 pt.
- Floating panel radius: 18 pt.
- Content card radius: 12 pt.
- Control and thumbnail radius: 8 pt.
- Panel outlines use `separatorColor`; keyboard selection uses `keyboardFocusIndicatorColor` and `selectedContentBackgroundColor`.

## The island scale

The island hangs from the hardware notch instead of sitting in a window, so it keeps its own
scale rather than inheriting the window radii and the system appearance. It is always dark.

- Widget card radius: 18 pt. Drop-target card radius: 20 pt. Navigation buttons: 26 pt circles.
- Widget grid: a small widget is one unit, medium two, wide four. A unit is at least 76 pt.
  Every widget in the strip shares one height (100 pt); size changes width only.
- Widget library: the edit button opens a shelf under the strip. Widgets are grouped into
  Öne çıkanlar, Çalışma, Sistem and Yaşam, and a card added there lands at the end of the
  strip at its intended width. A one-unit card collapses its three size letters into one
  menu, because four round buttons are wider than the card itself.
- Grid gap and panel padding: 12 pt and 20 pt.
- The main panel measures its visible cards and grows with them. Eighty-two percent of the
  display is a ceiling, never a default width. Empty sections collapse to navigation plus their
  single action or status row; they never reserve an empty black canvas.
- Orange (`systemOrange`) is the island's single accent. It marks running timers and the primary
  action, never decoration. Red (`systemRed`) is reserved for clearing and deleting.
- Card fills are white at 6% on black, 13% while the widget is active. Text steps down through
  white, 55% and 35%.
- A selected filter pill inverts to a white fill with black text; unselected pills are white at 10%.

## Motion and accessibility

- Opening uses 280 ms and closing uses 220 ms when motion is enabled.
- Selection changes use a short 130 ms ease-out transition.
- Reduce Motion removes spatial transitions. Reduce Transparency replaces materials with `windowBackgroundColor`.
- Every icon-only control needs a help label and accessibility label. Selection cannot rely on color alone.

## Surface rules

- Switcher: regular material, system shadow, four compact cards, one visible selection ring.
- Dock previews: the screenshot is primary; window actions appear on hover or keyboard focus.
- Settings: native sidebar hierarchy, semantic labels and controls.
- Notch: invisible while collapsed; black island only while content is visible.
