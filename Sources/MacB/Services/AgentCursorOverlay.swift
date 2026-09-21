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
        let size = NSSize(width: 168, height: 52)
        window.setFrame(NSRect(x: point.x + 14, y: point.y - 62, width: size.width, height: size.height), display: true)
        window.contentView = NSHostingView(rootView: AgentCursorBadge(label: label))
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
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 168, height: 52),
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
    let label: String
    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                Circle()
                    .fill(Color(nsColor: .systemOrange))
                    .frame(width: 7, height: 7)
                    .offset(x: 17, y: 3)
                    .opacity(0.95)
            }
            Text(label)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.94))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.32), radius: 22, y: 12)
        }
        .padding(4)
    }
}
