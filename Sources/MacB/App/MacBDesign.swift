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
        static let widgetFill = Color.white.opacity(0.085)
        static let widgetActiveFill = Color.white.opacity(0.13)
        static let widgetStroke = Color.white.opacity(0.08)
        static let navButton: CGFloat = 26
        static let navFill = Color.white.opacity(0.10)
        static let navSelectedFill = Color.white
        static let pillHeight: CGFloat = 28
        static let dropCardRadius: CGFloat = 20
        static let dropCardFill = Color.white.opacity(0.03)
        static let dropCardStroke = Color.white.opacity(0.22)
        static let destructive = Color(nsColor: .systemRed)
        static let primaryText = Color.white
        static let secondaryText = Color.white.opacity(0.55)
        static let tertiaryText = Color.white.opacity(0.35)
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
        static let glassHighlight = Color.white.opacity(0.085)
        static let glassStroke = Color.white.opacity(0.13)
    }
}
