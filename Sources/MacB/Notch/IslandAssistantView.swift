import AppKit
import MacBCore
import SwiftUI

/// What a conversation looks like in the open island. There is no navigation
/// row: `IslandAssistantEars` puts the orb and the status word either side of
/// the camera, and `IslandAssistantPanel` adds the text field, a subtitle or a
/// question under them only when one is wanted.
extension JarvisSession {
    /// The status as one or two words.
    var islandStatus: String {
        if let activity { return activity + "…" }
        switch state {
        case .idle: return "kapalı"
        case .connecting: return "bağlanıyor…"
        case .listening: return "dinliyorum"
        case .thinking: return "düşünüyor…"
        case .speaking: return "konuşuyor"
        case .failed: return "bağlanamadı"
        }
    }

    /// The one line the body shows, if any. A fault is always shown — it is
    /// the only way to learn what went wrong — and a subtitle only when asked.
    func islandDetail(captions: Bool) -> String? {
        if case .failed(let message) = state { return message }
        guard captions, let last = lines.last else { return nil }
        let text = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// The orb and a small button row on the left of the camera, the status word
/// on the right.
///
/// Both sit in the strip the panel already covers beside the notch, so they
/// cost no height and can never run into the camera and settings buttons,
/// which are in the row below. Tapping either side opens the text field.
struct IslandAssistantEars: View {
    @ObservedObject var session: JarvisSession
    @Binding var captions: Bool
    /// What each side gets once the edge padding and the camera are cleared.
    var earWidth: CGFloat
    var close: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            IslandAssistantPresence(session: session, captions: $captions, hovering: hovering, close: close)
                .frame(width: earWidth, alignment: .leading)
            Spacer(minLength: 0)
            IslandAssistantStatus(session: session)
                .frame(width: earWidth, alignment: .trailing)
        }
        .padding(.horizontal, IslandGeometry.horizontalPadding)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { session.showsInput = true }
        .onHover { hovering = $0 }
        .motion(MacBDesign.Motion.quick, value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Yazmak için tıkla")
    }
}

/// The orb, the free-mode leaf, and the small controls that only appear under
/// the pointer.
struct IslandAssistantPresence: View {
    @ObservedObject var session: JarvisSession
    @Binding var captions: Bool
    var hovering: Bool
    var close: () -> Void

