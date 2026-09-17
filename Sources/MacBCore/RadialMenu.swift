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
    /// Moving somebody else's window and reading the window list both do; the
    /// rest of the ring is MacB's own panels and needs nothing.
    public var requiresAccessibility: Bool {
        switch self {
        case .switcher, .windowLeft, .windowRight, .windowMaximize, .windowCenter, .windowNextDisplay:
            return true
        case .island, .shelf, .clipboard, .timer, .keyboardLock, .settings:
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
    /// Below three there is no ring worth drawing, and past eight the slices are
    /// narrower than the wobble in a hand coming off a trackpad click.
    public static let minimumSlices = 3
    public static let maximumSlices = 8

    /// The hole in the middle, in points.
    ///
    /// A gesture is a press and a flick, and the press lands before the flick
    /// does: without a dead zone the slice under the cursor at the instant of
    /// the click would fire on every single use. Inside this radius the ring is
    /// showing but has chosen nothing, which is also how somebody backs out —
    /// come back to the middle and let go.
    public static let deadZone: Double = 34

    /// Where the drawn ring starts and ends, measured from the cursor.
    public static let innerRadius: Double = 52
    public static let outerRadius: Double = 116

    public static func clampSliceCount(_ count: Int) -> Int {
        min(maximumSlices, max(minimumSlices, count))
    }

    /// Which slice an offset from the centre points at, or nil for none.
    ///
    /// `dx` grows to the right and `dy` grows upwards, which is AppKit's screen
    /// orientation rather than a view's. Slice zero is straight up and the rest
    /// run clockwise, because that is the order they are read in.
    public static func slice(dx: Double, dy: Double, count: Int) -> Int? {
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

/// Which action sits on which slice.
///
/// Stored as a plain list because the ring is a list: the order on screen is the
/// order here, clockwise from the top, and reordering is moving an element.
public struct RadialMenuLayout: Equatable, Codable, Sendable {
    public private(set) var actions: [RadialAction]

    public static let `default` = RadialMenuLayout(actions: [
        .island, .clipboard, .shelf, .switcher, .windowMaximize, .settings
    ])

    /// Decoding goes through the same validation as everything else, so a file
    /// edited by hand cannot produce a ring with twenty slices or none.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(actions: try container.decode([RadialAction].self, forKey: .actions))
    }

    public init(actions: [RadialAction]) {
        self.actions = Array(actions.prefix(RadialMenuGeometry.maximumSlices))
        if self.actions.count < RadialMenuGeometry.minimumSlices {
            self.actions = RadialMenuLayout.fallback(filling: self.actions)
        }
    }

    /// The slices that can actually run, in order.
    ///
    /// An unavailable action is dropped rather than greyed out: a ring is aimed
    /// at by angle, and a dead slice that still takes up a sixth of the circle
    /// costs every other slice its position. Somebody who has not granted
    /// Accessibility gets a smaller ring rather than one where half the slices
    /// do nothing and never say why.
    public func usableActions(hasAccessibility: Bool) -> [RadialAction] {
        let usable = actions.filter { hasAccessibility || !$0.requiresAccessibility }
        return usable.count >= RadialMenuGeometry.minimumSlices
            ? usable
            : RadialMenuLayout.fallback(filling: usable)
    }

    /// Tops a short list up from the default one, without repeating anything.
    private static func fallback(filling actions: [RadialAction]) -> [RadialAction] {
        var filled = actions
        for candidate in [RadialAction.island, .clipboard, .shelf, .switcher] where
            filled.count < RadialMenuGeometry.minimumSlices && !filled.contains(candidate) {
            filled.append(candidate)
        }
        return filled
    }
}
