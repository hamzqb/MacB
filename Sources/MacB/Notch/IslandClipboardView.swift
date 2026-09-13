import AppKit
import MacBCore
import SwiftUI
import UniformTypeIdentifiers

enum ClipboardFilter: String, CaseIterable, Hashable {
    case recent, images, colors, text, files, links, favorites

    /// Short enough to sit on one line at every panel width. The long form only
    /// appears in the accessibility label and the tooltip.
    var title: String {
        switch self {
        case .recent: return "Son"
        case .images: return "Görsel"
        case .colors: return "Renk"
        case .text: return "Metin"
        case .files: return "Dosya"
        case .links: return "Bağlantı"
        case .favorites: return "Favori"
        }
    }

    var longTitle: String {
        switch self {
        case .recent: return "Son kullanılanlar"
        case .images: return "Görseller"
        case .colors: return "Renkler"
        case .text: return "Metin"
        case .files: return "Dosyalar"
        case .links: return "Bağlantılar"
        case .favorites: return "Favoriler"
        }
    }

    var symbol: String {
        switch self {
        case .recent: return "clock"
        case .images: return "photo"
        case .colors: return "paintpalette"
        case .text: return "textformat"
        case .files: return "doc"
        case .links: return "link"
        case .favorites: return "star"
        }
    }

    /// What the gallery says when this filter has nothing to show.
    var emptyMessage: String {
        switch self {
        case .recent: return "Kopyaladıkların burada birikir."
        case .images: return "Henüz görsel kopyalamadın."
        case .colors: return "Kopyaladığın HEX renkler burada durur."
        case .text: return "Henüz metin kopyalamadın."
        case .files: return "Kopyaladığın dosyalar burada görünür."
        case .links: return "Henüz bağlantı kopyalamadın."
        case .favorites: return "Bir kartı yıldızlayınca buraya düşer."
        }
    }

    func matches(_ item: ClipboardShelfItem) -> Bool {
        switch self {
        case .recent: return true
        case .images: return item.kind == .image
        case .colors: return item.kind == .color
        case .text: return item.kind == .text
        case .files: return item.kind == .files
        case .links: return item.kind == .link
        case .favorites: return item.isFavorite
        }
    }
}

/// A horizontal gallery of clipboard entries, one card per entry.
struct IslandClipboardView: View {
    @ObservedObject var clipboard: ClipboardShelfStore
    @Binding var filter: ClipboardFilter
    var notify: (String, String) -> Void

    private var visible: [ClipboardShelfItem] { clipboard.items.filter { filter.matches($0) } }

    private func count(_ value: ClipboardFilter) -> Int {
        clipboard.items.filter(value.matches).count
    }

