import AppKit
import SwiftUI

/// A soft light over whatever MacB is looking at or reading.
///
/// When the assistant reads the screen, the page in the browser, or the
/// selection, the user should be able to see where its attention is without
/// having to read a status line — and without the screen flashing at them.
/// So the effect is light on the edges only: a translucent glow that fades in,
/// breathes once and fades out, and, for a whole-screen read, one faint band
/// passing from top to bottom. The middle of whatever is highlighted stays
/// untouched, so the user can keep reading through it.
///
/// Never part of what is read: captures leave MacB's own windows out, and the
/// window is also marked not to be shared with any other capture. It takes no
/// clicks. The same switch as the pointer badge turns it off.
@MainActor final class AgentFocusOverlay {
    static let shared = AgentFocusOverlay()

    enum Style: Equatable {
        /// A whole display being read: edge light and one passing band.
        case scan
        /// A window or an element: a rounded outline of light.
        case focus
    }

    private var window: NSPanel?
    private var hideTask: Task<Void, Never>?
    private static let enabledKey = "agentCursorOverlayEnabled"

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) == nil
            || UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// The display under the pointer, which is the one the screen readers capture.
    func highlightScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        show(frame: screen.frame, style: .scan, duration: 1.8)
    }

    /// The frontmost window of the frontmost app — the browser before a page
    /// read, the app holding a selection.
    func highlightFrontWindow() {
        guard let frame = Self.frontWindowFrame() else { return }
        show(frame: frame, style: .focus, duration: 1.6)
    }

    /// A rectangle in screen coordinates with a top-left origin, as a browser
    /// reports an element. Clamped to the display so a wrong zoom level can
    /// only make it imprecise, never off-screen.
    func highlight(topLeftRect rect: CGRect) {
        guard let primary = NSScreen.screens.first, rect.width > 1, rect.height > 1 else { return }
        var frame = NSRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
            .insetBy(dx: -6, dy: -6)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            frame = frame.intersection(screen.frame)
        }
        guard frame.width > 4, frame.height > 4 else { return }
        show(frame: frame, style: .focus, duration: 1.4)
    }

    private func show(frame: NSRect, style: Style, duration: TimeInterval) {
        guard isEnabled else { return }
        let panel = window ?? makeWindow()
        window = panel
        panel.setFrame(frame, display: false)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.contentView = NSHostingView(rootView: AgentFocusGlow(style: style, duration: duration,
                                                                   reduceMotion: reduceMotion))
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.1) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.window?.orderOut(nil)
        }
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    /// Bounds of the frontmost app's topmost normal window, in AppKit
    /// coordinates. Window bounds need no Screen Recording permission.
    private static func frontWindowFrame() -> NSRect? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 80, rect.height > 60 else { continue }
            return NSRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
        }
        return nil
    }
}

/// The light itself. Everything is at low opacity and blurred; nothing blinks.
private struct AgentFocusGlow: View {
    let style: AgentFocusOverlay.Style
    let duration: TimeInterval
    let reduceMotion: Bool
    @State private var visible = false
    @State private var sweep: CGFloat = 0

    private let colors = [Color(red: 0.4, green: 0.8, blue: 1), Color(red: 0.62, green: 0.45, blue: 1),
                          Color(red: 0.42, green: 0.98, blue: 0.8), Color(red: 0.4, green: 0.8, blue: 1)]

    var body: some View {
        GeometryReader { geometry in
            let radius: CGFloat = style == .scan ? 14 : 12
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                // A whisper of tint so the area reads as "attended to".
                shape.fill(colors[0].opacity(style == .scan ? 0.025 : 0.05))
                // The edge light: a wide soft stroke and a thin bright one.
                shape.strokeBorder(AngularGradient(colors: colors, center: .center), lineWidth: style == .scan ? 10 : 6)
                    .blur(radius: style == .scan ? 12 : 7)
                    .opacity(0.55)
                shape.strokeBorder(AngularGradient(colors: colors, center: .center), lineWidth: 1.2)
                    .opacity(0.6)
                if style == .scan, !reduceMotion {
                    LinearGradient(colors: [.clear, colors[0].opacity(0.10), colors[1].opacity(0.07), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                        .blur(radius: 18)
                        .offset(y: -80 + sweep * (geometry.size.height + 80))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .clipShape(shape)
                }
            }
            .opacity(visible ? 1 : 0)
        }
        .padding(style == .scan ? 4 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { visible = true }
            if !reduceMotion { withAnimation(.easeInOut(duration: min(1.4, duration * 0.8))) { sweep = 1 } }
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.4, duration - 0.6)) {
                withAnimation(.easeIn(duration: 0.55)) { visible = false }
            }
        }
    }
}
