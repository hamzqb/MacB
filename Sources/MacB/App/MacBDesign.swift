import SwiftUI

/// Shared visual rhythm for the settings window and floating panels.
enum MacBDesign {
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let accent = Color(nsColor: .controlAccentColor)
    static let corner: CGFloat = 18
    static let openDuration: Double = 0.28
    static let closeDuration: Double = 0.22
    static let contentSpacing: CGFloat = 28
    static let sidebarWidth: CGFloat = 164

    enum Island {
        static let expandedWidth: CGFloat = 420
        static let glanceWidth: CGFloat = 344
        static let glanceBodyHeight: CGFloat = 74
        static let mediaBodyHeight: CGFloat = 226
        static let emptyMediaBodyHeight: CGFloat = 150
        static let filesEmptyBodyHeight: CGFloat = 170
        static let utilityBodyHeight: CGFloat = 276
        static let cornerRadius: CGFloat = 24
        static let horizontalPadding: CGFloat = 20
        static let contentSpacing: CGFloat = 12
        static let tabHeight: CGFloat = 28
        static let heroArtwork: CGFloat = 58
    }
}
