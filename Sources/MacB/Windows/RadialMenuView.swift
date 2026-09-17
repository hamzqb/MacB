import AppKit
import MacBCore
import SwiftUI

/// The ring itself.
///
/// Everything here is drawn over the glass rather than being the glass: the
/// blurred backdrop is a donut-masked `NSVisualEffectView` sitting in the
/// window under this view, for the same reason the island's is — a
/// `.behindWindow` material inside a SwiftUI hierarchy has nothing behind it to
/// sample and turns into a flat grey sheet.
///
/// The ring never takes the keyboard and never becomes key. It is a thing the
/// hand points at while a mouse button is still down, and a window that steals
/// focus in the middle of that would end the gesture it exists to serve.
struct RadialMenuView: View {
    let actions: [RadialAction]
    /// Which slice the hand is on, or nil while it is still in the middle.
    let selection: Int?
    /// 0 while the ring is arriving, 1 once it is there.
    let presence: Double

    private var sliceCount: Int { max(1, actions.count) }
    private var step: Double { 360 / Double(sliceCount) }

    var body: some View {
        ZStack {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                slice(index: index, action: action)
            }
            divider
            hub
        }
        .frame(width: RadialMenuGeometry.outerRadius * 2,
               height: RadialMenuGeometry.outerRadius * 2)
        .scaleEffect(0.86 + 0.14 * presence)
        .opacity(presence)
        .allowsHitTesting(false)
    }

    // MARK: - Slices

    @ViewBuilder private func slice(index: Int, action: RadialAction) -> some View {
        let isOn = selection == index
        ZStack {
            sliceShape(index: index)
                .fill(isOn ? Color.white.opacity(0.20) : Color.white.opacity(0.05))
            sliceShape(index: index)
                .stroke(isOn ? MacBDesign.IslandToken.accent.opacity(0.85)
                             : Color.white.opacity(0.10),
                        lineWidth: isOn ? 1.5 : 0.5)
            label(index: index, action: action, isOn: isOn)
        }
        .motion(MacBDesign.Motion.instant, value: selection)
    }

    private func sliceShape(index: Int) -> some Shape {
        // A gap between slices, in degrees, so the ring reads as separate
        // targets rather than one disc with lines drawn on it.
        let gap = min(3.0, step / 6)
        let centre = -90 + Double(index) * step
        return AnnularSector(startAngle: .degrees(centre - step / 2 + gap / 2),
                             endAngle: .degrees(centre + step / 2 - gap / 2),
                             innerRadius: RadialMenuGeometry.innerRadius,
                             outerRadius: RadialMenuGeometry.outerRadius)
    }

    private func label(index: Int, action: RadialAction, isOn: Bool) -> some View {
        let centre = (-90 + Double(index) * step) * .pi / 180
        let radius = (RadialMenuGeometry.innerRadius + RadialMenuGeometry.outerRadius) / 2
        return Image(systemName: action.symbol)
            .font(.system(size: 17, weight: isOn ? .semibold : .medium))
            .foregroundStyle(isOn ? Color.white : MacBDesign.IslandToken.Ink.primary)
            .offset(x: cos(centre) * radius, y: sin(centre) * radius)
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }

    /// The hairline that closes the inner edge, so the hole looks cut rather
    /// than merely empty.
    private var divider: some View {
        Circle()
            .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
            .frame(width: RadialMenuGeometry.innerRadius * 2,
                   height: RadialMenuGeometry.innerRadius * 2)
    }

    /// The middle, which is both the label and the way out.
    ///
    /// It names what is about to happen rather than making the user read it off
    /// a slice they are pointing away from, and when nothing is chosen it says
    /// so, because letting go in the middle is how the ring is dismissed.
    private var hub: some View {
        VStack(spacing: 2) {
            if let selection, actions.indices.contains(selection) {
                Text(actions[selection].title)
                    .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text("Bırak, kapansın")
                    .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                    .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: RadialMenuGeometry.innerRadius * 1.7)
        .motion(MacBDesign.Motion.instant, value: selection)
    }
}

/// A slice of a donut: the shape a radial menu is actually made of.
struct AnnularSector: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: Double
    let outerRadius: Double

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: centre, radius: outerRadius,
                    startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: centre, radius: innerRadius,
                    startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// The blurred backdrop, cut to a donut.
///
/// Same lesson as the island: this has to be a sibling of the hosting view in
/// the window, not a layer inside the SwiftUI tree, or it samples nothing.
final class RadialGlassView: NSVisualEffectView {
    private var maskedSize: CGSize = .zero

    override func layout() {
        super.layout()
        guard bounds.size != maskedSize else { return }
        maskedSize = bounds.size
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        maskImage = NSImage(size: size, flipped: false) { rect in
            let centre = NSPoint(x: rect.midX, y: rect.midY)
            let outer = NSBezierPath(ovalIn: NSRect(
                x: centre.x - RadialMenuGeometry.outerRadius,
                y: centre.y - RadialMenuGeometry.outerRadius,
                width: RadialMenuGeometry.outerRadius * 2,
                height: RadialMenuGeometry.outerRadius * 2))
            let inner = NSBezierPath(ovalIn: NSRect(
                x: centre.x - RadialMenuGeometry.innerRadius,
                y: centre.y - RadialMenuGeometry.innerRadius,
                width: RadialMenuGeometry.innerRadius * 2,
                height: RadialMenuGeometry.innerRadius * 2))
            outer.append(inner.reversed)
            outer.windingRule = .evenOdd
            outer.fill()
            return true
        }
    }
}
