import AppKit
import Combine
import MacBCore
import SwiftUI
import Translation

/// The floating panel the AI answers in.
///
/// A panel of its own rather than a section of the island. An answer with
/// sources is a paragraph or three, and the island is a strip under the notch
/// sized for glanceable things; squeezing a reading surface into it would make
/// both worse. This appears under the notch, takes the keyboard without
/// bringing MacB forward, and goes away with Escape or a click elsewhere.
@MainActor final class AIPanelController: NSObject, NSWindowDelegate {
    private let assistant: AIAssistantService
    private let speech: SpeechInputService
    private let selection: SelectedTextService
    private let openSettings: () -> Void
    private var panel: KeyablePanel?
    private var glass: RoundedGlassView?
    private var speechState: AnyCancellable?

    private static let size = NSSize(width: 560, height: 420)

    init(assistant: AIAssistantService, speech: SpeechInputService, selection: SelectedTextService,
         openSettings: @escaping () -> Void) {
        self.assistant = assistant
        self.speech = speech
        self.selection = selection
        self.openSettings = openSettings
        super.init()
        speech.onFinish = { [weak assistant] text in assistant?.ask(text) }
        // A permission prompt took the keyboard away while the microphone was
        // being set up. When it is answered, the keyboard goes back to the
        // previous application, not here, so take it back — otherwise neither
        // Escape nor a click elsewhere would close the panel any more.
        speechState = speech.$state.removeDuplicates().dropFirst().sink { [weak self] state in
            guard let self, state != .preparing, let panel = self.panel, panel.isVisible, !panel.isKeyWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKey()
        }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? close() : show() }

    /// Opens the panel already listening. What is said becomes the question
    /// and is sent when the speaker pauses.
    func showListening() {
        show(focusQuestion: false)
        guard assistant.hasKey else { return }
        assistant.clear()
        speech.start()
    }

    func show(focusQuestion: Bool = true) {
        speech.dismissError()
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
        if focusQuestion { NotificationCenter.default.post(name: .macBFocusAIQuestion, object: nil) }
    }

