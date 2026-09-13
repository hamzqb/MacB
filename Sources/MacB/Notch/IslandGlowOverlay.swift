import AppKit
import SwiftUI

/// The island's shadow and the light it spills, both drawn behind it.
///
/// A panel that simply appears is a rectangle pasted over the wallpaper. A real
/// object that lights up throws some of that light onto what is behind it, and
/// that single cue is most of what makes the notch read as part of the machine
/// rather than a window sitting on top of it.
///
/// Both live in their own window under the panel so they can bleed past the
/// panel's own edges, which nothing drawn inside the panel can do. The window
/// never takes the mouse, so the desktop underneath behaves exactly as it did.
///
/// The shadow is drawn here rather than switched on with the window's own
/// `hasShadow`, because the system shadow is computed from the window's alpha
/// and has to be invalidated by hand on every resize. The island resizes on
/// every frame it animates, so that shadow would either lag a frame behind the
/// panel or cost a full recomputation sixty times a second.
@MainActor final class IslandGlowOverlay {
    private var window: NSWindow?
    private let model = Model()

    /// How far the light reaches past the panel on each side, and below it.
    ///
    /// Deliberately short. The first attempt reached a hundred and fifty points
    /// and read as an orange filter over the top third of the screen rather
    /// than as light: text under it went warm and lost contrast. Light from a
    /// small object falls off fast, and so should this.
    static let spread: CGFloat = 84

    /// Follows the panel. A zero strength puts the window away entirely, so an
    /// idle island costs nothing at all.
    func update(frame: NSRect, on screen: NSScreen, radius: CGFloat, tint: Color,
                shadow: Double, glow: Double) {
        guard max(shadow, glow) > 0.01, frame.width > 1 else { return hide() }
        let box = NSRect(x: frame.minX - Self.spread,
                         y: frame.minY - Self.spread,
                         width: frame.width + Self.spread * 2,
                         height: frame.height + Self.spread)
        if window == nil { build(on: screen) }
        window?.setFrame(box, display: false)
        model.panelWidth = frame.width
        model.panelHeight = frame.height
        model.radius = radius
        model.tint = tint
        model.shadow = shadow
        model.glow = glow
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func build(on screen: NSScreen) {
        let panel = NSWindow(contentRect: .zero, styleMask: [.borderless],
                             backing: .buffered, defer: false, screen: screen)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Under the island, over everything else. The light belongs to the
        // island, so anything the island covers it should light too.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: GlowView(model: model))
        panel.orderFront(nil)
        window = panel
    }

    @MainActor final class Model: ObservableObject {
        @Published var tint: Color = .orange
        @Published var shadow: Double = 0
        @Published var glow: Double = 0
        @Published var panelWidth: CGFloat = 0
        @Published var panelHeight: CGFloat = 0
        @Published var radius: CGFloat = 0
    }

    private struct GlowView: View {
        static let spread = IslandGlowOverlay.spread

        @ObservedObject var model: Model

        var body: some View {
            GeometryReader { proxy in
                let centreX = proxy.size.width / 2
                ZStack {
                    // The shadow, in the island's own shape. Offset down a
                    // little: the light in the room is above the screen, so the
                    // shadow belongs below the object rather than around it.
                    RoundedRectangle(cornerRadius: model.radius, style: .continuous)
                        .fill(.black)
                        .frame(width: model.panelWidth, height: model.panelHeight)
                        .position(x: centreX, y: model.panelHeight / 2 + 10)
                        .blur(radius: 22)
                        .opacity(0.55 * model.shadow)

                    // On the panel's bottom edge, because that is the edge the
                    // light actually leaves from: the top is against the bezel
                    // and the sides are nearly vertical.
                    EllipticalGradient(
                        colors: [model.tint.opacity(0.16), model.tint.opacity(0.05), .clear],
                        center: .center,
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.5)
                    .frame(width: max(model.panelWidth, 220) * 1.15, height: Self.spread * 1.8)
                    .position(x: centreX, y: model.panelHeight * 0.92)
                    .blur(radius: 30)
                    .opacity(model.glow)
                    .blendMode(.plusLighter)
                }
            }
            .allowsHitTesting(false)
            .motion(MacBDesign.Motion.gentle, value: model.tint)
            .motion(MacBDesign.Motion.quick, value: model.glow)
            .motion(MacBDesign.Motion.quick, value: model.shadow)
        }
    }
}
