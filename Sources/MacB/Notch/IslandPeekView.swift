import MacBCore
import SwiftUI

/// One compact line of live status shown while the pointer rests on the island.
///
/// The peek never becomes a second panel: it is a single row of chips whose
/// width follows the content, so an idle Mac shows a short strip instead of a
/// wide empty card.
struct PeekChip: Identifiable, Equatable {
    enum Leading: Equatable {
        case symbol(String)
        case artwork
    }

    let id: String
    let leading: Leading
    let text: String
    let detail: String?
    let isAccent: Bool
    /// Remaining share in 0...1, drawn as a hairline under the chip. The number
    /// beside it says how much is left; the bar says it without being read.
    var progress: Double?

    /// Rough width of the rendered chip. The controller sizes the panel from this,
    /// so the estimate has to live next to the view that draws it.
    var estimatedWidth: CGFloat {
        let glyph: CGFloat = 18
        let label = CGFloat(text.count) * 6.6
        let extra = detail.map { CGFloat($0.count) * 6.0 + 6 } ?? 0
        return glyph + 6 + label + extra + (id == "media" ? 24 : 0)
    }
}

struct AssistantPeekStatus: Equatable {
    let name: String
    let detail: String
    /// Remaining allowance in 0...1 when the assistant reports one.
    var remainingFraction: Double?
}

enum PeekModel {
    struct Input {
        var mediaAvailable = false
        var mediaTitle = ""
        var mediaArtist = ""
        var timerActive = false
        var timerText = ""
        var weatherSymbol: String?
        var weatherTemperature: Int?
        var shelfCount = 0
        var assistants: [AssistantPeekStatus] = []
        var batteryPercent: Double?
        var isCharging = false
    }

    /// The chips, in priority order. Everything here is already active work,
    /// so nothing is polled just to fill the strip.
    static func chips(_ input: Input) -> [PeekChip] {
        var chips: [PeekChip] = []
        if input.mediaAvailable, !input.mediaTitle.isEmpty {
            chips.append(PeekChip(id: "media", leading: .artwork,
                                    text: input.mediaTitle,
                                    detail: input.mediaArtist.isEmpty ? nil : input.mediaArtist,
                                    isAccent: false))
        }
        if input.timerActive {
            chips.append(PeekChip(id: "timer", leading: .symbol("timer"),
                                    text: input.timerText, detail: nil, isAccent: true))
        }
        // A crowded strip squeezes the widest chip first, and the widest chip is
        // the track. Losing the artist keeps the title readable; keeping both
        // left "Ortaya Karışık · Stabil" as "Or… S".
        let crowded = input.assistants.count + (input.timerActive ? 1 : 0) >= 2
        if crowded, let media = chips.firstIndex(where: { $0.id == "media" }) {
            chips[media] = PeekChip(id: "media", leading: .artwork, text: input.mediaTitle,
                                    detail: nil, isAccent: false)
        }
        for assistant in input.assistants.prefix(max(0, 3 - chips.count)) {
            chips.append(PeekChip(id: "assistant-\(assistant.name)", leading: .symbol("sparkles"),
                                    text: assistant.name, detail: assistant.detail, isAccent: true,
                                    progress: assistant.remainingFraction))
        }
        if input.shelfCount > 0 {
            chips.append(PeekChip(id: "shelf", leading: .symbol("tray.full.fill"),
                                    text: "\(input.shelfCount)", detail: nil, isAccent: false))
        }
        if let temperature = input.weatherTemperature {
            chips.append(PeekChip(id: "weather", leading: .symbol(input.weatherSymbol ?? "cloud.fill"),
                                    text: "\(temperature)°", detail: nil, isAccent: false))
        }
        // Battery earns a chip only when it is doing something worth saying:
        // charging, or low enough to change what you do next. A permanent
        // percentage is the menu bar's job, not the island's.
        if let percent = input.batteryPercent, input.isCharging || percent <= 20 {
            chips.append(PeekChip(id: "battery",
                                    leading: .symbol(input.isCharging ? "bolt.fill" : "battery.25"),
                                    text: "\(Int(percent))%", detail: nil,
                                    isAccent: input.isCharging || percent <= 10))
        }
        if chips.isEmpty {
            chips.append(PeekChip(id: "idle", leading: .symbol("chevron.down"),
                                    text: greeting(), detail: nil, isAccent: false))
        }
        return chips
    }

