import SwiftUI

/// Shared visual rhythm for the settings window and floating panels.
enum MacBDesign {
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    /// One accent for the whole product. The island is orange, so the settings
    /// window is too; inheriting the system accent made the two halves of MacB
    /// look like two applications.
    static let accent = Color(nsColor: .systemOrange)
    static let cardFill = Color.primary.opacity(0.04)
    static let cardStroke = Color.primary.opacity(0.06)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let selectedBackground = Color(nsColor: .selectedContentBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let focusRing = Color(nsColor: .keyboardFocusIndicatorColor)
    static let corner: CGFloat = 18
    static let openDuration: Double = 0.28
    static let closeDuration: Double = 0.22
    static let contentSpacing: CGFloat = 28
    static let sidebarWidth: CGFloat = 164

    /// Every animation in MacB, on one scale.
    ///
    /// There were twenty-one hand-written curves in here, no two of them
    /// agreeing: a highlight moved in 0.13 in one view and 0.16 in the next,
    /// and a colour faded in 0.45 in one card and 0.5 in another. Nobody can
    /// see the difference in isolation, but side by side the interface reads as
    /// several interfaces. Naming the intent instead of the number is the only
    /// way two views written a year apart move like one thing.
    enum Motion {
        /// Follows the hand: a hinge angle, a dragged value. Anything slower
        /// than this reads as the picture lagging behind the finger.
        static let tracking = Animation.easeOut(duration: 0.09)
        /// A highlight moving, a level stepping. Meant to read as immediate.
        static let instant = Animation.easeOut(duration: 0.13)
        /// Something arriving or leaving: a toast, a card, a scroll.
        static let quick = Animation.easeOut(duration: 0.18)
        /// A value settling into its new place.
        static let normal = Animation.easeOut(duration: 0.28)
        /// A change of mood: a colour taken from artwork, a glow coming up.
        static let gentle = Animation.easeOut(duration: 0.5)
        /// A control answering a hover or a press.
        static let snap = Animation.spring(response: 0.28, dampingFraction: 0.72)
        /// Something arriving into position with a little weight behind it.
        static let settle = Animation.spring(response: 0.40, dampingFraction: 0.80)
        /// The two halves of a refusal: thrown out hard, brought back settled.
        static let rejectOut = Animation.spring(response: 0.12, dampingFraction: 0.25)
        static let rejectBack = Animation.spring(response: 0.22, dampingFraction: 0.4)
        /// A bar that must never overshoot the number it is reporting.
        static let progress = Animation.linear(duration: 0.25)
        /// A pulse that does not stop, for a scan or a wait.
        static func breathe(_ duration: Double = 1.1) -> Animation {
            .easeInOut(duration: duration).repeatForever(autoreverses: true)
        }
    }

    /// Every text size in MacB, on one scale.
    ///
    /// There were twenty-four of them, from 8 to 46, with 10 and 11 both in
    /// heavy use for the same job and no rule saying which. Nine steps named
    /// after what they are for is enough for a menu-bar app, and a fixed set is
    /// what stops two labels that mean the same thing being drawn a point
    /// apart.
    enum TypeScale {
        /// Badges, pill counters, the smallest thing still worth reading.
        static let micro: CGFloat = 10
        /// A second line under a label: detail, hint, timestamp.
        static let caption: CGFloat = 11
        /// Ordinary label text. The default when nothing says otherwise.
        static let body: CGFloat = 12
        /// The title of a row or a card, set against its own caption.
        static let emphasis: CGFloat = 13
        /// A section heading, or a glyph standing in for one.
        static let title: CGFloat = 16
        /// The name of a window or a page.
        static let heading: CGFloat = 21
        /// A page title, or one number that is the whole point of a card.
        static let display: CGFloat = 26
        /// A single glyph carrying a whole empty state.
        static let hero: CGFloat = 34
        /// The one number somebody reads from across the room.
        static let giant: CGFloat = 44
    }

    /// Every gap in MacB, on one scale.
    ///
    /// The old values were a smear: every whole number from zero to sixteen was
    /// in use, with 5, 6 and 7 all doing the same job in neighbouring views.
    /// None of it was decided; it accumulated. These steps are, and a gap that
    /// is not one of them now has to justify itself.
    enum Space {
        /// Touching, but not quite.
        static let hair: CGFloat = 2
        /// Between a glyph and its own label.
        static let tight: CGFloat = 4
        /// Between two lines of the same thought.
        static let snug: CGFloat = 6
        /// The ordinary gap between controls in a row.
        static let close: CGFloat = 8
        /// Between a row and the next row.
        static let regular: CGFloat = 10
        /// Inside a card, from its edge to its content.
        static let comfortable: CGFloat = 12
        /// Between two cards.
        static let loose: CGFloat = 16
        /// Between a heading and what it heads.
        static let section: CGFloat = 20
        /// Between one section and the next.
        static let wide: CGFloat = 24
        /// The margin of a page.
        static let page: CGFloat = 32
    }

    enum Radius {
        static let panel: CGFloat = 18
        static let card: CGFloat = 12
        static let control: CGFloat = 8
    }

    /// Tokens for the black island surface. The island is deliberately its own scale:
    /// it sits on the hardware notch rather than in a window, so it does not inherit
    /// the window radii or the system appearance.
    enum IslandToken {
        static let accent = Color(nsColor: .systemOrange)
        static let widgetRadius: CGFloat = 18
        static let widgetFill = Fill.low
        static let widgetActiveFill = Fill.raised
        static let widgetStroke = Fill.low
        static let navButton: CGFloat = 26
        static let navFill = Fill.base
        static let navSelectedFill = Color.white
        static let pillHeight: CGFloat = 28
        static let dropCardRadius: CGFloat = 20
        static let dropCardFill = Fill.hairline
        static let dropCardStroke = Fill.strong
        static let destructive = Color(nsColor: .systemRed)
        static let primaryText = Color.white
        static let secondaryText = Ink.secondary
        static let tertiaryText = Ink.faint

        /// Every surface the island lays over its own black, on one scale.
        ///
        /// There were twenty-five different white opacities in here, all within
        /// a hair of each other and none of them agreeing. Five steps is enough
        /// to say rest, quiet, normal, hovered and pressed, and a fixed set is
        /// the only way two cards drawn a year apart look like one material.
        enum Fill {
            /// Hairlines, separators, the calmest resting surface.
            static let hairline = Color.white.opacity(0.04)
            /// A surface that should be felt rather than seen.
            static let low = Color.white.opacity(0.07)
            /// The ordinary fill for a card or a control.
            static let base = Color.white.opacity(0.10)
            /// Hovered, selected, or carrying something live.
            static let raised = Color.white.opacity(0.14)
            /// Pressed, or an edge that has to read against artwork.
            static let strong = Color.white.opacity(0.20)
        }

        /// Text and glyphs, four steps, brightest first.
        enum Ink {
            static let primary = Color.white.opacity(0.82)
            static let secondary = Color.white.opacity(0.55)
            static let tertiary = Color.white.opacity(0.42)
            static let faint = Color.white.opacity(0.32)
        }
    }

    enum Island {
        static let expandedWidth: CGFloat = 420
        static let mediaBodyHeight: CGFloat = 226
        static let emptyMediaBodyHeight: CGFloat = 150
        static let filesEmptyBodyHeight: CGFloat = 170
        static let clipboardEmptyBodyHeight: CGFloat = 132
        static let tasksEmptyBodyHeight: CGFloat = 174
        static let utilityBodyHeight: CGFloat = 276
        static let cornerRadius: CGFloat = 24
        static let horizontalPadding: CGFloat = 20
        static let contentSpacing: CGFloat = 12
        static let tabHeight: CGFloat = 34
        static let heroArtwork: CGFloat = 58
        static let glassHighlight = IslandToken.Fill.low
        static let glassStroke = IslandToken.Fill.raised
    }
}

/// Applies one of the motion tokens, and nothing at all when the system asks
/// for less motion.
///
/// Reduce Motion was honoured in two views out of twenty-one, because every
/// call site had to remember to check it. Going through here means a view
/// cannot animate without respecting the setting.
extension View {
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
