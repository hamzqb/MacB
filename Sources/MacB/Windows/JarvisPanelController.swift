import AppKit
import Combine
import MacBCore
import SwiftUI

/// The small glass window a Jarvis conversation lives in.
///
/// It stays up while the user carries on working — a conversation is not
/// something a click elsewhere should hang up — and closes with Escape, the
/// close button, a goodbye, or a quiet spell. Closing it ends the session and
/// switches the microphone off.
@MainActor final class JarvisPanelController: NSObject, NSWindowDelegate {
    private let session: JarvisSession
    private let openSettings: () -> Void
    private var panel: KeyablePanel?
    private var glass: RoundedGlassView?

    private static let size = NSSize(width: 440, height: 360)

    init(session: JarvisSession, openSettings: @escaping () -> Void) {
        self.session = session
        self.openSettings = openSettings
        super.init()
        session.onEnded = { [weak self] in self?.panel?.orderOut(nil) }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? close() : show() }

    func show() {
        let window = panel ?? makePanel()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        if let screen, !window.isVisible {
            let visible = screen.visibleFrame
            window.setFrame(NSRect(x: visible.midX - Self.size.width / 2, y: visible.maxY - Self.size.height - 12,
                                   width: Self.size.width, height: Self.size.height), display: false)
        }
        glass?.isHidden = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        window.orderFrontRegardless()
        session.start()
    }

    func close() {
        session.stop()
        panel?.orderOut(nil)
    }