    private var removableCount: Int { clipboard.items.filter { !$0.isFavorite }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.regular) {
            HStack(spacing: MacBDesign.Space.regular) {
                filterRow
                trashButton
            }
            if visible.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MacBDesign.Space.regular) {
                        ForEach(visible) { item in
                            ClipboardCard(item: item, clipboard: clipboard, notify: notify)
                        }
                    }
                    .padding(.bottom, MacBDesign.Space.hair)
                }
                .scrollClipDisabled()
            }
        }
    }

    /// The filters scroll rather than shrink. A truncated one-word label reads as
    /// a bug, and the row has to survive a narrow panel intact.
    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MacBDesign.Space.snug) {
                ForEach(ClipboardFilter.allCases, id: \.self) { value in
                    pill(value)
                }
            }
            .padding(.trailing, MacBDesign.Space.hair)
        }
        .scrollClipDisabled()
    }

    private func pill(_ value: ClipboardFilter) -> some View {
        let isSelected = value == filter
        let total = count(value)
        return Button { filter = value } label: {
            HStack(spacing: MacBDesign.Space.snug) {
                Image(systemName: value.symbol)
                    .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                Text(value.title)
                    .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium))
                if total > 0 {
                    Text("\(total)")
                        .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                        .monospacedDigit()
                        .opacity(isSelected ? 0.55 : 0.45)
                }
            }
            .fixedSize()
            .foregroundStyle(isSelected ? Color.black
                             : (total > 0 ? MacBDesign.IslandToken.primaryText
                                : MacBDesign.IslandToken.tertiaryText))
            .padding(.horizontal, MacBDesign.Space.comfortable)
            .frame(height: MacBDesign.IslandToken.pillHeight)
            .background(isSelected ? MacBDesign.IslandToken.navSelectedFill : MacBDesign.IslandToken.navFill,
                        in: Capsule())
        }
        .buttonStyle(.plain)
        .help(value.longTitle)
        .accessibilityLabel("\(value.longTitle), \(total) kayıt")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Icon only. A red sentence beside the filters competes with them for
    /// attention, and this action is destructive enough to stay quiet until wanted.
    private var trashButton: some View {
        Button {
            let removable = clipboard.items.filter { !$0.isFavorite }
            removable.forEach(clipboard.remove)
            notify("trash", "\(removable.count) öğe silindi")
        } label: {
            Image(systemName: "trash")
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                .foregroundStyle(removableCount > 0
                                 ? MacBDesign.IslandToken.destructive
                                 : MacBDesign.IslandToken.tertiaryText)
                .frame(width: MacBDesign.IslandToken.pillHeight,
                       height: MacBDesign.IslandToken.pillHeight)
                .background(MacBDesign.IslandToken.navFill, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(removableCount == 0)
        .help("Favori olmayan kayıtları sil")
        .accessibilityLabel("Favori olmayan \(removableCount) pano kaydını sil")
    }

    private var emptyState: some View {
        VStack(spacing: MacBDesign.Space.close) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [MacBDesign.IslandToken.Fill.raised, MacBDesign.IslandToken.Fill.hairline],
                                         center: .topLeading, startRadius: 1, endRadius: 40))
                Circle().strokeBorder(MacBDesign.IslandToken.Fill.base, lineWidth: 0.8)
                Image(systemName: filter.symbol)
                    .font(.system(size: MacBDesign.TypeScale.title, weight: .medium))
                    .foregroundStyle(MacBDesign.IslandToken.secondaryText)
            }
            .frame(width: 40, height: 40)
            Text(filter.emptyMessage)
                .font(.system(size: MacBDesign.TypeScale.caption))
                .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandGeometry.clipboardCardHeight)
        .background(MacBDesign.IslandToken.widgetFill.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ClipboardCard: View {
    let item: ClipboardShelfItem
    @ObservedObject var clipboard: ClipboardShelfStore
    var notify: (String, String) -> Void

    @State private var isHovering = false

    private let size = CGSize(width: 132, height: 104)

    var body: some View {
        Button {
            clipboard.copy(item)
            notify("doc.on.clipboard", "Kopyalandı")
        } label: {
            ZStack(alignment: .bottomLeading) {
                background
                badge
                if isHovering { actions }
                if item.isFavorite { favoriteMark }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onDrag { NSItemProvider(object: item.text as NSString) }
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var background: some View {
        if let data = item.imageData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else if let hex = item.colorHex, let color = Color(hex: hex) {
            color
        } else {
            MacBDesign.IslandToken.widgetFill
            Text(item.text)
                .font(.system(size: MacBDesign.TypeScale.micro))
                .foregroundStyle(MacBDesign.IslandToken.primaryText.opacity(0.8))
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(MacBDesign.Space.close)
        }
    }

    @ViewBuilder private var badge: some View {
        HStack(spacing: MacBDesign.Space.tight) {
            if let icon = sourceIcon {
                Image(nsImage: icon).resizable().frame(width: 12, height: 12)
            }
            Text(item.colorHex ?? relativeTime)
                .font(.system(size: MacBDesign.TypeScale.micro, weight: item.colorHex == nil ? .regular : .bold))
        }
        .foregroundStyle(labelColor)
        .padding(.horizontal, MacBDesign.Space.snug)
        .padding(.vertical, MacBDesign.Space.tight)
        .background(item.colorHex == nil ? AnyShapeStyle(.black.opacity(0.55)) : AnyShapeStyle(.clear), in: Capsule())
        .padding(MacBDesign.Space.close)
    }

    private var actions: some View {
        VStack {
            HStack {
                iconButton(item.isFavorite ? "star.fill" : "star", label: "Favori") { clipboard.toggleFavorite(item) }
                Spacer()
                iconButton("trash", label: "Sil") { clipboard.remove(item) }
            }
            Spacer()
        }
        .padding(MacBDesign.Space.snug)
    }

    private var favoriteMark: some View {
        VStack {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: MacBDesign.TypeScale.micro))
                    .foregroundStyle(.yellow)
                    .padding(MacBDesign.Space.tight)
                    .background(.black.opacity(0.45), in: Circle())
                Spacer()
            }
            Spacer()
        }
        .padding(MacBDesign.Space.snug)
        .allowsHitTesting(false)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var labelColor: Color {
        guard let hex = item.colorHex, let color = NSColor(hex: hex) else { return .white }
        return color.usingColorSpace(.sRGB)?.brightnessComponent ?? 1 > 0.6 ? .black : .white
    }

    private var sourceIcon: NSImage? {
        guard let bundle = item.sourceBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: item.copiedAt, relativeTo: Date())
    }

    private var accessibilityText: String {
        if let hex = item.colorHex { return "Renk \(hex), kopyalamak için tıkla" }
        if item.kind == .image { return "Görsel, \(relativeTime), kopyalamak için tıkla" }
        return "\(item.text.prefix(60)), kopyalamak için tıkla"
    }
}

extension Color {
    init?(hex: String) {
        guard let color = NSColor(hex: hex) else { return nil }
        self.init(nsColor: color)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
                  green: CGFloat((number >> 8) & 0xFF) / 255,
                  blue: CGFloat(number & 0xFF) / 255,
                  alpha: 1)
    }
}
