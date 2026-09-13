import MacBCore
import SwiftUI

/// The island announcing a system change: a new track, the charger, the lid.
///
/// One line, same height as the peek, so the panel slides open and shut without
/// changing shape. The level bar replaces the macOS square that normally lands
/// in the middle of whatever you are looking at.
struct IslandEventView: View {
    let event: IslandEvent
    let artwork: NSImage?

    private var tint: Color {
        switch event.kind {
        case .batteryLow: return MacBDesign.IslandToken.destructive
        case .charging: return Color(nsColor: .systemGreen)
        default: return MacBDesign.IslandToken.accent
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacBDesign.IslandToken.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
                if let detail = event.detail, event.progress == nil {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let progress = event.progress {
                level(progress)
                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                        .frame(width: IslandGeometry.eventLevelDetailWidth, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([event.title, event.detail].compactMap { $0 }.joined(separator: " "))
    }

    @ViewBuilder private var leading: some View {
        if event.kind == .nowPlaying, let artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: event.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private func level(_ progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MacBDesign.IslandToken.Fill.raised)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(1, max(0, progress)))
            }
        }
        .frame(width: IslandGeometry.eventLevelWidth, height: 4)
        .animation(.easeOut(duration: 0.12), value: progress)
    }
}