    private func makePanel() -> KeyablePanel {
        let window = KeyablePanel(contentRect: NSRect(origin: .zero, size: Self.size),
                                  styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.onEscape = { [weak self] in self?.close() }

        let container = NSView(frame: NSRect(origin: .zero, size: Self.size))
        let glass = RoundedGlassView(frame: container.bounds)
        glass.cornerRadius = 28
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.autoresizingMask = [.width, .height]
        let host = NSHostingView(rootView: JarvisView(
            session: session,
            close: { [weak self] in self?.close() },
            openSettings: { [weak self] in self?.close(); self?.openSettings() }))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        container.addSubview(host, positioned: .above, relativeTo: glass)
        window.contentView = container
        self.glass = glass
        panel = window
        return window
    }
}

// MARK: - View

struct JarvisView: View {
    @ObservedObject var session: JarvisSession
    var close: () -> Void
    var openSettings: () -> Void
    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 14) {
            header
            JarvisOrb(state: session.state, input: session.inputLevel, output: session.outputLevel)
                .frame(width: 118, height: 118)
                .accessibilityLabel(statusText)
            Text(statusText)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: statusText)
            if let confirmation = session.confirmation {
                confirmationCard(confirmation)
            } else {
                transcript
            }
            Spacer(minLength: 0)
            inputRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.05), .white.opacity(0.14)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Jarvis")
                .font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
            if session.isActive {
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("Canlı · mikrofon açık")
                        .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.white.opacity(0.08), in: Capsule())
                .accessibilityElement(children: .combine)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Bitir (Esc)")
            .accessibilityLabel("Konuşmayı bitir")
        }
    }

    private var statusText: String {
        if let activity = session.activity { return activity + "…" }
        switch session.state {
        case .idle: return "Kapalı"
        case .connecting: return "Bağlanıyor…"
        case .listening: return "Dinliyorum"
        case .thinking: return "Düşünüyor…"
        case .speaking: return "Konuşuyor — araya girebilirsin"
        case .failed(let message): return message
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(session.lines) { line in
                        Text(line.text)
                            .font(.system(size: line.speaker == .jarvis ? 14 : 13,
                                          weight: line.speaker == .jarvis ? .regular : .medium))
                            .foregroundStyle(line.speaker == .jarvis ? MacBDesign.IslandToken.Ink.primary
                                                                     : MacBDesign.IslandToken.Ink.secondary)
                            .frame(maxWidth: .infinity, alignment: line.speaker == .jarvis ? .leading : .trailing)
                            .multilineTextAlignment(line.speaker == .jarvis ? .leading : .trailing)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                    if case .failed = session.state {
                        Button("Yeniden bağlan") { session.start() }
                            .buttonStyle(.bordered).controlSize(.small)
                        if case .failed(let message) = session.state, message == AIAssistantService.missingKeyMessage {
                            Button("Ayarlar'ı aç", action: openSettings).controlSize(.small)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: session.lines.last?.text) { _, _ in
                if let last = session.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: 96)
    }

    private func confirmationCard(_ confirmation: JarvisSession.Confirmation) -> some View {
        VStack(spacing: 10) {
            Label(confirmation.text, systemImage: Self.symbol(for: confirmation.tool))
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Reddet") { session.answerConfirmation(false) }
                    .keyboardShortcut(.cancelAction)
                // No Return shortcut on purpose: a Return meant for the text
                // field must never become a yes to sending the screen.
                Button("İzin ver") { session.answerConfirmation(true) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.regular)
            Text("Cevap vermezsen 30 saniyede reddedilir.")
                .font(.system(size: MacBDesign.TypeScale.micro))
                .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private static func symbol(for tool: JarvisTool) -> String {
        switch tool {
        case .lookAtScreen: return "eye"
        case .addReminder: return "checklist"
        case .addCalendarEvent, .calendarEvents: return "calendar.badge.plus"
        case .openWebsite: return "safari"
        case .openApplication: return "app.badge"
        case .copyToClipboard: return "doc.on.clipboard"
        case .addNote: return "square.and.pencil"
        case .remember, .forget: return "brain"
        case .webSearch: return "magnifyingglass"
        default: return "questionmark.circle"
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Yaz ya da konuş…", text: $typed)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($typing)
                .onSubmit { session.say(typed); typed = "" }
                .disabled(!session.isActive)
                .accessibilityLabel("Jarvis'e yaz")
            Button { session.say(typed); typed = "" } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .foregroundStyle(MacBDesign.IslandToken.accent)
            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || !session.isActive)
            .accessibilityLabel("Gönder")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color.white.opacity(0.07), in: Capsule())
        .onTapGesture { typing = true }
    }
}

/// The orb: a soft sphere that breathes with the microphone while listening,
/// swells with the voice while speaking, and turns slowly while thinking.
struct JarvisOrb: View {
    let state: JarvisSession.State
    let input: Double
    let output: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var energy: Double {
        switch state {
        case .speaking: return output
        case .listening: return input
        default: return 0
        }
    }

    private var palette: [Color] {
        switch state {
        case .failed: return [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.6, green: 0.1, blue: 0.2)]
        case .idle, .connecting: return [Color.white.opacity(0.7), Color.gray.opacity(0.5)]
        case .thinking: return [Color(red: 0.75, green: 0.55, blue: 1), Color(red: 0.25, green: 0.35, blue: 1)]
        case .speaking: return [Color(red: 0.45, green: 0.95, blue: 1), Color(red: 0.2, green: 0.45, blue: 1)]
        case .listening: return [Color(red: 0.55, green: 0.85, blue: 1), Color(red: 0.35, green: 0.3, blue: 0.95)]
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let pulse = reduceMotion ? 0 : energy
            let spin = reduceMotion ? 0 : time * (state == .thinking ? 1.6 : 0.4)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [palette[0].opacity(0.45), .clear], center: .center,
                                         startRadius: 10, endRadius: 64))
                    .scaleEffect(1 + pulse * 0.35)
                Circle()
                    .fill(AngularGradient(colors: palette + [palette[0]], center: .center,
                                          angle: .radians(spin)))
                    .blur(radius: 8)
                    .frame(width: 78, height: 78)
                    .scaleEffect(1 + pulse * 0.22 + (reduceMotion ? 0 : sin(time * 1.7) * 0.02))
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.85), .white.opacity(0)], center: UnitPoint(x: 0.38, y: 0.32),
                                         startRadius: 1, endRadius: 30))
                    .frame(width: 70, height: 70)
                    .blendMode(.plusLighter)
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                    .frame(width: 80, height: 80)
                    .scaleEffect(1 + pulse * 0.22)
            }
            .animation(.easeOut(duration: 0.12), value: pulse)
        }
    }
}
