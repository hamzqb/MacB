import AppKit
import Combine

struct RecentFileItem: Identifiable {
    let id: String
    let url: URL
    let name: String
    let modifiedAt: Date
    let isDirectory: Bool
}

enum ClipboardItemKind: String, Codable {
    case text, image, files, link, color

    var symbol: String {
        switch self {
        case .text: return "text.quote"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        }
    }
}

struct ClipboardShelfItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let copiedAt: Date
    var isFavorite: Bool = false
    var kind: ClipboardItemKind = .text
    var imageData: Data?
    var filePaths: [String]?
    var urlString: String?
    var colorHex: String?
    var sourceBundleIdentifier: String?

    init(id: UUID, text: String, copiedAt: Date, isFavorite: Bool = false,
         kind: ClipboardItemKind = .text, imageData: Data? = nil, filePaths: [String]? = nil,
         urlString: String? = nil, colorHex: String? = nil, sourceBundleIdentifier: String? = nil) {
        self.id = id; self.text = text; self.copiedAt = copiedAt; self.isFavorite = isFavorite
        self.kind = kind; self.imageData = imageData; self.filePaths = filePaths
        self.urlString = urlString; self.colorHex = colorHex; self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, copiedAt, isFavorite, kind, imageData, filePaths, urlString, colorHex, sourceBundleIdentifier
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        copiedAt = try values.decode(Date.self, forKey: .copiedAt)
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        kind = try values.decodeIfPresent(ClipboardItemKind.self, forKey: .kind) ?? .text
        imageData = try values.decodeIfPresent(Data.self, forKey: .imageData)
        filePaths = try values.decodeIfPresent([String].self, forKey: .filePaths)
        urlString = try values.decodeIfPresent(String.self, forKey: .urlString)
        colorHex = try values.decodeIfPresent(String.self, forKey: .colorHex)
        sourceBundleIdentifier = try values.decodeIfPresent(String.self, forKey: .sourceBundleIdentifier)
    }
}

@MainActor final class FavoriteWindowStore: ObservableObject {
    @Published private(set) var signatures: Set<String> = []
    private let defaults: UserDefaults
    private let key = "favoriteWindowSignatures"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        signatures = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func isFavorite(_ window: WindowRecord) -> Bool { signatures.contains(signature(for: window)) }

    func toggle(_ window: WindowRecord) {
        let value = signature(for: window)
        if signatures.contains(value) { signatures.remove(value) } else { signatures.insert(value) }
        defaults.set(Array(signatures).sorted(), forKey: key)
    }

    func sort(_ windows: [WindowRecord], enabled: Bool) -> [WindowRecord] {
        guard enabled else { return windows }
        return windows.enumerated().sorted {
            let leftFavorite = isFavorite($0.element)
            let rightFavorite = isFavorite($1.element)
            if leftFavorite != rightFavorite { return leftFavorite }
            return $0.offset < $1.offset
        }.map(\.element)
    }

    private func signature(for window: WindowRecord) -> String {
        "\(window.appName)|\(window.title)"
    }
}

@MainActor final class RecentFileStore: ObservableObject {
    @Published private(set) var items: [RecentFileItem] = []
    private var timer: Timer?
    var enabled = true { didSet { enabled ? start() : stop() } }

    func start() {
        guard enabled, timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        items = []
    }

    func refresh() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders = ["Downloads", "Desktop", "Documents"].map { home.appendingPathComponent($0) }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .isRegularFileKey, .isHiddenKey]
        let found = folders.flatMap { folder -> [RecentFileItem] in
            guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else { return [] }
            return children.compactMap { url in
                guard let values = try? url.resourceValues(forKeys: keys), values.isHidden != true else { return nil }
                guard values.isRegularFile == true || values.isDirectory == true else { return nil }
                return RecentFileItem(id: url.standardizedFileURL.path, url: url, name: url.lastPathComponent,
                                      modifiedAt: values.contentModificationDate ?? .distantPast,
                                      isDirectory: values.isDirectory == true)
            }
        }
        items = Array(found.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(5))
    }
}

