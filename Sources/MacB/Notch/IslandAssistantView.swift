import AppKit
import MacBCore
import SwiftUI

/// The voice assistant in the island: an orb, a word about what it is doing,
/// and the last thing it said.
///
/// Small on purpose. A conversation held out loud does not need a transcript on
/// screen — the answer is in the air — so this keeps one line of it, the one
/// being said now, and nothing else. What has to be read rather than heard is a
/// question waiting to be allowed, and that gets its own card.
struct IslandAssistantView: View {
    @ObservedObject var session: JarvisSession
    /// Whether the island shows what is being said. The user's choice, kept
    /// between conversations.
    @Binding var captions: Bool
    var close: () -> Void
    var openSettings: () -> Void
    @State private var typed = ""
    @FocusState private var typing: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: MacBDesign.Space.snug) {
            badge
            if captions, let line = latestLine {
                Text(line)
                    .font(.system(size: MacBDesign.TypeScale.micro))
                    .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .id(line)
                    .transition(.opacity)
            }
            if let confirmation = session.confirmation {
                confirmationCard(confirmation)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if session.showsInput {
                inputRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .foregroundStyle(MacBDesign.IslandToken.Ink.primary)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: session.showsInput)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: captions)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: session.confirmation?.text)
        .animation(.easeInOut(duration: 0.2), value: statusText)
        .animation(.easeInOut(duration: 0.2), value: latestLine)
        .onAppear { typed = "" }
        .onChange(of: session.showsInput) { _, shown in typing = shown }
    }

    // MARK: - The badge

    /// What is there when nothing has been asked for: the orb and a word.
    ///
    /// Tapping it opens the line to type into, and closes it again. The two
    /// small controls only appear under the pointer, so at rest this is a dot
    /// and a word and nothing else.
    private var badge: some View {
        HStack(spacing: MacBDesign.Space.snug) {
            JarvisOrb(state: session.state, input: session.inputLevel, output: session.outputLevel)
                .frame(width: 26, height: 26)
            JarvisWaveform(state: session.state,
                           level: session.state == .speaking ? session.outputLevel : session.inputLevel)
                .frame(width: 26, height: 14)
            Text(statusText)
                .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                .lineLimit(1)
                .id(statusText)
                .transition(.opacity)
            Spacer(minLength: 2)
            if hovering || session.showsInput {
                smallButton(captions ? "captions.bubble.fill" : "captions.bubble",
                            label: captions ? "Altyazıyı kapat" : "Altyazıyı aç") {
                    captions.toggle()
                }
                .transition(.opacity)
            }
            if case .failed = session.state {
                smallButton("arrow.clockwise", label: "Yeniden bağlan") { session.start() }
            }
            smallButton("xmark", label: "Konuşmayı bitir", action: close)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture { session.showsInput.toggle() }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MacB, \(statusText)")
        .accessibilityHint("Yazmak için tıkla")
    }

    private func smallButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 16, height: 16)
                .background(MacBDesign.IslandToken.Fill.base, in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// The newest thing said, whoever said it.
    private var latestLine: String? {
        guard let last = session.lines.last else { return nil }
        let text = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var statusText: String {
        if let activity = session.activity { return activity + "…" }
        switch session.state {
        case .idle: return "kapalı"
        case .connecting: return "bağlanıyor…"
        case .listening: return "dinliyorum"
        case .thinking: return "düşünüyor…"
        case .speaking: return "konuşuyor"
        case .failed(let message): return message
        }
    }

    // MARK: - Confirmation

    private func confirmationCard(_ confirmation: JarvisSession.Confirmation) -> some View {
        HStack(spacing: MacBDesign.Space.snug) {
            Image(systemName: Self.symbol(for: confirmation.tool))
                .font(.system(size: 11))
                .foregroundStyle(MacBDesign.IslandToken.accent)
            Text(confirmation.text)
                .font(.system(size: MacBDesign.TypeScale.micro))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            // No Return shortcut on purpose: a Return meant for the text field
            // must never become a yes to sending the screen.
            Button("Hayır") { session.answerConfirmation(false) }
                .buttonStyle(IslandCapsuleButtonStyle())
            Button("İzin ver") { session.answerConfirmation(true) }
                .buttonStyle(IslandCapsuleButtonStyle(isPrimary: true))
        }
        .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
        .buttonStyle(.plain)
        .padding(.horizontal, MacBDesign.Space.snug)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(MacBDesign.IslandToken.Fill.base, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Typing

    /// A thin line to type into, for when saying it out loud is not an option.
    private var inputRow: some View {
        HStack(spacing: MacBDesign.Space.snug) {
            TextField("yaz", text: $typed)
                .textFieldStyle(.plain)
                .font(.system(size: MacBDesign.TypeScale.micro))
                .focused($typing)
                .onSubmit(send)
                .disabled(!session.isActive)
                .accessibilityLabel("MacB'ye yaz")
            if case .failed(let message) = session.state, message == AIAssistantService.missingKeyMessage {
                Button("Ayarlar", action: openSettings).controlSize(.mini)
            }
            if !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacBDesign.IslandToken.accent)
                .accessibilityLabel("Gönder")
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, MacBDesign.Space.regular)
        .frame(height: 22)
        .background(MacBDesign.IslandToken.Fill.hairline, in: Capsule())
        .animation(.easeOut(duration: 0.15), value: typed.isEmpty)
    }

    private func send() {
        session.say(typed)
        typed = ""
    }

    private static func symbol(for tool: JarvisTool) -> String {
        switch tool {
        case .lookAtScreen: return "eye"
        case .readScreenText: return "text.viewfinder"
        case .runScenario: return "wand.and.stars"
        case .playMusic: return "play.circle.fill"
        case .powerAction: return "moon.zzz.fill"
        case .setAppearance: return "circle.lefthalf.filled"
        case .openSettings: return "gearshape"
        case .setWiFi: return "wifi"
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
}

/// The orb: a soft sphere that breathes with the microphone while listening,
/// swells with the voice while speaking, and turns while thinking.
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

    /// A colour per state, far enough apart to tell at a glance and without
    /// reading the words: blue is hearing you, violet is working, green is
    /// talking, amber is still connecting, red went wrong.
    static func palette(for state: JarvisSession.State) -> [Color] {
        switch state {
        case .failed:
            return [Color(red: 1, green: 0.42, blue: 0.38), Color(red: 0.62, green: 0.08, blue: 0.16)]
        case .idle:
            return [Color.white.opacity(0.65), Color.gray.opacity(0.45)]
        case .connecting:
            return [Color(red: 1, green: 0.78, blue: 0.35), Color(red: 0.75, green: 0.45, blue: 0.1)]
        case .thinking:
            return [Color(red: 0.78, green: 0.53, blue: 1), Color(red: 0.42, green: 0.18, blue: 0.9)]
        case .speaking:
            return [Color(red: 0.42, green: 0.98, blue: 0.7), Color(red: 0.05, green: 0.6, blue: 0.45)]
        case .listening:
            return [Color(red: 0.4, green: 0.8, blue: 1), Color(red: 0.1, green: 0.35, blue: 0.95)]
        }
    }

    private var palette: [Color] { JarvisOrb.palette(for: state) }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let pulse = reduceMotion ? 0 : energy
                let spin = reduceMotion ? 0 : time * (state == .thinking ? 1.6 : 0.4)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [palette[0].opacity(0.45), .clear], center: .center,
                                             startRadius: size * 0.1, endRadius: size * 0.55))
                        .scaleEffect(1 + pulse * 0.3)
                    Circle()
                        .fill(AngularGradient(colors: palette + [palette[0]], center: .center, angle: .radians(spin)))
                        .blur(radius: size * 0.08)
                        .frame(width: size * 0.68, height: size * 0.68)
                        .scaleEffect(1 + pulse * 0.22 + (reduceMotion ? 0 : sin(time * 1.7) * 0.02))
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.8), .white.opacity(0)],
                                             center: UnitPoint(x: 0.38, y: 0.32),
                                             startRadius: 1, endRadius: size * 0.3))
                        .frame(width: size * 0.62, height: size * 0.62)
                        .blendMode(.plusLighter)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                        .frame(width: size * 0.7, height: size * 0.7)
                        .scaleEffect(1 + pulse * 0.22)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .animation(.easeOut(duration: 0.12), value: pulse)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Five bars beside the orb that move with whoever is talking.
