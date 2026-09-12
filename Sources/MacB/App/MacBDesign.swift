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