@MainActor final class ClipboardShelfStore: ObservableObject {
    @Published private(set) var items: [ClipboardShelfItem] = []
    @Published var errorMessage: String?
    var favorites: [ClipboardShelfItem] { items.filter(\.isFavorite) }
    var maximumHistoryCount = 30
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let fileURL: URL
    private var storageReadable = true
    var enabled = true { didSet { enabled ? start() : stop() } }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB/clipboard-favorites.json")
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                items = try JSONDecoder().decode([ClipboardShelfItem].self, from: Data(contentsOf: self.fileURL))
                    .filter(\.isFavorite)
            } catch {
                storageReadable = false
                errorMessage = "Pano favorileri okunamadı. Mevcut kayıtlar korunuyor."
            }
        }
    }

    func start() {
        guard enabled, timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 0.3
    }

    func stop() {
        timer?.invalidate(); timer = nil
        items.removeAll { !$0.isFavorite }
    }

    func refresh() {
        guard enabled else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        // Password managers mark confidential/transient data; never retain those entries.
        let privateTypes = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                            "org.nspasteboard.AutoGeneratedType"]
        guard !privateTypes.contains(where: { pasteboard.availableType(from: [NSPasteboard.PasteboardType($0)]) != nil }),
              let item = makeItem(from: pasteboard) else { return }
        guard !items.contains(where: { equivalent($0, item) }) else { return }
        items.insert(item, at: 0)
        trimHistory()
    }

    func copy(_ item: ClipboardShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .image:
            if let data = item.imageData { pasteboard.setData(data, forType: .png) }
        case .files:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) }
            if !urls.isEmpty { pasteboard.writeObjects(urls as [NSURL]) }
        case .link:
            if let raw = item.urlString, let url = URL(string: raw) { pasteboard.writeObjects([url as NSURL]) }
            else { pasteboard.setString(item.text, forType: .string) }
        case .color:
            if let raw = item.colorHex, let color = color(fromHex: raw) { pasteboard.writeObjects([color]) }
            else { pasteboard.setString(item.text, forType: .string) }
        case .text:
            pasteboard.setString(item.text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
    }

    func search(_ query: String, favoritesOnly: Bool = false) -> [ClipboardShelfItem] {
        let source = favoritesOnly ? favorites : items
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return source }
        return source.filter {
            $0.text.localizedCaseInsensitiveContains(term)
                || ($0.sourceBundleIdentifier?.localizedCaseInsensitiveContains(term) ?? false)
                || ($0.filePaths?.contains(where: { $0.localizedCaseInsensitiveContains(term) }) ?? false)
        }
    }

    func toggleFavorite(_ item: ClipboardShelfItem) {
        guard storageReadable, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items
        if !updated[index].isFavorite && favorites.count >= 50 {
            errorMessage = "En fazla 50 pano favorisi saklayabilirsin."
            return
        }
        updated[index].isFavorite.toggle()
        let payloadSize = updated.lazy.filter(\.isFavorite).reduce(0) { $0 + ($1.imageData?.count ?? 0) + $1.text.utf8.count }
        guard payloadSize <= 8 * 1_024 * 1_024 else {
            errorMessage = "Pano favorileri toplamda en fazla 8 MB olabilir."
            return
        }
        guard saveFavorites(updated) else { return }
        items = updated
        trimHistory()
    }

    func remove(_ item: ClipboardShelfItem) {
        let updated = items.filter { $0.id != item.id }
        if item.isFavorite && !saveFavorites(updated) { return }
        items = updated
    }

    private func trimHistory() {
        var historyCount = 0
        items = items.filter {
            if $0.isFavorite { return true }
            historyCount += 1
            return historyCount <= maximumHistoryCount
        }
    }

    private func makeItem(from pasteboard: NSPasteboard) -> ClipboardShelfItem? {
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let privateApps = ["1password", "bitwarden", "lastpass", "keepass", "dashlane"]
        if let source, privateApps.contains(where: { source.localizedCaseInsensitiveContains($0) }) { return nil }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let paths = urls.prefix(20).map(\.standardizedFileURL.path)
            return ClipboardShelfItem(id: UUID(), text: paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "),
                                      copiedAt: Date(), kind: .files, filePaths: paths, sourceBundleIdentifier: source)
        }
        if pasteboard.availableType(from: [.color]) != nil,
           let color = NSColor(from: pasteboard)?.usingColorSpace(.deviceRGB), let hex = hexString(for: color) {
            return ClipboardShelfItem(id: UUID(), text: hex, copiedAt: Date(), kind: .color,
                                      colorHex: hex, sourceBundleIdentifier: source)
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff), data.count <= 2 * 1_024 * 1_024,
           let image = NSImage(data: data),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return ClipboardShelfItem(id: UUID(), text: "Görsel \(Int(image.size.width))×\(Int(image.size.height))",
                                      copiedAt: Date(), kind: .image, imageData: png, sourceBundleIdentifier: source)
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: false]) as? [URL],
           let url = urls.first, !url.isFileURL {
            return ClipboardShelfItem(id: UUID(), text: url.absoluteString, copiedAt: Date(), kind: .link,
                                      urlString: url.absoluteString, sourceBundleIdentifier: source)
        }
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.utf8.count <= 65_536, !looksSensitive(text) else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
            return ClipboardShelfItem(id: UUID(), text: text, copiedAt: Date(), kind: .link,
                                      urlString: text, sourceBundleIdentifier: source)
        }
        if let hex = normalizedHexColor(text) {
            return ClipboardShelfItem(id: UUID(), text: hex, copiedAt: Date(), kind: .color,
                                      colorHex: hex, sourceBundleIdentifier: source)
        }
        return ClipboardShelfItem(id: UUID(), text: text, copiedAt: Date(), kind: .text, sourceBundleIdentifier: source)
    }

    private func equivalent(_ lhs: ClipboardShelfItem, _ rhs: ClipboardShelfItem) -> Bool {
        lhs.kind == rhs.kind && lhs.text == rhs.text && lhs.filePaths == rhs.filePaths && lhs.imageData == rhs.imageData
    }

    private func normalizedHexColor(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = #"^#(?:[0-9A-F]{3}|[0-9A-F]{6}|[0-9A-F]{8})$"#
        return value.range(of: pattern, options: .regularExpression) == nil ? nil : value
    }

    private func hexString(for color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
        let red = Int((rgb.redComponent * 255).rounded()), green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded()), alpha = Int((rgb.alphaComponent * 255).rounded())
        return alpha == 255
            ? String(format: "#%02X%02X%02X", red, green, blue)
            : String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    private func color(fromHex raw: String) -> NSColor? {
        var hex = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let hasAlpha = hex.count == 8
        return NSColor(red: CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255,
                       green: CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255,
                       blue: CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255,
                       alpha: hasAlpha ? CGFloat(value & 0xFF) / 255 : 1)
    }

    private func looksSensitive(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("-----begin private key-----") || lower.contains("-----begin rsa private key-----") { return true }
        let patterns = [
            #"(?i)\b(password|passwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token)\s*[:=]\s*\S+"#,
            #"\b(?:sk|pk)_(?:live|test)_[A-Za-z0-9]{16,}\b"#,
            #"\bgh[opusr]_[A-Za-z0-9_]{20,}\b"#,
            #"\bAKIA[0-9A-Z]{16}\b"#,
            #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#,
            #"(?i)\b(otp|verification|doğrulama|code|kod)\D{0,12}\d{4,8}\b"#
        ]
        if patterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil }) { return true }
        let digits = text.filter(\.isNumber)
        return (13...19).contains(digits.count) && luhnValid(digits)
    }

    private func luhnValid(_ digits: String) -> Bool {
        var sum = 0
        for (offset, character) in digits.reversed().enumerated() {
            guard var value = character.wholeNumberValue else { return false }
            if offset % 2 == 1 { value *= 2; if value > 9 { value -= 9 } }
            sum += value
        }
        return sum > 0 && sum % 10 == 0
    }

    private func saveFavorites(_ updated: [ClipboardShelfItem]) -> Bool {
        guard storageReadable else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated.filter(\.isFavorite)).write(to: fileURL, options: .atomic)
            // Favorites are local text; restrict the persistent file to the current user.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Pano favorileri kaydedilemedi: \(error.localizedDescription)"
            return false
        }
    }
}

@MainActor final class FileActivityStore: ObservableObject {
    @Published private(set) var activeCount = 0
    @Published private(set) var lastUpdate: Date?
    private var timer: Timer?
    var enabled = true { didSet { enabled ? start() : stop() } }

    func start() {
        guard enabled, timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        activeCount = 0; lastUpdate = nil
    }

    func refresh() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard let children = try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            activeCount = 0; return
        }
        let cutoff = Date().addingTimeInterval(-10 * 60)
        let recent = children.filter { url in
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { $0 > cutoff } ?? false
        }
        activeCount = recent.count
        lastUpdate = recent.isEmpty ? nil : Date()
    }
}
