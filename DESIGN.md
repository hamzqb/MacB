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
