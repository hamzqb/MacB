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

    /// What is being searched for. Not persisted: a search is about the next
    /// ten seconds, and a filter still applied tomorrow is a list with things
    /// missing from it for no visible reason.
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var visible: [ClipboardShelfItem] {
        clipboard.items.filter { item in
            filter.matches(item) && ClipboardSearch.matches(haystack: searchable(item), query: query)
        }
    }

    /// Everything about an entry worth typing at.
    ///
    /// The visible text, the link and the file names — an image has none of
    /// these and is found by its filter rather than by search, which is correct:
    /// nobody remembers the words inside a screenshot.
    private func searchable(_ item: ClipboardShelfItem) -> [String?] {
        var fields: [String?] = [item.text, item.urlString, item.colorHex]
        fields.append(contentsOf: (item.filePaths ?? []).map { ($0 as NSString).lastPathComponent })
        return fields
    }

    private func count(_ value: ClipboardFilter) -> Int {
        clipboard.items.filter(value.matches).count
    }

    private var removableCount: Int { clipboard.items.filter { !$0.isFavorite }.count }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacBDesign.Space.regular) {
            HStack(spacing: MacBDesign.Space.regular) {
                filterRow
                trashButton
            }
            searchField
            if visible.isEmpty {
                emptyState
            } else {
                // A list, not a wall of cards: what was copied is text, and
                // text is read down a column.
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5)
                            }
                            ClipboardRow(item: item, clipboard: clipboard, notify: notify)
                        }
                    }
                }
                .frame(height: IslandGeometry.clipboardRowHeight * CGFloat(IslandGeometry.clipboardVisibleRows))
            }
        }
    }

    /// Type part of what you copied.
    ///
    /// A clipboard history is the one list where scrolling is the wrong tool:
    /// somebody knows exactly what they copied and only needs to say which one.
    /// The filters above answer "what kind of thing"; this answers "the one
    /// with this in it".
    private var searchField: some View {
        HStack(spacing: MacBDesign.Space.snug) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
            TextField("Ara", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: MacBDesign.TypeScale.caption))
                .foregroundStyle(MacBDesign.IslandToken.primaryText)
                .focused($searchFocused)
                .accessibilityLabel("Panoda ara")
            if !query.isEmpty {
                Button { query = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: MacBDesign.TypeScale.caption))
                        .foregroundStyle(MacBDesign.IslandToken.Ink.faint)
                }
                .buttonStyle(.plain)
                .help("Aramayı temizle")
                .accessibilityLabel("Aramayı temizle")
            }
        }
        .padding(.horizontal, MacBDesign.Space.close)
        .frame(height: 26)
        .background(Color.white.opacity(0.07), in: Capsule())
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
        .layoutPriority(1)
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
            .foregroundStyle(isSelected ? Color.white
                             : (total > 0 ? Color.white.opacity(0.7) : Color.white.opacity(0.32)))
            .padding(.horizontal, MacBDesign.Space.comfortable)
            .frame(height: MacBDesign.IslandToken.pillHeight)
            .background(isSelected ? AnyShapeStyle(Color.white.opacity(0.14)) : AnyShapeStyle(Color.clear),
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
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(removableCount == 0)
        .help("Favori olmayan kayıtları sil")
        .accessibilityLabel("Favori olmayan \(removableCount) pano kaydını sil")
    }

    private var emptyState: some View {
        VStack(spacing: MacBDesign.Space.close) {
            Image(systemName: isSearching ? "magnifyingglass" : filter.symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.28))
            // An empty list during a search is not an empty clipboard, and
            // saying "kopyaladıkların burada birikir" to somebody who has just
            // typed four letters is answering a question they did not ask.
            Text(isSearching ? "Aramana uyan bir şey yok." : filter.emptyMessage)
                .font(.system(size: MacBDesign.TypeScale.caption))
                .foregroundStyle(MacBDesign.IslandToken.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandGeometry.clipboardRowHeight * 2)
        .accessibilityElement(children: .combine)
    }
}

/// One entry: what it is on the left, what it says in the middle, when it was
/// copied on the right. Clicking copies it back; the star and the bin appear
/// under the pointer.
private struct ClipboardRow: View {
    let item: ClipboardShelfItem
    @ObservedObject var clipboard: ClipboardShelfStore
    var notify: (String, String) -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            clipboard.copy(item)
            notify("doc.on.clipboard", "Kopyalandı")
        } label: {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 5) {
                        if let icon = sourceIcon {
                            Image(nsImage: icon).resizable().frame(width: 11, height: 11)
                        }
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if isHovering {
                    iconButton(item.isFavorite ? "star.fill" : "star", label: "Favori",
                               tint: item.isFavorite ? .yellow : .white.opacity(0.6)) {
                        clipboard.toggleFavorite(item)
                    }
                    iconButton("trash", label: "Sil", tint: MacBDesign.IslandToken.destructive) {
                        clipboard.remove(item)
                    }
                } else if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                }
                Text(relativeTime)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.32))
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(height: IslandGeometry.clipboardRowHeight)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onDrag { NSItemProvider(object: item.text as NSString) }
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var thumbnail: some View {
        Group {
            if let data = item.imageData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if let hex = item.colorHex, let color = Color(hex: hex) {
                color
            } else {
                Color.white.opacity(0.07)
                    .overlay(Image(systemName: item.kind.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55)))
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var title: String {
        if let hex = item.colorHex { return hex.uppercased() }
        if item.kind == .image { return "Görsel" }
        let line = item.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? item.text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Boş" : trimmed
    }

    private var subtitle: String {
        switch item.kind {
        case .text: return "Metin"
        case .image: return "Görsel"
        case .files: return (item.filePaths?.count).map { "\($0) dosya" } ?? "Dosya"
        case .link: return item.urlString ?? "Bağlantı"
        case .color: return "Renk"
        }
    }

    private func iconButton(_ symbol: String, label: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(IslandPressStyle())
        .help(label)
        .accessibilityLabel(label)
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
