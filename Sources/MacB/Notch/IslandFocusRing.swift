import SwiftUI

/// A visible ring around whatever the keyboard is currently on.
///
/// Every control in the island is a plain button, and a plain button draws no
/// focus ring at all, so the island was reachable by Tab and impossible to
/// follow: the focus was somewhere, and nothing on screen said where. The ring
/// is drawn outside the control rather than inside it so it never eats into the
/// control's own fill, and it takes the island accent rather than the system
/// focus colour, which is tuned for light windows and disappears on black.
///
/// Tab only walks buttons when Keyboard navigation is switched on in System
/// Settings, which is the system's decision to make, not MacB's. The ring
/// simply shows the focus wherever the system puts it.
extension View {
    func islandFocusRing<S: InsettableShape>(in shape: S) -> some View {
        modifier(IslandFocusRing(shape: shape))
    }
}

struct IslandFocusRing<S: InsettableShape>: ViewModifier {
    let shape: S
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            // The system ring is suppressed so there is only ever one, and it
            // is the one that reads on a black surface.
            .focusEffectDisabled()
            .overlay(
                shape.strokeBorder(MacBDesign.IslandToken.accent, lineWidth: 2)
                    .padding(-3)
                    .opacity(focused ? 1 : 0)
            )
            .motion(MacBDesign.Motion.instant, value: focused)
    }
}