///
/// The orb alone says which state MacB is in but not whether anything is
/// actually reaching the microphone — a listening orb and a deaf one look the
/// same. Bars do not: they are flat when nothing is arriving and they move when
/// it is, which is the one question somebody has while talking to a computer.
/// Costs nothing; the levels are already being measured for the orb.
struct JarvisWaveform: View {
    let state: JarvisSession.State
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Only while somebody is talking. Thinking and connecting have the orb's
    /// own motion, and a waveform there would be pretending to hear something.
    private var isLive: Bool {
        switch state {
        case .listening, .speaking: return true
        default: return false
        }
    }

    var body: some View {
        let color = JarvisOrb.palette(for: state)[0]
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !isLive)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let energy = isLive ? min(1, max(0, level)) : 0
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<5, id: \.self) { bar in
                        // Each bar runs at its own speed, so the row reads as a
                        // wave rather than five things blinking together.
                        let phase = reduceMotion ? 0 : sin(time * (2.4 + Double(bar) * 0.55) + Double(bar))
                        let height = geometry.size.height * (0.18 + energy * (0.42 + 0.4 * phase))
                        Capsule()
                            .fill(color.opacity(0.35 + energy * 0.5))
                            .frame(height: max(2, height))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .opacity(isLive ? 1 : 0)
        .animation(reduceMotion ? nil : MacBDesign.Motion.quick, value: isLive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The orb as the closed island shows it: a small pulsing dot in the state's
/// colour, with a ring that breathes with whoever is talking.
///
/// No words and no transcript. While MacB is working in the background this is
/// all there is to see — enough to know it is listening, small enough to sit in
/// a row of indicators.
struct JarvisMiniOrb: View {
    let state: JarvisSession.State
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = JarvisOrb.palette(for: state)
        let energy = reduceMotion ? 0 : min(1, max(0, level))
        ZStack {
            Circle()
                .stroke(colors[0].opacity(0.55), lineWidth: 1)
                .frame(width: 11, height: 11)
                .scaleEffect(1 + energy * 0.5)
                .opacity(1 - energy * 0.45)
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 7, height: 7)
                .scaleEffect(1 + energy * 0.35)
        }
        .frame(width: 14, height: 14)
        .animation(.easeOut(duration: 0.12), value: energy)
    }
}
