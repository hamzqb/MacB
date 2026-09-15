import AppKit
import SwiftUI

/// The island's actual translucency: the desktop behind the panel, blurred by
/// the window server, showing through the panel's own shape.
///
/// SwiftUI's materials and `glassEffect` blur what is *inside* the window they
/// are drawn in. The island's window is empty behind the panel, so all they had
/// to work with was black, and the result was a very convincing picture of
/// frosted glass with nothing behind it. The panel looked like glass and was, in
/// fact, paint.
///
/// `NSVisualEffectView` in `.behindWindow` mode is the one thing that samples
/// the screen itself, so that is what the island is made of now. It is given the
/// panel's own outline as a mask rather than relying on the SwiftUI clip, which
/// does not reliably reach an AppKit view hosted inside it — without the mask
/// the blur is a square and the rounded corners are the only part that is not.
///
/// Nothing is captured: this is the same compositor effect a sidebar uses, and
/// no pixel behind the panel is ever readable by MacB.
struct IslandBackdrop: NSViewRepresentable {
    /// How heavy the frost is. The island sits over a desktop it does not
    /// control, so it needs a material that darkens rather than one that takes
    /// the window's own colour.
    var material: NSVisualEffectView.Material = .hudWindow
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func makeNSView(context: Context) -> ShapedVisualEffectView {
        let view = ShapedVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.topRadius = topRadius
        view.bottomRadius = bottomRadius
        return view
    }

    func updateNSView(_ view: ShapedVisualEffectView, context: Context) {
        if view.material != material { view.material = material }
        view.topRadius = topRadius
        view.bottomRadius = bottomRadius
    }
}

/// An effect view that keeps its mask in step with its own bounds.
///
/// The island changes width and height constantly — it grows for a panel, it
/// shrinks back to a bar — so the mask cannot be made once. It is rebuilt
/// whenever the size or either radius changes, and never otherwise: drawing an
/// image on every layout pass of a view this size is not free.
final class ShapedVisualEffectView: NSVisualEffectView {
    var topRadius: CGFloat = 0 { didSet { if topRadius != oldValue { refreshMask() } } }
    var bottomRadius: CGFloat = 0 { didSet { if bottomRadius != oldValue { refreshMask() } } }

    private var maskedSize: CGSize = .zero

    override func layout() {
        super.layout()
        if bounds.size != maskedSize { refreshMask() }
    }

    private func refreshMask() {
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        maskedSize = size
        let top = min(topRadius, size.height / 2, size.width / 2)
        let bottom = min(bottomRadius, size.height / 2, size.width / 2)
        maskImage = NSImage(size: size, flipped: false) { rect in
            Self.outline(in: rect, topRadius: top, bottomRadius: bottom).fill()
            return true
        }
    }

    /// The panel's outline, with the top and bottom corners rounded
    /// independently: flush against the top of the screen the island has square
    /// top corners, and clear of it, round ones.
    private static func outline(in rect: NSRect, topRadius: CGFloat, bottomRadius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        // AppKit's origin is bottom-left, so "bottom" here is the low edge,
        // which is the side that hangs below the notch.
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY - topRadius))
        path.appendArc(withCenter: NSPoint(x: rect.minX + topRadius, y: rect.maxY - topRadius),
                       radius: topRadius, startAngle: 180, endAngle: 90, clockwise: true)
        path.line(to: NSPoint(x: rect.maxX - topRadius, y: rect.maxY))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - topRadius, y: rect.maxY - topRadius),
                       radius: topRadius, startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + bottomRadius))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - bottomRadius, y: rect.minY + bottomRadius),
                       radius: bottomRadius, startAngle: 0, endAngle: -90, clockwise: true)
        path.line(to: NSPoint(x: rect.minX + bottomRadius, y: rect.minY))
        path.appendArc(withCenter: NSPoint(x: rect.minX + bottomRadius, y: rect.minY + bottomRadius),
                       radius: bottomRadius, startAngle: -90, endAngle: -180, clockwise: true)
        path.close()
        return path
    }
}
