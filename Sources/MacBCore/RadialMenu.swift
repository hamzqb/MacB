import Foundation

/// One thing a slice of the ring can do.
///
/// Deliberately a closed list rather than "run this shell command". A ring that
/// appears under the cursor on a gesture is the easiest thing in the app to fire
/// by accident, so everything on it has to be something a stray flick can do
/// without consequence — open a panel, move a window, start a timer. Nothing
/// here deletes, sends, installs or authenticates.
public enum RadialAction: String, CaseIterable, Codable, Sendable {
    case island
    case shelf
    case clipboard
    case switcher
    case timer
    case quickNote
    case askAI
    case jarvis
    case voiceAsk
    case summarizeSelection
    case fixSelection
    case translateSelection
    case keepAwake
    case applyArrangement
    case keyboardLock
    case windowLeft
    case windowRight
    case windowMaximize
    case windowCenter
    case windowNextDisplay
    case settings

    public var title: String {
        switch self {
        case .island: return "Island"
        case .shelf: return "Raf"
        case .clipboard: return "Pano"
        case .switcher: return "Pencereler"
        case .timer: return "Zamanlayıcı"
        case .quickNote: return "Hızlı not"
        case .askAI: return "Yapay zekâ"
        case .jarvis: return "MacB ile konuş"
        case .voiceAsk: return "Sesle sor"
        case .summarizeSelection: return "Seçimi özetle"
        case .fixSelection: return "Seçimi düzelt"
        case .translateSelection: return "Seçimi çevir"
        case .keepAwake: return "Uyanık tut"
        case .applyArrangement: return "Pencere düzeni"
        case .keyboardLock: return "Klavye kilidi"
        case .windowLeft: return "Sol yarı"
        case .windowRight: return "Sağ yarı"
        case .windowMaximize: return "Büyüt"
        case .windowCenter: return "Ortala"
        case .windowNextDisplay: return "Sonraki ekran"
        case .settings: return "Ayarlar"
        }
    }

    public var symbol: String {
        switch self {
        case .island: return "capsule"
        case .shelf: return "tray.full"
        case .clipboard: return "doc.on.clipboard"
        case .switcher: return "square.on.square"
        case .timer: return "timer"
        case .quickNote: return "square.and.pencil"
        case .askAI: return "sparkles"
        case .jarvis: return "person.wave.2"
        case .voiceAsk: return "waveform"
        case .summarizeSelection: return "text.line.3.summary"
        case .fixSelection: return "text.badge.checkmark"
        case .translateSelection: return "translate"
        case .keepAwake: return "cup.and.heat.waves"
        case .applyArrangement: return "rectangle.3.group"
        case .keyboardLock: return "keyboard"
        case .windowLeft: return "rectangle.lefthalf.filled"
        case .windowRight: return "rectangle.righthalf.filled"
        case .windowMaximize: return "arrow.up.left.and.arrow.down.right"
        case .windowCenter: return "rectangle.center.inset.filled"
        case .windowNextDisplay: return "display.2"
        case .settings: return "gearshape"
        }
    }

    /// Whether this needs the Accessibility permission to do anything.
    ///
    /// Moving somebody else's window, reading the window list and reading the
    /// text selected in another application all do; the rest of the ring is
    /// MacB's own panels and needs nothing.
    public var requiresAccessibility: Bool {
        switch self {
        case .switcher, .windowLeft, .windowRight, .windowMaximize, .windowCenter, .windowNextDisplay,
             .summarizeSelection, .fixSelection, .translateSelection, .applyArrangement:
            return true
        case .island, .shelf, .clipboard, .timer, .quickNote, .askAI, .jarvis, .voiceAsk, .keepAwake,
             .keyboardLock, .settings:
            return false
        }
    }
}