    func close() {
        speech.cancel()
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
            speech: speech,
            replace: { [weak self] in
                guard let self else { return }
                self.assistant.replaceSelection(using: self.selection)
            },
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
        // A permission prompt for the microphone takes the keyboard for a
        // moment; closing then would cancel the very thing being allowed.
        if speech.state == .preparing || assistant.isDownloadingLanguage { return }
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
    @ObservedObject var speech: SpeechInputService
    var replace: () -> Void
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
            Image(systemName: speech.isBusy ? "waveform" : "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MacBDesign.IslandToken.accent)
                .symbolEffect(.variableColor.iterative, isActive: speech.isListening)
            if speech.isBusy {
                Text(speech.transcript.isEmpty ? (speech.isListening ? "Dinliyorum…" : "Mikrofon açılıyor…") : speech.transcript)
                    .font(.system(size: 16))
                    .foregroundStyle(speech.transcript.isEmpty ? MacBDesign.IslandToken.Ink.faint : MacBDesign.IslandToken.Ink.primary)
                    .lineLimit(1...4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Duyulan soru")
                levelMeter
                Button(action: speech.finish) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacBDesign.IslandToken.accent)
                .disabled(speech.transcript.isEmpty)
                .help("Şimdi gönder")
                .accessibilityLabel("Soruyu gönder")
                Button(action: speech.cancel) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                .help("Dinlemeyi bırak")
                .accessibilityLabel("Dinlemeyi bırak")
            } else {
                TextField(assistant.hasKey ? "Bir şey sor…" : "Önce Ayarlar'dan anahtarı gir",
                          text: $question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .lineLimit(1...4)
                    .focused($focused)
                    .disabled(!assistant.hasKey)
                    .onSubmit(send)
                    .accessibilityLabel("Soru")
            }
            if speech.isBusy {
                EmptyView()
            } else if assistant.isAnswering {
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
            if !speech.isBusy && !assistant.isAnswering && assistant.hasKey {
                Button(action: lookAtScreen) {
                    Image(systemName: "eye").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                .help("Öndeki pencereye bak ve sorunu ona göre yanıtla")
                .accessibilityLabel("Ekrana bak")
                Button { assistant.clear(); speech.start() } label: {
                    Image(systemName: "mic.fill").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                .help("Sesle sor")
                .accessibilityLabel("Sesle sor")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    /// Five bars that follow the microphone, so it is obvious it hears you.
    private var levelMeter: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { bar in
                let weight = [0.55, 0.8, 1, 0.8, 0.55][bar]
                Capsule()
                    .fill(MacBDesign.IslandToken.accent)
                    .frame(width: 3, height: 4 + 14 * CGFloat(speech.level * weight))
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.08), value: speech.level)
        .accessibilityHidden(true)
    }

    private var emptyState: some View {
        VStack(spacing: MacBDesign.Space.regular) {
            Spacer()
            if let error = assistant.errorMessage {
                errorLine(error)
                if let download = assistant.languageDownload {
                    LanguageDownloadButton(source: download.source, target: download.target,
                                           started: { assistant.isDownloadingLanguage = true }) { success in
                        assistant.finishLanguageDownload(success: success)
                    }
                } else if error == AIAssistantService.missingKeyMessage {
                    Button("Ayarlar'ı aç", action: openSettings)
                }
            } else if case .failed(let problem) = speech.state {
                errorLine(problem)
            } else if assistant.hasKey {
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
                    if case .failed(let problem) = speech.state { errorLine(problem) }
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
            if let result = assistant.selectionResult, result.turnID == turn.id,
               !(assistant.isAnswering && turn.id == assistant.turns.last?.id), !turn.answer.isEmpty {
                selectionControls(result)
            }
        }
    }

    /// What to do with a result made from selected text. It is already on the
    /// clipboard; putting it back in place is offered only where the other
    /// application lets a selection be written.
    private func selectionControls(_ result: AIAssistantService.SelectionResult) -> some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
            HStack(spacing: MacBDesign.Space.regular) {
                Button(action: assistant.copyResult) {
                    Label(result.isCopied ? "Panoda" : "Kopyala",
                          systemImage: result.isCopied ? "checkmark" : "doc.on.doc")
                }
                if result.isReplaced {
                    Label("Yerine kondu", systemImage: "checkmark")
                        .font(.system(size: MacBDesign.TypeScale.caption))
                } else if result.canReplace {
                    Button(action: replace) {
                        Label("Seçimin yerine koy", systemImage: "arrow.uturn.left.square")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if let note = result.note {
                Text(note)
                    .font(.system(size: MacBDesign.TypeScale.micro))
                    .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
            }
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

    /// Sends the question with a picture of the window in front of MacB.
    private func lookAtScreen() {
        speech.dismissError()
        let text = question
        question = ""
        assistant.askAboutScreen(text)
    }

    private func send() {
        speech.dismissError()
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


/// Asks macOS to download a translation language, with its own consent
/// sheet. The download is Apple's, from Apple, into the system's shared
/// language store; MacB only asks for it.
private struct LanguageDownloadButton: View {
    let source: String
    let target: String
    let started: () -> Void
    let done: (Bool) -> Void
    @State private var requested = false

    var body: some View {
        if #available(macOS 15.0, *) {
            Button(requested ? "İndiriliyor…" : "Dil paketini indir") {
                NSApp.activate(ignoringOtherApps: true)
                started()
                requested = true
            }
            .disabled(requested)
            .modifier(LanguagePreparation(source: source, target: target, active: requested) { success in
                requested = false
                done(success)
            })
        } else {
            Button("Dil ayarlarını aç") { OfflineTranslator.openLanguageSettings() }
        }
    }
}

@available(macOS 15.0, *)
private struct LanguagePreparation: ViewModifier {
    let source: String
    let target: String
    let active: Bool
    let done: (Bool) -> Void

    func body(content: Content) -> some View {
        content.translationTask(active ? TranslationSession.Configuration(
            source: Locale.Language(identifier: source), target: Locale.Language(identifier: target)) : nil) { session in
            do {
                try await session.prepareTranslation()
                done(true)
            } catch {
                done(false)
            }
        }
    }
}
