import AppKit
import MacBCore
import SwiftUI

/// The floating panel the AI answers in.
///
/// A panel of its own rather than a section of the island. An answer with
/// sources is a paragraph or three, and the island is a strip under the notch
/// sized for glanceable things; squeezing a reading surface into it would make
/// both worse. This appears under the notch, takes the keyboard without
/// bringing MacB forward, and goes away with Escape or a click elsewhere.
@MainActor final class AIPanelController: NSObject, NSWindowDelegate {
    private let assistant: AIAssistantService
    private let openSettings: () -> Void
    private var panel: KeyablePanel?
    private var glass: RoundedGlassView?

    private static let size = NSSize(width: 560, height: 420)

    init(assistant: AIAssistantService, openSettings: @escaping () -> Void) {
        self.assistant = assistant
        self.openSettings = openSettings
        super.init()
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? close() : show() }

    func show() {
        let window = panel ?? makePanel()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            // Just under the menu bar and the notch, centred: where the eye
            // already is when it has just used the island or the ring.
            let visible = screen.visibleFrame
            let origin = NSPoint(x: visible.midX - Self.size.width / 2,
                                 y: visible.maxY - Self.size.height - 12)
            window.setFrame(NSRect(origin: origin, size: Self.size), display: false)
        }
        glass?.isHidden = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .macBFocusAIQuestion, object: nil)
    }

    func close() {
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
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.delegate = self
        window.onEscape = { [weak self] in self?.close() }

        let container = NSView(frame: NSRect(origin: .zero, size: Self.size))
        container.autoresizingMask = [.width, .height]
        let glass = RoundedGlassView(frame: container.bounds)
        glass.cornerRadius = 22
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.autoresizingMask = [.width, .height]
        let host = NSHostingView(rootView: AIPanelView(
            assistant: assistant,
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

    /// Clicking anywhere else puts it away, the way Spotlight does. The
    /// conversation is kept, so reopening it carries on where it was.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// A borderless panel that can still take the keyboard.
///
/// Borderless windows refuse key status by default, which would make a text
/// field in one impossible to type into.
final class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// A behind-window material with rounded corners, cut by a mask so the blur
/// itself is rounded rather than a square sheet under a rounded picture.
final class RoundedGlassView: NSVisualEffectView {
    var cornerRadius: CGFloat = 20 { didSet { maskedSize = .zero; needsLayout = true } }
    private var maskedSize: CGSize = .zero

    override func layout() {
        super.layout()
        guard bounds.size != maskedSize, bounds.width > 1, bounds.height > 1 else { return }
        maskedSize = bounds.size
        let radius = cornerRadius
        maskImage = NSImage(size: bounds.size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
    }
}

extension Notification.Name {
    /// Sent when the AI panel opens, so its question field takes the cursor.
    static let macBFocusAIQuestion = Notification.Name("MacBFocusAIQuestion")
}

// MARK: - View

struct AIPanelView: View {
    @ObservedObject var assistant: AIAssistantService
    var close: () -> Void
    var openSettings: () -> Void

    @State private var question = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            if assistant.turns.isEmpty {
                emptyState
            } else {
                conversation
            }
        }
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.06), .white.opacity(0.12)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .macBFocusAIQuestion)) { _ in
            focused = true
        }
    }

    private var header: some View {
        HStack(spacing: MacBDesign.Space.regular) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MacBDesign.IslandToken.accent)
            TextField(assistant.hasKey ? "Bir şey sor…" : "Önce Ayarlar'dan anahtarı gir",
                      text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...4)
                .focused($focused)
                .disabled(!assistant.hasKey)
                .onSubmit(send)
                .accessibilityLabel("Soru")
            if assistant.isAnswering {
                Button(action: assistant.stop) {
                    Image(systemName: "stop.circle.fill").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .help("Durdur")
                .accessibilityLabel("Yanıtı durdur")
            } else if !assistant.turns.isEmpty {
                Button(action: { assistant.clear(); focused = true }) {
                    Image(systemName: "square.and.pencil").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                .help("Yeni konuşma")
                .accessibilityLabel("Yeni konuşma")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: MacBDesign.Space.regular) {
            Spacer()
            if assistant.hasKey {
                Text("Sor, gerekirse internette araştırıp kaynaklarıyla cevaplasın.")
                    .font(.system(size: MacBDesign.TypeScale.body))
                    .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                Text("Enter gönderir · Esc kapatır")
                    .font(.system(size: MacBDesign.TypeScale.micro))
                    .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
            } else {
                Text("OpenAI anahtarı girilmemiş.")
                    .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                Button("Ayarlar'ı aç", action: openSettings)
            }
            if let error = assistant.errorMessage { errorLine(error) }
            Spacer()
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(assistant.turns) { turn in
                        turnView(turn).id(turn.id)
                    }
                    if let error = assistant.errorMessage { errorLine(error) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(18)
            }
            .onChange(of: assistant.turns.last?.answer) { _, _ in
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

    @ViewBuilder private func turnView(_ turn: AITurn) -> some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.regular) {
            Text(turn.question)
                .font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
                .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                .textSelection(.enabled)
            if turn.answer.isEmpty && assistant.isAnswering && turn.id == assistant.turns.last?.id {
                HStack(spacing: MacBDesign.Space.snug) {
                    ProgressView().controlSize(.small)
                    Text(assistant.isSearching ? "İnternette arıyor…" : "Düşünüyor…")
                        .font(.system(size: MacBDesign.TypeScale.caption))
                        .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
                }
            } else {
                Text(Self.render(turn.answer))
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .tint(MacBDesign.IslandToken.accent)
            }
            if !turn.citations.isEmpty { sources(turn.citations) }
        }
    }

    /// Where the answer came from, as links. OpenAI requires cited sources to be
    /// visible and clickable, and a reader deserves to check them anyway.
    private func sources(_ citations: [AICitation]) -> some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
            Text("Kaynaklar")
                .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
            ForEach(Array(citations.prefix(6).enumerated()), id: \.element.id) { index, citation in
                Button {
                    NSWorkspace.shared.open(citation.url)
                } label: {
                    HStack(spacing: MacBDesign.Space.snug) {
                        Text("\(index + 1)")
                            .font(.system(size: MacBDesign.TypeScale.micro, weight: .bold)).monospacedDigit()
                            .frame(width: 16, height: 16)
                            .background(MacBDesign.IslandToken.Fill.base, in: Circle())
                        Text(citation.displayTitle).lineLimit(1)
                        Text(citation.url.host ?? "")
                            .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
                            .lineLimit(1)
                    }
                    .font(.system(size: MacBDesign.TypeScale.caption))
                }
                .buttonStyle(.plain)
                .help(citation.url.absoluteString)
            }
        }
        .padding(.top, MacBDesign.Space.hair)
    }

    private func errorLine(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: MacBDesign.TypeScale.caption))
            .foregroundStyle(Color.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func send() {
        let text = question
        question = ""
        assistant.ask(text)
    }

    /// Light Markdown — bold, italics, code, links — with the line breaks kept.
    /// Anything that does not parse is shown as the plain text it is.
    private static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