    var body: some View {
        HStack(spacing: MacBDesign.Space.snug) {
            JarvisOrb(state: session.state, input: session.inputLevel, output: session.outputLevel)
                .frame(width: 20, height: 20)
                .accessibilityLabel("MacB, \(session.islandStatus)")
            if session.isFreeEngine && !hovering {
                // Free is a mode, not a fault: it gets a mark of its own rather
                // than an apology in the status line.
                Image(systemName: "leaf.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
                    .help("Ücretsiz mod: konuşma bu Mac'te çözülür, cevabı ücretsiz sağlayıcı yazar.")
                    .transition(.opacity)
            }
            if hovering {
                Group {
                    smallButton(captions ? "captions.bubble.fill" : "captions.bubble",
                                label: captions ? "Altyazıyı kapat" : "Altyazıyı aç") { captions.toggle() }
                    if case .failed = session.state {
                        smallButton("arrow.clockwise", label: "Yeniden bağlan") { session.start() }
                    }
                    smallButton("xmark", label: "Konuşmayı bitir", action: close)
                }
                .transition(.opacity)
            }
        }
    }

    private func smallButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 18, height: 18)
                .background(MacBDesign.IslandToken.Fill.base, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The status word: one line, trailing, cut short rather than wrapped.
struct IslandAssistantStatus: View {
    @ObservedObject var session: JarvisSession

    var body: some View {
        Text(session.islandStatus)
            .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
            .foregroundStyle(statusColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(session.islandStatus)
            .id(session.islandStatus)
            .transition(.opacity)
            .motion(MacBDesign.Motion.quick, value: session.islandStatus)
    }

    private var statusColor: Color {
        if case .failed = session.state { return JarvisOrb.palette(for: session.state)[0] }
        return MacBDesign.IslandToken.Ink.secondary
    }
}

/// The open island while a conversation runs: the orb and status up top, and
/// under them only what is wanted right now — the text field while the pointer
/// is here, a subtitle, a question waiting for a yes.
struct IslandAssistantPanel: View {
    @ObservedObject var session: JarvisSession
    /// Whether the island shows what is being said. The user's choice, kept
    /// between conversations.
    @Binding var captions: Bool
    /// The strip beside the camera; zero on a display without a notch.
    var cameraHeight: CGFloat
    var earWidth: CGFloat
    var showsInput: Bool
    var isInteractive: Bool
    var close: () -> Void
    var openSettings: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: IslandGeometry.assistantSpacing) {
            if cameraHeight > 0 {
                IslandAssistantEars(session: session, captions: $captions, earWidth: earWidth, close: close)
                    .frame(height: cameraHeight)
            } else {
                HStack(spacing: 0) {
                    IslandAssistantPresence(session: session, captions: $captions, hovering: hovering, close: close)
                    Spacer(minLength: MacBDesign.Space.close)
                    IslandAssistantStatus(session: session)
                }
                .frame(height: IslandGeometry.assistantPresenceHeight)
                .padding(.horizontal, IslandGeometry.horizontalPadding)
                .padding(.top, IslandGeometry.assistantPresenceTop)
                .contentShape(Rectangle())
                .onTapGesture { session.showsInput = true }
                .onHover { hovering = $0 }
                .motion(MacBDesign.Motion.quick, value: hovering)
            }
            VStack(alignment: .leading, spacing: IslandGeometry.assistantSpacing) {
                if showsInput {
                    IslandAssistantInput(session: session, openSettings: openSettings, isInteractive: isInteractive)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
                if let line = session.islandDetail(captions: captions) {
                    Text(line)
                        .font(.system(size: MacBDesign.TypeScale.micro))
                        .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, maxHeight: IslandGeometry.captionHeight, alignment: .topLeading)
                        .textSelection(.enabled)
                        .help(line)
                        .id(line)
                        .transition(.opacity)
                }
                if let confirmation = session.confirmation {
                    confirmationCard(confirmation)
                        .frame(height: IslandGeometry.assistantConfirmationHeight)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, MacBDesign.Space.regular + 4)
        }
        .foregroundStyle(MacBDesign.IslandToken.Ink.primary)
        .motion(MacBDesign.Motion.quick, value: showsInput)
        .motion(MacBDesign.Motion.quick, value: session.islandDetail(captions: captions))
        .motion(MacBDesign.Motion.normal, value: session.confirmation?.text)
    }

    // MARK: - Confirmation

    private func confirmationCard(_ confirmation: JarvisSession.Confirmation) -> some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.close) {
            HStack(alignment: .top, spacing: MacBDesign.Space.close) {
                ZStack {
                    Circle().fill(MacBDesign.IslandToken.accent.opacity(0.18))
                    Image(systemName: Self.symbol(for: confirmation.tool))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacBDesign.IslandToken.accent)
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                    Text(Self.title(for: confirmation.tool))
                        .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                        .foregroundStyle(MacBDesign.IslandToken.Ink.primary)
                    Text(confirmation.text)
                        .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                        .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: MacBDesign.Space.snug) {
                Spacer(minLength: 0)
                Button("Hayır") { session.answerConfirmation(false) }
                    .buttonStyle(IslandCapsuleButtonStyle())
                // No Return shortcut on purpose: a Return meant for the text field
                // must never become a yes to sending the screen.
                Button("İzin ver") { session.answerConfirmation(true) }
                    .buttonStyle(IslandCapsuleButtonStyle(isPrimary: true))
            }
        }
        .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
        .buttonStyle(.plain)
        .padding(.horizontal, MacBDesign.Space.comfortable)
        .padding(.vertical, MacBDesign.Space.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [MacBDesign.IslandToken.Fill.raised,
                                              MacBDesign.IslandToken.Fill.low],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(MacBDesign.IslandToken.Fill.strong.opacity(0.7), lineWidth: 0.7))
    }

