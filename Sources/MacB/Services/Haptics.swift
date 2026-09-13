import AppKit

/// The small taps a Force Touch trackpad can give back.
///
/// Dragging a file onto a target is the one place in MacB where the pointer is
/// carrying something and the eyes are on the file rather than on the target.
/// A tap says "this one" without asking anybody to look.
///
/// Nothing here is required for anything to work, and a Mac without a Force
/// Touch trackpad simply feels nothing: the system performer is a no-op there,
/// so there is no hardware check to get wrong.
enum Haptics {
    /// The pointer has arrived over something that will accept the drop.
    ///
    /// `.alignment` is the lightest of the three, and it is what macOS itself
    /// uses when a dragged object snaps to a guide, which is the same idea.
    static func targetEntered() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Something has actually been taken: a file dropped, a shelf item accepted.
    static func accepted() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
    }
}