/// What the ring is made of, and which slice a flick of the wrist picked.
///
/// Separated from the window entirely. Everything interesting about a radial
/// menu is arithmetic — where the slices start, how far the hand has to travel
/// before it counts, which way is up — and none of it should need a trackpad and
/// a pair of eyes to check.
public enum RadialMenuGeometry {
    /// How many slices the ring may carry.
    ///
    /// One is allowed, and it is a real answer rather than a degenerate case:
    /// a ring with a single slice is a gesture that does one thing, aimed in any
    /// direction, which is the fastest shortcut in the app. Past eight the
    /// slices are narrower than the wobble in a hand coming off a trackpad
    /// click, and nobody can hit them without looking.
    public static let minimumSlices = 1
    public static let maximumSlices = 8

    public static func clampSliceCount(_ count: Int) -> Int {
        min(maximumSlices, max(minimumSlices, count))
    }

    /// Which slice an offset from the centre points at, or nil for none.
    ///
    /// `dx` grows to the right and `dy` grows upwards, which is AppKit's screen
    /// orientation rather than a view's. Slice zero is straight up and the rest
    /// run clockwise, because that is the order they are read in.
    public static func slice(dx: Double, dy: Double, count: Int, deadZone: Double) -> Int? {
        let slices = clampSliceCount(count)
        guard (dx * dx + dy * dy).squareRoot() >= deadZone else { return nil }
        let step = 2 * Double.pi / Double(slices)
        // atan2(x, y) rather than the usual (y, x): this measures clockwise from
        // straight up instead of counter-clockwise from the right.
        var angle = atan2(dx, dy)
        if angle < 0 { angle += 2 * Double.pi }
        // Half a slice of rotation, so slice zero is centred on up rather than
        // starting there.
        let shifted = (angle + step / 2).truncatingRemainder(dividingBy: 2 * Double.pi)
        return min(slices - 1, Int(shifted / step))
    }

    /// The angle, clockwise from straight up in radians, at the middle of a slice.
    public static func midAngle(_ index: Int, count: Int) -> Double {
        Double(index) * 2 * Double.pi / Double(clampSliceCount(count))
    }

    /// Where the ring has to sit so all of it stays on screen.
    ///
    /// The gesture fires wherever the cursor happens to be, including hard
    /// against a corner, and a ring with two slices off the edge of the display
    /// is a ring with two slices nobody can reach.
    public static func origin(forCursor cursor: (x: Double, y: Double),
                              size: Double,
                              screen: (x: Double, y: Double, width: Double, height: Double),
                              margin: Double = 8) -> (x: Double, y: Double) {
        let half = size / 2
        let minX = screen.x + margin, maxX = screen.x + screen.width - size - margin
        let minY = screen.y + margin, maxY = screen.y + screen.height - size - margin
        return (x: min(max(cursor.x - half, minX), max(minX, maxX)),
                y: min(max(cursor.y - half, minY), max(minY, maxY)))
    }
}

/// How big the ring is drawn, on one dial.
///
/// Every radius comes off the same number so the proportions cannot drift: the
/// band keeps its thickness relative to the hole, and the dead zone keeps its
/// relationship to both. A ring where the hole grew and the band did not is a
/// ring whose slices are suddenly hard to hit.
///
/// Small by default, and the slider only goes so far. This appears under the
/// hand, mid-gesture, over whatever somebody was looking at, so every point of
/// radius is more of their work covered up.
public struct RadialMenuMetrics: Equatable, Sendable {
    public static let minimumScale: Double = 0.6
    public static let maximumScale: Double = 1.4
    /// The radii at scale 1, in points.
    private static let baseOuter: Double = 76
    private static let baseInner: Double = 34
    private static let baseDeadZone: Double = 24

    public let scale: Double

    public init(scale: Double = 1) {
        self.scale = min(Self.maximumScale, max(Self.minimumScale, scale))
    }

    public var outerRadius: Double { Self.baseOuter * scale }
    public var innerRadius: Double { Self.baseInner * scale }

