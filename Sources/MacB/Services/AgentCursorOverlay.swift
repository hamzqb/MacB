import AppKit
import SwiftUI

@MainActor final class AgentCursorOverlay: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey); if !isEnabled { hide() } }
    }
    @Published private(set) var isVisible = false

    private static let enabledKey = "agentCursorOverlayEnabled"
    private var window: NSPanel?
    private var hideTask: Task<Void, Never>?

    init() {
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
        }
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    func pulse(label: String = "MacB bakıyor…", at point: CGPoint? = nil) {
        guard isEnabled else { return }
        show(label: label, at: point ?? NSEvent.mouseLocation)
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run { self?.hide() }
        }
    }

    func show(label: String, at point: CGPoint) {
        guard isEnabled else { return }
        if window == nil { window = makeWindow() }
        guard let window else { return }
        let size = NSSize(width: 38, height: 38)
        window.setFrame(NSRect(x: point.x + 10, y: point.y - 44, width: size.width, height: size.height), display: true)
        window.contentView = NSHostingView(rootView: AgentCursorBadge())
        window.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        window?.orderOut(nil)
        isVisible = false
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 38, height: 38),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        return panel
    }
}

private struct AgentCursorBadge: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "cursorarrow")
                .font(.system(size: 25, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(nsColor: .systemOrange))
                .shadow(color: .black.opacity(0.40), radius: 5, y: 3)
            Circle()
                .fill(Color(nsColor: .systemOrange))
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
                .offset(x: -2, y: 2)
        }
        .frame(width: 38, height: 38)
        .accessibilityLabel("MacB göstergesi")
    }
}
