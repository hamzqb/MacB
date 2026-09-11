import Foundation

/// How far the island has folded, derived from the hinge angle.
///
/// The screen stays lit while the lid is closing and only goes dark at the very
/// end, so there is a real window in which a fold can be seen. Everything here
/// is arithmetic on an angle: no hardware, no timers, so the thresholds that
/// decide when the island folds are provable in the test runner.
public enum LidFold {
    /// Above this the lid is simply open and nothing happens.
    public static let openAngle: Double = 80
    /// At and below this the island is fully folded away.
    public static let foldedAngle: Double = 12
    /// A reading this low means the lid is shut and the screen is gone.
    public static let closedAngle: Double = 6
    /// The lid has to pass this on the way up before an opening counts, so a
    /// hand resting on the screen cannot trigger the greeting over and over.
    public static let greetingAngle: Double = 45

    /// 0 while the lid is open, 1 when it is folded away.
    public static func progress(forAngle angle: Double) -> Double {
        guard angle < openAngle else { return 0 }
        guard angle > foldedAngle else { return 1 }
        return (openAngle - angle) / (openAngle - foldedAngle)
    }

    public static func isClosed(angle: Double) -> Bool { angle <= closedAngle }
}

/// Watches a stream of hinge readings and says when something happened.
///
/// A raw angle is noisy and a MacBook lid wobbles while you type, so an opening
/// is only reported after the lid has genuinely been near-shut and then come
/// back up past a much higher angle. One event per real open, never per wobble.
public struct LidFoldTracker: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case none
        /// The lid just went past the point where the fold begins, on the way down.
        case folding
        /// The lid was shut and has now been opened far enough to greet.
        case opened
    }

    /// Set once the lid has been seen low enough to count as shut.
    private var wasClosed = false
    /// Set while the fold is on screen, so folding is reported once per close.
    private var wasFolding = false
    public private(set) var angle: Double?

    public init() {}

    public var progress: Double { angle.map(LidFold.progress(forAngle:)) ?? 0 }

    public mutating func update(angle reading: Double?) -> Event {
        guard let reading else {
            // The sensor stopped answering. Nothing is known, so nothing folds,
            // but what was known is kept: a lid shut a moment ago is still shut.
            angle = nil
            return .none
        }
        angle = reading

        if LidFold.isClosed(angle: reading) {
            wasClosed = true
            wasFolding = false
            return .none
        }

        if wasClosed, reading >= LidFold.greetingAngle {
            wasClosed = false
            wasFolding = false
            return .opened
        }

        let folding = reading < LidFold.openAngle
        if folding, !wasFolding, !wasClosed {
            wasFolding = true
            return .folding
        }
        if !folding { wasFolding = false }
        return .none
    }
}
