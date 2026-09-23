import CoreGraphics
import Foundation

/// A widget living on the desktop rather than in the island.
///
/// The same widgets the island offers, in Apple's three widget sizes, placed
/// where the user drops them. Position is kept as a fraction of the screen so
/// a widget put in the top right corner is still in the top right corner on
/// another display, or after the resolution changes.
public struct DesktopWidget: Identifiable, Codable, Equatable, Sendable {
    public enum Size: String, Codable, CaseIterable, Sendable {
        case small, medium, large

        public var title: String {
            switch self {
            case .small: return "Küçük"
            case .medium: return "Orta"
            case .large: return "Büyük"
            }
        }

        /// Apple's own widget proportions: a square, two squares side by side,
        /// and a big square.
        public var size: CGSize {
            switch self {
            case .small: return CGSize(width: 170, height: 170)
            case .medium: return CGSize(width: 364, height: 170)
            case .large: return CGSize(width: 364, height: 364)
            }
        }
    }

    public var id: UUID
    public var kind: IslandWidgetKind
    public var size: Size
    /// Where the widget's top-left corner sits, as a fraction of the screen.
    public var x: Double
    public var y: Double

    public init(id: UUID = UUID(), kind: IslandWidgetKind, size: Size = .small, x: Double = 0.04, y: Double = 0.08) {
        self.id = id
        self.kind = kind
        self.size = size
        self.x = x
        self.y = y
    }

    /// The frame for this widget on a screen of `screen`, in AppKit
    /// coordinates (origin at the bottom left), always fully on screen.
    public func frame(on screen: CGRect) -> CGRect {
        let size = size.size
        let maxX = max(screen.minX, screen.maxX - size.width)
        let maxY = max(screen.minY, screen.maxY - size.height)
        let left = screen.minX + (screen.width - size.width) * clamp(x)
        let top = screen.minY + (screen.height - size.height) * clamp(1 - y)
        return CGRect(x: min(max(screen.minX, left), maxX),
                      y: min(max(screen.minY, top), maxY),
                      width: size.width, height: size.height)
    }

    /// The fractions a frame on `screen` corresponds to, for saving a drag.
    public static func position(of frame: CGRect, on screen: CGRect) -> (x: Double, y: Double) {
        let horizontal = screen.width - frame.width
        let vertical = screen.height - frame.height
        let x = horizontal > 0 ? (frame.minX - screen.minX) / horizontal : 0
        let y = vertical > 0 ? 1 - (frame.minY - screen.minY) / vertical : 0
        return (min(1, max(0, x)), min(1, max(0, y)))
    }

    private func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

/// Everything on the desktop, in the order it was added.
public struct DesktopWidgetLayout: Codable, Equatable, Sendable {
    public var widgets: [DesktopWidget]

    public init(widgets: [DesktopWidget] = []) { self.widgets = widgets }

    /// Where a new widget of `size` should land: down the left edge, below
    /// whatever is already there, so nothing is ever added underneath
    /// something else.
    public func nextPosition(for size: DesktopWidget.Size) -> (x: Double, y: Double) {
        let column = widgets.filter { abs($0.x - 0.04) < 0.001 }
        let y = 0.08 + Double(column.count) * 0.22
        return y > 0.85 ? (0.2, 0.08) : (0.04, y)
    }

    /// The widgets the desktop can show. The island's own strip has a couple
    /// that only make sense inside it.
    public static let offered: [IslandWidgetKind] = [
        .media, .systemStats, .battery, .storage, .weather, .calendar, .worldClock,
        .notes, .tasks, .timer, .shelf, .recentFiles, .quickLaunch, .topProcesses,
        .clipboard, .assistantActivity, .watchers
    ]

    /// The size a kind reads best at when it is first added.
    public static func defaultSize(for kind: IslandWidgetKind) -> DesktopWidget.Size {
        switch kind {
        case .battery, .storage, .worldClock, .timer, .calendar: return .small
        case .topProcesses, .tasks, .recentFiles, .watchers, .clipboard: return .large
        default: return .medium
        }
    }
}
