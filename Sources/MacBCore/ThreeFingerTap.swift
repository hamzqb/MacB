import Foundation

/// Recognises a three-finger tap from nothing but a count of fingers over time.
///
/// The trackpad reports how many contacts it can see, many times a second, and
/// that alone is enough to tell a tap from everything else it has to be told
/// apart from. A tap is short and it is exactly three: a two-finger click is not
/// three, a four-finger pinch peaks at four, a swipe with three fingers lasts
/// far longer than a tap does, and resting a palm never reaches zero cleanly.
///
/// Counting rather than tracking positions is deliberate. Reading the contact
/// positions would mean knowing the private frame struct's exact layout, and a
/// wrong guess there reads whatever happens to be next in memory. The finger
/// count is an argument to the callback, a plain integer, and cannot be
/// misread.
///
/// The whole gesture is judged from the moment the first finger lands to the
/// moment the last one leaves, so somebody whose three fingers do not land on
/// the same millisecond is still tapping.
public struct ThreeFingerTap: Equatable, Sendable {
    /// Exactly this many, at the busiest moment of the gesture.
    public static let fingerCount = 3
    /// The longest a tap may last, first finger down to last finger up.
    ///
    /// A deliberate tap is well under this. A three-finger swipe, which macOS
    /// itself uses for spaces and Mission Control, is not — that is the gesture
    /// this most has to stay out of the way of.
    public static let maximumDuration: Double = 0.3

    private var firstContact: Double?
    private var peak = 0

    public init() {}

    /// One frame from the trackpad. Returns true when a tap has just finished.
    public mutating func frame(fingers: Int, at time: Double) -> Bool {
        guard fingers > 0 else {
            guard let started = firstContact else { return false }
            let held = time - started
            let wasTap = peak == Self.fingerCount && held <= Self.maximumDuration
            firstContact = nil
            peak = 0
            return wasTap
        }
        if firstContact == nil { firstContact = time }
        peak = max(peak, fingers)
        // A gesture that has already outstayed a tap is abandoned where it is,
        // rather than firing late when the fingers finally come off.
        if let started = firstContact, time - started > Self.maximumDuration {
            peak = 0
        }
        return false
    }

    /// Forgets whatever was in progress, for when the trackpad goes away.
    public mutating func reset() {
        firstContact = nil
        peak = 0
    }
}
