import AppKit
import MacBCore
import SwiftUI

/// The morning briefing in the island: a greeting, then the few things worth
/// knowing before the day starts.
///
/// Nothing here was fetched for the occasion except the weather, and nothing
/// leaves the Mac. The voice is macOS's own, so reading it aloud costs nothing
/// and works with no key.
struct IslandBriefingView: View {
    @ObservedObject var briefing: BriefingService
    var close: () -> Void
    var talk: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.regular) {
            HStack(spacing: MacBDesign.Space.comfortable) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(MacBDesign.IslandToken.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: MacBDesign.Space.hair) {
                    ForEach(Array(briefing.lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: index == 0 ? MacBDesign.TypeScale.emphasis
                                                           : MacBDesign.TypeScale.caption,
                                          weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? MacBDesign.IslandToken.Ink.primary
                                                        : MacBDesign.IslandToken.Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(MacBDesign.IslandToken.Fill.base, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Kapat")
                .accessibilityLabel("Brifingi kapat")
            }
            HStack(spacing: MacBDesign.Space.regular) {
                Button {
                    briefing.isSpeaking ? briefing.stopSpeaking() : briefing.speak()
                } label: {
                    Label(briefing.isSpeaking ? "Sustur" : "Oku",
                          systemImage: briefing.isSpeaking ? "speaker.slash" : "speaker.wave.2")
                }
                Button {
                    close()
                    talk()
                } label: {
                    Label("MacB ile konuş", systemImage: "person.wave.2")
                }
                Spacer(minLength: 8)
            }
            .controlSize(.small)
        }
        .foregroundStyle(MacBDesign.IslandToken.Ink.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(briefing.lines.joined(separator: ". "))
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