    /// The one place the peek's inputs are gathered.
    ///
    /// The controller needs them to size the panel and the view needs them to
    /// draw it. Two copies drifted apart once already, so both call this.
    @MainActor
    static func input(media: MediaService,
                      timer: TimerService,
                      weather: WeatherService,
                      shelf: ShelfStore,
                      aiActivity: AIActivityService,
                      systemMonitor: SystemMonitorService) -> Input {
        var input = Input()
        input.mediaAvailable = media.source != .none && !media.title.isEmpty
        input.mediaTitle = media.title
        input.mediaArtist = media.artist
        input.timerActive = timer.isActive
        input.timerText = timer.remainingText
        if let snapshot = weather.snapshot {
            input.weatherSymbol = snapshot.symbol
            input.weatherTemperature = snapshot.temperature
        }
        input.shelfCount = shelf.items.count
        input.assistants = aiActivity.statuses.map {
            AssistantPeekStatus(name: $0.kind.rawValue, detail: $0.detail,
                                remainingFraction: $0.usage?.remainingPercent.map { $0 / 100 })
        }
        input.batteryPercent = systemMonitor.snapshot.batteryPercent
        input.isCharging = systemMonitor.snapshot.isCharging
        return input
    }

    /// Panel width for the given chips, capped so a long track title cannot stretch the strip.
    static func width(for chips: [PeekChip]) -> CGFloat {
        let content = chips.reduce(0) { $0 + $1.estimatedWidth } + CGFloat(max(0, chips.count - 1)) * 18
        return min(IslandGeometry.peekMaximumWidth, max(200, content + 36))
    }

    static func greeting() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Günaydın"
        case 12..<18: return "İyi günler"
        default: return "İyi akşamlar"
        }
    }

}

struct IslandPeekView: View {
    let chips: [PeekChip]
    let artwork: NSImage?
    let mediaIsPlaying: Bool
    let open: () -> Void
    let toggleMedia: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 9)
                }
                Button(action: chip.id == "media" ? toggleMedia : open) {
                    chipView(chip)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        chips.map { chip in [chip.text, chip.detail].compactMap { $0 }.joined(separator: " ") }
            .joined(separator: ", ")
    }

    @ViewBuilder private func chipView(_ chip: PeekChip) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            chipRow(chip)
            if let progress = chip.progress {
                quotaBar(progress)
            }
        }
        // The track is the one chip allowed to shrink, but not to nothing.
        .frame(minWidth: chip.id == "media" ? 112 : nil, alignment: .leading)
        .fixedSize(horizontal: chip.id != "media", vertical: false)
    }

    /// Orange while there is room, red once the allowance is nearly gone.
    private func quotaBar(_ progress: Double) -> some View {
        let value = min(1, max(0, progress))
        let tint: Color = value <= 0.1 ? MacBDesign.IslandToken.destructive : MacBDesign.IslandToken.accent
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(tint).frame(width: proxy.size.width * value)
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func chipRow(_ chip: PeekChip) -> some View {
        HStack(spacing: 6) {
            switch chip.leading {
            case .artwork:
                artworkView
            case .symbol(let symbol):
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(chip.isAccent ? MacBDesign.IslandToken.accent : MacBDesign.IslandToken.secondaryText)
                    .frame(width: 16)
            }
            Text(chip.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MacBDesign.IslandToken.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let detail = chip.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(MacBDesign.IslandToken.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }
            if chip.id == "media" {
                if mediaIsPlaying { PeekEqualizer() }
                Image(systemName: mediaIsPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(MacBDesign.IslandToken.primaryText)
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(0.10), in: Circle())
            }
        }
    }

    @ViewBuilder private var artworkView: some View {
        if let artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .frame(width: 20, height: 20)
                .overlay(Image(systemName: "music.note")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MacBDesign.IslandToken.secondaryText))
        }
    }
}

/// Four bars that rise and fall while audio plays.
///
/// Driven by the clock rather than by the audio itself: MacB does not tap the
/// output, and a decorative meter is not worth asking for that permission. It
/// only exists while the peek is on screen and something is actually playing.
private struct PeekEqualizer: View {
    private let phases: [Double] = [0, 0.35, 0.7, 1.05]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(phases.enumerated()), id: \.offset) { _, phase in
                    let wave = (sin(time * 5.4 + phase * .pi * 2) + 1) / 2
                    Capsule()
                        .fill(MacBDesign.IslandToken.accent)
                        .frame(width: 2, height: 4 + wave * 9)
                }
            }
            .frame(width: 14, height: 14)
        }
        .accessibilityHidden(true)
    }
}
