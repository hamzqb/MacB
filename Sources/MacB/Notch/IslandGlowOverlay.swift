import AppKit
import SwiftUI

/// The light the island spills onto the desktop behind it.
///
/// A panel that simply appears is a rectangle pasted over the wallpaper. A real
/// object that lights up throws some of that light onto what is behind it, and
/// that single cue is most of what makes the notch read as part of the machine
/// rather than a window sitting on top of it.
///
/// It lives in its own window under the panel so it can bleed past the panel's
/// own edges, which a shadow inside the panel cannot do. The window never takes
/// the mouse, so the desktop underneath behaves exactly as it did.
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
    func update(frame: NSRect, on screen: NSScreen, tint: Color, strength: Double) {
        guard strength > 0.01, frame.width > 1 else { return hide() }
        let box = NSRect(x: frame.minX - Self.spread,
                         y: frame.minY - Self.spread,
                         width: frame.width + Self.spread * 2,
                         height: frame.height + Self.spread)
        if window == nil { build(on: screen) }
        window?.setFrame(box, display: false)
        model.panelWidth = frame.width
        model.panelHeight = frame.height
        model.tint = tint
        model.strength = strength
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
        @Published var strength: Double = 0
        @Published var panelWidth: CGFloat = 0
        @Published var panelHeight: CGFloat = 0
    }

    private struct GlowView: View {
        static let spread = IslandGlowOverlay.spread

        @ObservedObject var model: Model

        var body: some View {
            GeometryReader { proxy in
                // On the panel's bottom edge, because that is the edge the
                // light actually leaves from: the top is against the bezel and
                // the sides are nearly vertical.
                let centre = CGPoint(x: proxy.size.width / 2, y: model.panelHeight * 0.92)
                let reach = max(model.panelWidth, 220)
                EllipticalGradient(
                    colors: [model.tint.opacity(0.16), model.tint.opacity(0.05), .clear],
                    center: .center,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5)
                .frame(width: reach * 1.15, height: Self.spread * 1.8)
                .position(centre)
                .blur(radius: 30)
                .opacity(model.strength)
                .blendMode(.plusLighter)
            }
            .allowsHitTesting(false)
            .motion(MacBDesign.Motion.gentle, value: model.tint)
            .motion(MacBDesign.Motion.quick, value: model.strength)
        }
    }
}