    private static func title(for tool: JarvisTool) -> String {
        switch tool {
        case .readMail: return "Maillerine bakayım mı?"
        case .calendarEvents: return "Takvimine bakayım mı?"
        case .lookAtScreen: return "Ekrana bakayım mı?"
        case .readScreenText: return "Ekrandaki yazıyı okuyayım mı?"
        case .readBrowserPage: return "Tarayıcıdaki sayfayı okuyayım mı?"
        case .browserAction: return "Tarayıcıda yapayım mı?"
        case .addReminder: return "Hatırlatıcı ekleyeyim mi?"
        case .addCalendarEvent: return "Takvime ekleyeyim mi?"
        case .powerAction: return "Mac için bu işlemi yapayım mı?"
        case .remember: return "Bunu hafızaya alayım mı?"
        default: return "Buna izin veriyor musun?"
        }
    }

    private static func symbol(for tool: JarvisTool) -> String {
        switch tool {
        case .lookAtScreen: return "eye"
        case .readScreenText: return "text.viewfinder"
        case .readBrowserPage: return "safari"
        case .browserAction: return "cursorarrow.click"
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

/// The text field: a slim capsule that is there while the pointer is over the
/// island or the user is typing, and gone otherwise.
struct IslandAssistantInput: View {
    @ObservedObject var session: JarvisSession
    var openSettings: () -> Void
    /// False for the copy of the panel that is fading out, so two fields never
    /// fight over the keyboard.
    var isInteractive: Bool
    @State private var typed = ""
    @FocusState private var focused: Bool

    private var hasText: Bool { !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: MacBDesign.Space.close) {
            JarvisMiniOrb(state: session.state,
                          level: session.state == .speaking ? session.outputLevel : session.inputLevel)
                .accessibilityHidden(true)
            TextField("MacB’ye yaz", text: $typed)
                .textFieldStyle(.plain)
                .font(.system(size: MacBDesign.TypeScale.body))
                .focused($focused)
                .onSubmit(send)
                .onExitCommand(perform: dismiss)
                .disabled(!session.isActive)
                .accessibilityLabel("MacB'ye yaz")
            if case .failed(let message) = session.state, message == AIAssistantService.missingKeyMessage {
                Button("Ayarlar", action: openSettings)
                    .buttonStyle(IslandCapsuleButtonStyle())
            }
            Button(action: hasText ? send : dismiss) {
                Image(systemName: hasText ? "arrow.up" : "xmark")
                    .font(.system(size: hasText ? 11 : 9, weight: .bold))
                    .foregroundStyle(hasText ? Color.black : MacBDesign.IslandToken.Ink.secondary)
                    .frame(width: 22, height: 22)
                    .background(hasText ? MacBDesign.IslandToken.navSelectedFill : MacBDesign.IslandToken.Fill.base,
                                in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(hasText ? "Gönder" : "Vazgeç")
            .accessibilityLabel(hasText ? "Gönder" : "Vazgeç")
        }
        .padding(.leading, MacBDesign.Space.regular)
        .padding(.trailing, MacBDesign.Space.tight)
        .frame(height: IslandGeometry.assistantInputHeight)
        .background(MacBDesign.IslandToken.navFill, in: Capsule())
        .overlay(Capsule().strokeBorder(MacBDesign.IslandToken.Fill.hairline, lineWidth: 0.7))
        .motion(MacBDesign.Motion.quick, value: hasText)
        .onAppear {
            typed = ""
            // Shown by the pointer passing over, not by a request to type:
            // only take the keyboard when the user asked for the field.
            if isInteractive, session.showsInput { focused = true }
        }
        .onChange(of: session.showsInput) { _, wanted in
            if isInteractive { focused = wanted }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused { session.showsInput = true }
            else if !hasText { session.showsInput = false }
        }
    }

    private func send() {
        guard hasText else { return }
        session.say(typed)
        typed = ""
        focused = false
        session.showsInput = false
    }

    private func dismiss() {
        typed = ""
        focused = false
        session.showsInput = false
    }
}
