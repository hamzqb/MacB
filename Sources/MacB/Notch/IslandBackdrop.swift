import AppKit
import CoreImage
import QuartzCore

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
/// the screen itself, so that is what the island is made of now. It does not
/// live in the SwiftUI view: hosted inside a hierarchy that clips itself to the
/// island's outline and folds with the lid, it has nothing behind it to sample
/// and draws a flat dark sheet. `NotchController` puts it in the panel's window
/// underneath the hosting view instead, and gives it the panel's own outline as
/// a mask — without the mask the glass is a square and only the corners of the
/// content are round.
///
/// Nothing is captured: this is the same compositor effect a sidebar uses, and
/// no pixel behind the panel is ever readable by MacB.
///
/// The mask is rebuilt whenever the size or either radius changes, and never
/// otherwise: the island changes width and height constantly, and drawing an
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
            IslandOutline.path(in: rect, topRadius: top, bottomRadius: bottom).fill()
            return true
        }
    }
}

/// Puts the colour back into what the material took out.
///
/// A `.behindWindow` material does not only blur, it washes out: the blur is
/// paired with a heavy desaturation and a grey wash, which is why a panel over
/// a bright wallpaper still reads as a grey slab rather than as glass with a
/// wallpaper behind it. Apple's own glass does the opposite — it pushes
/// saturation up, so what is behind the sheet is more colourful through it than
/// around it, and that single difference is most of what the eye calls glass.
///
/// `backgroundFilters` is the public way to ask Core Animation for that: the
/// filter runs on whatever has already been composited behind this layer, which
/// here is the blurred desktop the material drew. Nothing is read back — the
/// filter lives in the compositor, and MacB never sees a pixel of it.
///
/// If the compositor declines to run it the view is simply invisible, which is
/// the correct failure: the island is still glass, just less vivid.
final class IslandSaturationView: NSView {
    var topRadius: CGFloat = 0 { didSet { if topRadius != oldValue { refreshMask() } } }
    var bottomRadius: CGFloat = 0 { didSet { if bottomRadius != oldValue { refreshMask() } } }
    /// 1 leaves the picture alone; above that, colours through the glass deepen.
    var saturation: Double = 1 { didSet { if saturation != oldValue { refreshFilters() } } }

    private var maskedSize: CGSize = .zero
    private let shape = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.mask = shape
        refreshFilters()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        if bounds.size != maskedSize { refreshMask() }
    }

    private func refreshFilters() {
        guard let layer else { return }
        guard saturation > 1.001,
              let filter = CIFilter(name: "CIColorControls",
                                    parameters: [kCIInputSaturationKey: saturation]) else {
            layer.backgroundFilters = []
            return
        }
        layer.backgroundFilters = [filter]
    }

    private func refreshMask() {
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        maskedSize = size
        let top = min(topRadius, size.height / 2, size.width / 2)
        let bottom = min(bottomRadius, size.height / 2, size.width / 2)
        shape.frame = bounds
        shape.path = IslandOutline.path(in: bounds, topRadius: top, bottomRadius: bottom).cgPath
        shape.fillColor = NSColor.black.cgColor
    }
}

/// The island's silhouette, shared by everything in the window that has to be
/// cut to it.
enum IslandOutline {
    /// The panel's outline, with the top and bottom corners rounded
    /// independently: flush against the top of the screen the island has square
    /// top corners, and clear of it, round ones.
    static func path(in rect: NSRect, topRadius: CGFloat, bottomRadius: CGFloat) -> NSBezierPath {
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
