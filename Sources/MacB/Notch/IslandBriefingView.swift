import AppKit
import MacBCore
import SwiftUI

/// The morning briefing in the island: a greeting, then the few things worth
/// knowing before the day starts.
///
/// It used to be a stack of grey sentences — the spoken briefing, printed. That
/// is the wrong shape for something that is on screen for four seconds while
/// somebody is reaching for their coffee: a paragraph has to be read from the
/// start, and by the time you have, the island has closed. So the ear and the
/// eye get different versions of the same facts. The voice still says
/// sentences; the island shows a greeting and a row of chips, each a glyph and
/// two words, found by shape rather than by reading.
///
/// Nothing here was fetched for the occasion except the weather, and nothing
/// leaves the Mac. The voice is macOS's own, so reading it aloud costs nothing
/// and works with no key.
struct IslandBriefingView: View {
    @ObservedObject var briefing: BriefingService
    var close: () -> Void
    var talk: () -> Void

    /// Drives the one entrance: the chips arrive a beat after the greeting.
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.close) {
            HStack(spacing: MacBDesign.Space.comfortable) {
                timeOfDayTile
                Text(greeting)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacBDesign.IslandToken.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: MacBDesign.Space.close)
                closeButton
            }
            if !briefing.chips.isEmpty {
                HStack(spacing: MacBDesign.Space.snug) {
                    ForEach(briefing.chips) { chip in
                        chipView(chip)
                    }
                    Spacer(minLength: 0)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 4)
            }
            HStack(spacing: MacBDesign.Space.snug) {
                action(briefing.isSpeaking ? "Sustur" : "Oku",
                       symbol: briefing.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       isPrimary: false) {
                    briefing.isSpeaking ? briefing.stopSpeaking() : briefing.speak()
                }
                action("MacB ile konuş", symbol: "waveform", isPrimary: true) {
                    close()
                    talk()
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .motion(MacBDesign.Motion.settle, value: hasAppeared)
        .onAppear { hasAppeared = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(briefing.lines.joined(separator: ". "))
    }

    /// The greeting, with the spoken first line as the fallback: a briefing
    /// that arrives before the greeting is computed still says something.
    private var greeting: String {
        briefing.greeting.isEmpty ? (briefing.lines.first ?? "") : briefing.greeting
    }

    // MARK: - Pieces

    /// A soft tile rather than a bare glyph. On black, an orange symbol on its
    /// own reads as a warning; given a tinted plate it reads as an identity.
    private var timeOfDayTile: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(LinearGradient(colors: [MacBDesign.IslandToken.accent.opacity(0.28),
                                          MacBDesign.IslandToken.accent.opacity(0.10)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(MacBDesign.IslandToken.accent.opacity(0.28), lineWidth: 1)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MacBDesign.IslandToken.accent)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(MacBDesign.IslandToken.Ink.secondary)
                .frame(width: 20, height: 20)
                .background(MacBDesign.IslandToken.Fill.low, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Kapat")
        .accessibilityLabel("Brifingi kapat")
    }

    private func chipView(_ chip: Briefing.Chip) -> some View {
        HStack(spacing: MacBDesign.Space.tight) {
            Image(systemName: chip.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(chip.isUrgent ? MacBDesign.IslandToken.accent
                                               : MacBDesign.IslandToken.Ink.secondary)
            Text(chip.text)
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                .foregroundStyle(chip.isUrgent ? MacBDesign.IslandToken.accent
                                               : MacBDesign.IslandToken.Ink.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, MacBDesign.Space.close)
        .padding(.vertical, 5)
        .background(chip.isUrgent ? MacBDesign.IslandToken.accent.opacity(0.14)
                                  : MacBDesign.IslandToken.Fill.low,
                    in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chip.text)
    }

    private func action(_ title: String, symbol: String, isPrimary: Bool,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: MacBDesign.Space.tight) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
            }
            .padding(.horizontal, MacBDesign.Space.comfortable)
            .frame(height: 28)
        }
        .buttonStyle(IslandCapsuleButtonStyle(isPrimary: isPrimary))
        .accessibilityLabel(title)
    }

    /// The sun in the morning, something quieter later on — the briefing can be
    /// asked for at any hour, not only the one it normally arrives at.
    private var symbol: String {
        switch Calendar.current.component(.hour, from: briefing.givenAt ?? Date()) {
        case 5..<11: return "sun.horizon.fill"
        case 11..<18: return "sun.max.fill"
        case 18..<22: return "sunset.fill"
        default: return "moon.stars.fill"
        }
    }
}

/// The island's own button: a capsule on black, which the system's button is
/// not. AppKit's default draws a light grey rectangle designed for a window,
/// and three of them in a row on the island looked like a dialog had been
/// pasted onto the notch.
struct IslandCapsuleButtonStyle: ButtonStyle {
    var isPrimary = false
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isPrimary ? MacBDesign.IslandToken.accent
                                       : MacBDesign.IslandToken.Ink.primary)
            .background(background(pressed: configuration.isPressed), in: Capsule())
            .overlay {
                Capsule().strokeBorder(isPrimary ? MacBDesign.IslandToken.accent.opacity(0.30)
                                                 : MacBDesign.IslandToken.Fill.low,
                                       lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : MacBDesign.Motion.snap, value: configuration.isPressed)
            .animation(reduceMotion ? nil : MacBDesign.Motion.instant, value: isHovering)
            .onHover { isHovering = $0 }
    }

    private func background(pressed: Bool) -> Color {
        if isPrimary {
            return MacBDesign.IslandToken.accent.opacity(pressed ? 0.30 : (isHovering ? 0.22 : 0.15))
        }
        if pressed { return MacBDesign.IslandToken.Fill.strong }
        return isHovering ? MacBDesign.IslandToken.Fill.raised : MacBDesign.IslandToken.Fill.low
    }
}
