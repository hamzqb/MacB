import SwiftUI

/// Shared visual rhythm for the settings window and floating panels.
enum MacBDesign {
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let accent = Color(nsColor: .controlAccentColor)
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

    enum Island {
        static let expandedWidth: CGFloat = 420
        static let glanceWidth: CGFloat = 344
        static let glanceBodyHeight: CGFloat = 74
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
