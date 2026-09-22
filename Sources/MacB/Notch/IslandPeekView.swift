import AppKit
import MacBCore
import SwiftUI

/// The strip shown while the pointer rests on the island: what is going on
/// right now, and the three things most often wanted next.
///
/// Every part earns its place. Nothing playing means no track; nothing copied
/// means no clipboard; an empty shelf means no shelf. What is left is the row
/// of quick actions, so the strip is never an empty card.
enum PeekPart: Equatable, Identifiable {
    case media(title: String, artist: String)
    case timer(String)
    case clipboard(text: String, symbol: String)
    case shelf(count: Int)
    /// Always last, and always there.
    case actions

    var id: String {
        switch self {
        case .media: return "media"
        case .timer: return "timer"
        case .clipboard: return "clipboard"
        case .shelf: return "shelf"
        case .actions: return "actions"
        }
    }

    /// Roughly how wide it draws. The controller sizes the panel from this, so
    /// the estimate lives beside the view that draws it.
    var estimatedWidth: CGFloat {
        switch self {
        case .media(let title, let artist):
            let text = max(CGFloat(title.count), CGFloat(artist.count)) * 6.4
            return 26 + 8 + min(150, max(70, text)) + 26
        case .timer(let text): return 24 + CGFloat(text.count) * 7.4
        case .clipboard(let text, _): return 24 + min(130, max(60, CGFloat(text.count) * 6.2))
        case .shelf: return 58
        case .actions: return CGFloat(PeekAction.allCases.count) * 30 + 8
        }
    }
}

/// What the strip can do without opening anything.
enum PeekAction: String, CaseIterable, Identifiable {
    case assistant, screenshot, keepAwake

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .assistant: return "sparkles"
        case .screenshot: return "camera.viewfinder"
        case .keepAwake: return "cup.and.heat.waves.fill"
        }
    }

    var label: String {
        switch self {
        case .assistant: return "MacB'ye sor"
        case .screenshot: return "Ekran görüntüsü al"
        case .keepAwake: return "Uyanık tut"
        }
    }
}

enum PeekModel {
    struct Input {
        var mediaAvailable = false
        var mediaTitle = ""
        var mediaArtist = ""
        var timerActive = false
        var timerText = ""
        var clipboardText = ""
        var clipboardSymbol = "text.quote"
        var shelfCount = 0
    }

    /// The parts, in the order they are drawn.
    static func parts(_ input: Input) -> [PeekPart] {
        var parts: [PeekPart] = []
        if input.mediaAvailable, !input.mediaTitle.isEmpty {
            parts.append(.media(title: input.mediaTitle, artist: input.mediaArtist))
        }
        if input.timerActive { parts.append(.timer(input.timerText)) }
        if !input.clipboardText.isEmpty {
            parts.append(.clipboard(text: input.clipboardText, symbol: input.clipboardSymbol))
        }
        if input.shelfCount > 0 { parts.append(.shelf(count: input.shelfCount)) }
        parts.append(.actions)
        return parts
    }

    /// The one place the strip's inputs are gathered: the controller needs
    /// them to size the panel and the view to draw it, and two copies drifted
    /// apart once already.
    ///
    /// The clipboard is read only when it is not behind a lock, and only its
    /// first line: the strip is a hint, not the history.
    @MainActor
    static func input(media: MediaService,
                      timer: TimerService,
                      shelf: ShelfStore,
                      clipboard: ClipboardShelfStore,
                      clipboardLocked: Bool) -> Input {
        var input = Input()
        input.mediaAvailable = media.source != .none && !media.title.isEmpty
        input.mediaTitle = media.title
        input.mediaArtist = media.artist
        input.timerActive = timer.isActive
        input.timerText = timer.remainingText
        if !clipboardLocked, let latest = clipboard.items.first {
            input.clipboardText = Self.oneLine(latest.text)
            input.clipboardSymbol = latest.kind.symbol
        }
        input.shelfCount = shelf.items.count
        return input
    }

    static func oneLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 34 ? String(trimmed.prefix(33)) + "…" : trimmed
    }

    /// Panel width for the given parts, capped so a long track title cannot
    /// stretch the strip.
    static func width(for parts: [PeekPart]) -> CGFloat {
        let content = parts.reduce(0) { $0 + $1.estimatedWidth } + CGFloat(max(0, parts.count - 1)) * 20
        return min(IslandGeometry.peekMaximumWidth, max(220, content + 36))
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
    let parts: [PeekPart]
    let artwork: NSImage?
    let tint: Color?
    let mediaIsPlaying: Bool
    let keepAwakeIsOn: Bool
    let open: () -> Void
    let toggleMedia: () -> Void
    let openClipboard: () -> Void
    let openShelf: () -> Void
    let run: (PeekAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.1))
                        .frame(width: 1, height: 20)
                        .padding(.horizontal, 10)
                }
                view(for: part)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func view(for part: PeekPart) -> some View {
        switch part {
        case .media(let title, let artist): mediaPart(title: title, artist: artist)
        case .timer(let text): timerPart(text)
        case .clipboard(let text, let symbol): clipboardPart(text: text, symbol: symbol)
        case .shelf(let count): shelfPart(count)
        case .actions: actionsPart
        }
    }

    // MARK: - Parts

    /// The cover, the title over the artist, and one button that plays or
    /// pauses. Pressing anywhere else opens the player.
    private func mediaPart(title: String, artist: String) -> some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 8) {
                    artworkView
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !artist.isEmpty {
                            Text(artist)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(tint ?? .white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: 150, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(IslandPressStyle())
            .accessibilityLabel("\(title), \(artist). Oynatıcıyı aç")
            Button(action: toggleMedia) {
                Image(systemName: mediaIsPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(IslandPressStyle())
            .accessibilityLabel(mediaIsPlaying ? "Duraklat" : "Oynat")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func timerPart(_ text: String) -> some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacBDesign.IslandToken.accent)
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle())
        .accessibilityLabel("Zamanlayıcı \(text)")
    }

    private func clipboardPart(text: String, symbol: String) -> some View {
        Button(action: openClipboard) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 150, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle())
        .accessibilityLabel("Son kopyalanan: \(text). Panoyu aç")
    }

    private func shelfPart(_ count: Int) -> some View {
        Button(action: openShelf) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle())
        .accessibilityLabel("Rafta \(count) öğe. Rafı aç")
    }

    private var actionsPart: some View {
        HStack(spacing: 2) {
            ForEach(PeekAction.allCases) { action in
                let isOn = action == .keepAwake && keepAwakeIsOn
                Button { run(action) } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? MacBDesign.IslandToken.accent : .white.opacity(0.78))
                        .frame(width: 28, height: 28)
                        .background {
                            if isOn { Circle().fill(MacBDesign.IslandToken.accent.opacity(0.16)) }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(IslandPressStyle())
                .help(action.label)
                .accessibilityLabel(action.label)
            }
        }
    }

    @ViewBuilder private var artworkView: some View {
        if let artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6)))
        }
    }
}
