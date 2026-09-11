import Foundation

/// How far the island has folded, derived from the hinge angle.
///
/// The screen stays lit while the lid is closing and only goes dark at the very
/// end, so there is a real window in which a fold can be seen. Everything here
/// is arithmetic on an angle: no hardware, no timers, so the thresholds that
/// decide when the island folds are provable in the test runner.
public enum LidFold {
    /// Where the fold starts unless the user says otherwise.
    ///
    /// Late on purpose. Past sixty degrees the screen is already hard to read
    /// from a normal seat, so this is the point where the lid is clearly being
    /// shut rather than merely tilted, and the fold does not fire while someone
    /// is adjusting the angle to cut a reflection.
    public static let defaultOpenAngle: Double = 60
    public static let minimumOpenAngle: Double = 20
    public static let maximumOpenAngle: Double = 110

    /// A reading this low means the lid is shut and the screen is gone.
    public static let closedAngle: Double = 6
    /// Where the fold finishes when there is room for it.
    ///
    /// It has to complete before macOS cuts the display, or the last and most
    /// dramatic frames are never seen by anybody.
    private static let completionAngle: Double = 14
    /// The narrowest the fold is ever allowed to be, so a low starting angle
    /// still animates over something rather than snapping shut.
    private static let minimumTravel: Double = 6

    public static func clampOpenAngle(_ value: Double) -> Double {
        min(maximumOpenAngle, max(minimumOpenAngle, value))
    }

    /// The angle at which the fold is complete, given where it starts.
    public static func foldedAngle(openAngle: Double) -> Double {
        min(completionAngle, clampOpenAngle(openAngle) - minimumTravel)
    }

    /// 0 while the lid is open, 1 when it is folded away.
    ///
    /// Straight-line in the angle, so every degree of hinge adds the same amount
    /// of fold. An eased curve looks better in isolation and worse on a hinge:
    /// the hand turning it expects the picture to follow it exactly.
    public static func progress(forAngle angle: Double,
                                openAngle: Double = defaultOpenAngle) -> Double {
        let start = clampOpenAngle(openAngle)
        let end = foldedAngle(openAngle: start)
        guard angle < start else { return 0 }
        guard angle > end else { return 1 }
        return (start - angle) / (start - end)
    }

    public static func isClosed(angle: Double) -> Bool { angle <= closedAngle }
}

/// Watches a stream of hinge readings and says when something happened.
///
/// A raw angle is noisy and a MacBook lid wobbles while you type, so an opening
/// is only reported after the lid has genuinely been near-shut and then come
/// back up past the angle where the fold begins. One event per real open, never
/// per wobble.
public struct LidFoldTracker: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case none
        /// The lid just went past the point where the fold begins, on the way down.
        case folding
        /// The lid was shut and has now been opened far enough to greet.
        case opened
    }

    public private(set) var openAngle: Double
    /// Set once the lid has been seen low enough to count as shut.
    private var wasClosed = false
    /// Set while the fold is on screen, so folding is reported once per close.
    private var wasFolding = false
    public private(set) var angle: Double?

    public init(openAngle: Double = LidFold.defaultOpenAngle) {
        self.openAngle = LidFold.clampOpenAngle(openAngle)
    }

    public mutating func setOpenAngle(_ value: Double) {
        openAngle = LidFold.clampOpenAngle(value)
    }

    public var progress: Double {
        angle.map { LidFold.progress(forAngle: $0, openAngle: openAngle) } ?? 0
    }

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

        if wasClosed, reading >= openAngle {
            wasClosed = false
            wasFolding = false
            return .opened
        }

        let folding = reading < openAngle
        if folding, !wasFolding, !wasClosed {
            wasFolding = true
            return .folding
        }
        if !folding { wasFolding = false }
        return .none
    }
}

/// How strongly the screen behind the island is blurred as the lid comes down.
///
/// The system's blur has one fixed radius and no dial. Raising a single pane's
/// opacity does not deepen it, it only mixes a blurred copy over a sharp one,
/// which the eye reads as dimming rather than blurring: the text stays legible
/// until the sharp copy is almost gone, then everything vanishes at once.
///
/// So the radius is grown by stacking. A pane blurs whatever the window server
/// has already drawn behind it, including an earlier pane, so a second pane
/// blurs an already blurred picture and the radius genuinely compounds. The
/// panes arrive one after another instead of together, and each one finishes
/// before the next begins to matter, so every stretch of the fold has its own
/// visible step of blur rather than all of them landing at the end.
///
/// They do darken as they stack, which is why the order matters: the screen is
/// only near black in the last few degrees, where the lid is about to make it
/// black anyway.
public enum LidScreenBlur {
    /// Where each pane starts and finishes arriving, in fold progress.
    private static let ramps: [(start: Double, end: Double)] = [
        (0.00, 0.34), (0.30, 0.67), (0.62, 0.95)
    ]

    public static var layerCount: Int { ramps.count }

    /// 0 while a pane is not wanted yet, 1 once it has fully arrived.
    public static func layerAlpha(_ index: Int, progress: Double) -> Double {
        guard ramps.indices.contains(index) else { return 0 }
        let ramp = ramps[index]
        guard progress > ramp.start else { return 0 }
        guard progress < ramp.end else { return 1 }
        return (progress - ramp.start) / (ramp.end - ramp.start)
    }

    /// How blurred the screen is overall, 0 to 1, so the shape of the ramps can
    /// be proven to keep climbing and to be busy at every stage of the fold.
    public static func strength(progress: Double) -> Double {
        ramps.indices.reduce(0.0) { $0 + layerAlpha($1, progress: progress) } / Double(ramps.count)
    }
}
