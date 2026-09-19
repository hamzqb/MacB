import AppKit
import MacBCore
import SwiftUI

/// The voice assistant inside the island: an orb that answers to the voice,
/// what has just been said, anything waiting to be allowed, and a line to type
/// in when talking is not an option.
struct IslandAssistantView: View {
    @ObservedObject var session: JarvisSession
    var close: () -> Void
    var openSettings: () -> Void
    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: MacBDesign.Space.regular) {
            HStack(spacing: MacBDesign.Space.comfortable) {
                JarvisOrb(state: session.state, input: session.inputLevel, output: session.outputLevel)
                    .frame(width: 64, height: 64)
                    .accessibilityLabel(statusText)
                VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                    HStack(spacing: MacBDesign.Space.snug) {
                        Text("MacB")
                            .font(.system(size: MacBDesign.TypeScale.body, weight: .semibold))
                        if session.isActive {
                            HStack(spacing: 4) {
                                Circle().fill(Color.red).frame(width: 5, height: 5)
                                Text("canlı · mikrofon açık").font(.system(size: MacBDesign.TypeScale.micro, weight: .medium))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(MacBDesign.IslandToken.Fill.base, in: Capsule())
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Text(statusText)
                        .font(.system(size: MacBDesign.TypeScale.caption))
                        .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if case .failed = session.state {
                    Button("Yeniden dene") { session.start() }
                        .controlSize(.small)
                }
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(MacBDesign.IslandToken.Fill.base, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Konuşmayı bitir")
                .accessibilityLabel("Konuşmayı bitir")
            }
            if let confirmation = session.confirmation {
                confirmationCard(confirmation)
            } else if !session.lines.isEmpty {
                transcript
            }
            inputRow
        }
        .foregroundStyle(MacBDesign.IslandToken.Ink.primary)
        .onAppear { typed = "" }
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
                VStack(alignment: .leading, spacing: MacBDesign.Space.snug) {
                    ForEach(session.lines) { line in
                        Text(line.text)
                            .font(.system(size: MacBDesign.TypeScale.caption,
                                          weight: line.speaker == .user ? .medium : .regular))
                            .foregroundStyle(line.speaker == .jarvis ? MacBDesign.IslandToken.Ink.primary
                                                                     : MacBDesign.IslandToken.Ink.tertiary)
                            .frame(maxWidth: .infinity, alignment: line.speaker == .jarvis ? .leading : .trailing)
                            .multilineTextAlignment(line.speaker == .jarvis ? .leading : .trailing)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: session.lines.last?.text) { _, _ in
                if let last = session.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func confirmationCard(_ confirmation: JarvisSession.Confirmation) -> some View {
        VStack(spacing: MacBDesign.Space.snug) {
            Label(confirmation.text, systemImage: Self.symbol(for: confirmation.tool))
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: MacBDesign.Space.regular) {
                Button("Reddet") { session.answerConfirmation(false) }
                // No Return shortcut on purpose: a Return meant for the text
                // field must never become a yes to sending the screen.
                Button("İzin ver") { session.answerConfirmation(true) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(MacBDesign.Space.regular)
        .frame(maxWidth: .infinity)
        .background(MacBDesign.IslandToken.Fill.base, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var inputRow: some View {
        HStack(spacing: MacBDesign.Space.snug) {
            TextField("Yaz ya da konuş…", text: $typed)
                .textFieldStyle(.plain)
                .font(.system(size: MacBDesign.TypeScale.caption))
                .focused($typing)
                .onSubmit(send)
                .disabled(!session.isActive)
                .accessibilityLabel("MacB'ye yaz")
            if case .failed(let message) = session.state, message == AIAssistantService.missingKeyMessage {
                Button("Ayarlar", action: openSettings).controlSize(.small)
            }
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .foregroundStyle(MacBDesign.IslandToken.accent)
            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || !session.isActive)
            .accessibilityLabel("Gönder")
        }
        .padding(.horizontal, MacBDesign.Space.regular)
        .frame(height: 30)
        .background(MacBDesign.IslandToken.Fill.hairline, in: Capsule())
    }

    private func send() {
        session.say(typed)
        typed = ""
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
