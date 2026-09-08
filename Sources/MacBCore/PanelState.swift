import Foundation

public enum NotchPhase: String, Equatable { case collapsed, glance, expanded }
public enum NotchContent: String, Equatable { case music, files, commands }

/// Interaction policy is independent of rendering and of animation progress.
public struct PanelState: Equatable {
    public private(set) var phase: NotchPhase = .collapsed
    public private(set) var content: NotchContent = .music
    public var isOpen: Bool { phase != .collapsed }
    public private(set) var isDragging = false
    public private(set) var hasKeyboardFocus = false
    public private(set) var closeDeadline: TimeInterval?
    public private(set) var hoverDeadline: TimeInterval?
    public init() {}

    public mutating func open() { phase = .expanded; closeDeadline = nil; hoverDeadline = nil }
    public mutating func glance() { if phase == .collapsed { phase = .glance }; closeDeadline = nil; hoverDeadline = nil }
    public mutating func select(_ content: NotchContent) { self.content = content; open() }
    public mutating func setDragging(_ value: Bool) {
        isDragging = value
        if value { select(.files) }
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
        if let deadline = hoverDeadline, now >= deadline { glance() }
        guard !isDragging, !hasKeyboardFocus, let deadline = closeDeadline, now >= deadline else { return }
        close()
    }
    public mutating func close() {
        phase = .collapsed; content = .music
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