    /// The hole in the middle.
    ///
    /// A gesture is a press and a flick, and the press lands before the flick
    /// does: without a dead zone the slice under the cursor at the instant of
    /// the click would fire on every single use. Inside this radius the ring is
    /// showing but has chosen nothing, which is also how somebody backs out —
    /// come back to the middle and let go.
    ///
    /// Kept inside the drawn hole rather than matching it, so a hand that has
    /// only just left the middle is already choosing something and can see
    /// which.
    public var deadZone: Double { Self.baseDeadZone * scale }

    /// The window's side, which is the ring plus nothing at all.
    public var side: Double { outerRadius * 2 }

    /// The size of the icon on a slice, which has to shrink with the band or it
    /// stops fitting inside it.
    public var symbolSize: Double { 15 * min(1.15, max(0.85, scale)) }
}

/// What one slice of the ring does: one of MacB's own actions, or opening an
/// application, folder or file the user picked.
///
/// Opening is the only thing a user-chosen slice can do. It is the same thing a
/// double-click in Finder does, so a slice cannot do anything the user could not
/// already do by hand, and nothing on the ring runs a command or a script.
public enum RadialSlot: Hashable, Codable, Sendable {
    case action(RadialAction)
    case open(path: String)

    public var requiresAccessibility: Bool {
        if case .action(let action) = self { return action.requiresAccessibility }
        return false
    }

    /// What the hub shows while this slice is chosen.
    public var title: String {
        switch self {
        case .action(let action): return action.title
        case .open(let path):
            let name = (path as NSString).lastPathComponent
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
    }
}

/// Which slice does what.
///
/// Stored as a plain list because the ring is a list: the order on screen is the
/// order here, clockwise from the top, and reordering is moving an element.
public struct RadialMenuLayout: Equatable, Codable, Sendable {
    public private(set) var slots: [RadialSlot]

    public static let `default` = RadialMenuLayout(actions: [
        .island, .clipboard, .shelf, .switcher
    ])

    private enum CodingKeys: String, CodingKey { case slots, actions }

    /// Decoding goes through the same validation as everything else, so a file
    /// edited by hand cannot produce a ring with twenty slices or none. A ring
    /// saved before slices could open things is read from its old shape rather
    /// than thrown away.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let slots = try container.decodeIfPresent([RadialSlot].self, forKey: .slots) {
            self.init(slots: slots)
        } else {
            self.init(actions: try container.decode([RadialAction].self, forKey: .actions))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slots, forKey: .slots)
    }

    public init(slots: [RadialSlot]) {
        let clamped = Array(slots.prefix(RadialMenuGeometry.maximumSlices))
        self.slots = clamped.isEmpty ? [.action(.island)] : clamped
    }

    public init(actions: [RadialAction]) {
        self.init(slots: actions.map(RadialSlot.action))
    }

    /// The slices that can actually run, in order.
    ///
    /// An unavailable slice is dropped rather than greyed out: a ring is aimed
    /// at by angle, and a dead slice that still takes up a sixth of the circle
    /// costs every other slice its position. Somebody who has not granted
    /// Accessibility gets a smaller ring, and an application that has since been
    /// deleted simply stops being on it.
    public func usableSlots(hasAccessibility: Bool,
                            exists: (String) -> Bool = { _ in true }) -> [RadialSlot] {
        let usable = slots.filter { slot in
            switch slot {
            case .action(let action): return hasAccessibility || !action.requiresAccessibility
            case .open(let path): return exists(path)
            }
        }
        return usable.isEmpty ? [.action(.island)] : usable
    }
}

/// One ring for everywhere, and optionally a different one per application.
///
/// The slices worth having in Finder are not the ones worth having in a
/// browser, and a ring that knows where it is saves a slice per app on the one
/// that does not. An application without a ring of its own gets the general
/// one, so setting nothing up changes nothing.
public enum RadialMenuProfiles {
    public static func layout(for bundleIdentifier: String?,
                              standard: RadialMenuLayout,
                              perApp: [String: RadialMenuLayout]) -> RadialMenuLayout {
        guard let bundleIdentifier, let specific = perApp[bundleIdentifier] else { return standard }
        return specific
    }
}
