import CoreGraphics
import Foundation

/// The outline of the island, and how it moves.
///
/// Under a camera housing the island is the notch growing: its top edge sits
/// flush with the screen and flares outward into two small concave shoulders,
/// the way the hardware cutout meets the bezel, and its bottom corners round
/// off. Both scale with the height, so the closed strip keeps the cutout's own
/// small corners and the open panel reaches its full radius. On a display
/// without a notch there is nothing to grow out of, and the top corners round
/// like the bottom ones instead.
public struct IslandSilhouette: Equatable, Sendable {
    /// How far each shoulder flares out beyond the body, and how tall it is.
    public var shoulder: CGFloat
    /// Convex top corners, for displays without a notch.
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat

    public init(shoulder: CGFloat, topRadius: CGFloat, bottomRadius: CGFloat) {
        self.shoulder = shoulder
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    /// The silhouette for a body `height` tall, with `radius` as the layout's
    /// own bottom radius.
    public static func forBody(height: CGFloat, radius: CGFloat, underNotch: Bool) -> IslandSilhouette {
        let bottom = min(radius, height / 2)
        guard underNotch else { return IslandSilhouette(shoulder: 0, topRadius: bottom, bottomRadius: bottom) }
        let shoulder = min(maximumShoulder, max(minimumShoulder, (height * 0.19).rounded(.toNearestOrAwayFromZero)))
        return IslandSilhouette(shoulder: shoulder, topRadius: 0, bottomRadius: bottom)
    }

    public static let minimumShoulder: CGFloat = 6
    public static let maximumShoulder: CGFloat = 14

    /// The outline in `rect`, which includes the shoulders: the body is
    /// `rect` narrowed by one shoulder on each side. Drawn with `y` growing
    /// downward, as SwiftUI does; `yDown: false` flips it for AppKit layers.
    public func path(in rect: CGRect, yDown: Bool = true) -> CGPath {
        let path = CGMutablePath()
        let s = max(0, min(shoulder, rect.width / 4, rect.height / 2))
        let left = rect.minX + s, right = rect.maxX - s
        let bodyWidth = right - left
        let bottom = max(0, min(bottomRadius, bodyWidth / 2, (rect.height - s) / 2))
        let top = s > 0 ? 0 : max(0, min(topRadius, bodyWidth / 2, (rect.height - bottom) / 2))
        let y0 = rect.minY, y1 = rect.maxY
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            yDown ? CGPoint(x: x, y: y) : CGPoint(x: x, y: rect.minY + rect.maxY - y)
        }
        if s > 0 {
            // Out of the bezel on the left, down through the shoulder.
            path.move(to: p(rect.minX, y0))
            path.addQuadCurve(to: p(left, y0 + s), control: p(left, y0))
        } else {
            path.move(to: p(left, y0 + top))
            if top > 0 { path.addQuadCurve(to: p(left + top, y0), control: p(left, y0)) }
            path.addLine(to: p(right - top, y0))
            if top > 0 { path.addQuadCurve(to: p(right, y0 + top), control: p(right, y0)) }
        }
        if s > 0 {
            path.addLine(to: p(left, y1 - bottom))
            path.addQuadCurve(to: p(left + bottom, y1), control: p(left, y1))
            path.addLine(to: p(right - bottom, y1))
            path.addQuadCurve(to: p(right, y1 - bottom), control: p(right, y1))
            path.addLine(to: p(right, y0 + s))
            path.addQuadCurve(to: p(rect.maxX, y0), control: p(right, y0))
        } else {
            path.addLine(to: p(right, y1 - bottom))
            path.addQuadCurve(to: p(right - bottom, y1), control: p(right, y1))
            path.addLine(to: p(left + bottom, y1))
            path.addQuadCurve(to: p(left, y1 - bottom), control: p(left, y1))
        }
        path.closeSubpath()
        return path
    }
}

/// How the island moves. One spring for the shape, with no bounce: the
/// panel settles like an object with weight, and never wobbles. Opening is a
/// little slower than closing, which reads as calm on the way in and quick on
/// the way out. Content waits until the shape is most of the way there, then
/// fades in; on the way out it goes first.
public enum IslandMotion {
    public static let openResponse: Double = 0.40
    public static let closeResponse: Double = 0.32
    /// Critically damped: no overshoot.
    public static let damping: Double = 1.0
    /// Hover on the closed island is the one playful motion.
    public static let hoverResponse: Double = 0.30
    public static let hoverDamping: Double = 0.62
    /// How much the closed island grows under the pointer.
    public static let hoverGrowth: CGFloat = 6

    /// When content appears, as a fraction of the opening's response.
    public static let revealDelayFraction: Double = 0.45
    public static let revealDuration: Double = 0.22
    /// How long the content takes to leave before the shape shrinks.
    public static let leaveDuration: Double = 0.12
    public static let leaveBlur: CGFloat = 14

    public static func response(opening: Bool) -> Double { opening ? openResponse : closeResponse }

    /// A critically damped spring is within a hair of rest after about this
    /// long; the window can be shrunk back to the island after it.
    public static func settleTime(opening: Bool) -> Double { response(opening: opening) * 1.25 }

    /// Spring constants for Core Animation that match SwiftUI's
    /// `spring(response:dampingFraction:)`, so the glass behind the island
    /// and the island itself move as one.
    public static func stiffness(response: Double) -> Double {
        let omega = 2 * Double.pi / response
        return omega * omega
    }

    public static func dampingCoefficient(response: Double, fraction: Double = damping) -> Double {
        4 * Double.pi * fraction / response
    }
}

/// The window the island lives in.
///
/// It is sized once to hold the island's largest state plus room for its
/// shadow, and the island moves inside it; the window never resizes while the
/// island animates. Resizing it every frame was what made the old island
/// stutter: the window server, the material and SwiftUI's layout all redid
/// their work sixty times a second.
public enum IslandEnvelope {
    /// Room beside and below the island for its shadow.
    public static let sidePadding: CGFloat = 40
    public static let bottomPadding: CGFloat = 44
    /// Black drawn above the top of the screen, so no hairline of wallpaper
    /// shows between the bezel and the island.
    public static let topBleed: CGFloat = 4

    /// The window size that holds an island of `size` (shoulders included).
    public static func size(holding size: CGSize, screenWidth: CGFloat) -> CGSize {
        CGSize(width: min(screenWidth, (size.width + 2 * sidePadding).rounded(.up)),
               height: (size.height + topBleed + bottomPadding).rounded(.up))
    }
}
