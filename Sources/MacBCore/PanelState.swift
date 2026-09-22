import Foundation

public enum NotchPhase: String, Equatable { case collapsed, peek, expanded }

/// Sections reachable from the icon navigation, in display order.
public enum NotchContent: String, Equatable, CaseIterable {
    /// The player, large, the way Atoll opens.
    case home
    /// The editable widget strip that used to be home.
    case widgets
    case files
    case timer
    /// CPU, memory, GPU, network and disk as running lines.
    case stats
    case clipboard
    case apps
    /// The voice assistant. Not a tab: it appears while a conversation is
    /// running and the island goes back to where it was afterwards.
    case assistant
    /// The morning briefing. Also not a tab: it shows up once, is read, and
    /// goes away.
    case briefing
    /// What a background job found while nobody was here. Also not a tab: it
    /// arrives once, is answered, and goes.
    case agent

    /// The section a drop or an explicit close returns to.
    public static let `default` = NotchContent.home

    /// The sections the navigation offers on its left.
    public static let tabs: [NotchContent] = [.home, .widgets, .files, .timer, .stats]
    /// Sections that sit with the tools on the right.
    public static let toolTabs: [NotchContent] = [.clipboard, .apps]
}

/// Interaction policy is independent of rendering and of animation progress.
public struct PanelState: Equatable {
    public private(set) var phase: NotchPhase = .collapsed
    public private(set) var content: NotchContent = .default
    public var isOpen: Bool { phase != .collapsed }
    public private(set) var isDragging = false
    public private(set) var hasKeyboardFocus = false
    public private(set) var closeDeadline: TimeInterval?
    public private(set) var hoverDeadline: TimeInterval?
    public init() {}

    public mutating func open() { phase = .expanded; closeDeadline = nil; hoverDeadline = nil }
    public mutating func peek() { if phase == .collapsed { phase = .peek }; closeDeadline = nil; hoverDeadline = nil }
    public mutating func select(_ content: NotchContent) { self.content = content; open() }
    public mutating func setDragging(_ value: Bool) {
        isDragging = value
        if value { open() }
    }
    public mutating func setKeyboardFocus(_ value: Bool) {
        hasKeyboardFocus = value
        if value { open() }
    }
    public mutating func pointerExited(at now: TimeInterval, delay: TimeInterval = 0.3) {
        hoverDeadline = nil
        closeDeadline = now + delay
    }
    public mutating func pointerEntered(at now: TimeInterval? = nil) {
        closeDeadline = nil
        if phase == .collapsed, hoverDeadline == nil, let now { hoverDeadline = now + 0.18 }
    }
    public mutating func tick(at now: TimeInterval) {
        if let deadline = hoverDeadline, now >= deadline { peek() }
        guard !isDragging, !hasKeyboardFocus, let deadline = closeDeadline, now >= deadline else { return }
        close()
    }
    public mutating func close() {
        phase = .collapsed; content = .default
        isDragging = false; hasKeyboardFocus = false
        closeDeadline = nil; hoverDeadline = nil
    }
}

public enum MorphTiming {
    /// Small overshoot; exact endpoints let interrupted transitions rebase on the current frame.
    public static func progress(_ fraction: Double) -> Double {
        let t = max(0, min(1, fraction))
        if t == 0 || t == 1 { return t }
        func spring(_ x: Double) -> Double { 1 - exp(-7 * x) * (cos(9 * x) + (7.0 / 9.0) * sin(9 * x)) }
        return spring(t) / spring(1)
    }
}
