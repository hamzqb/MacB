import AppKit
import Combine

struct RecentFileItem: Identifiable {
    let id: String
    let url: URL
    let name: String
    let modifiedAt: Date
    let isDirectory: Bool
}

struct ClipboardShelfItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let copiedAt: Date
    var isFavorite: Bool = false
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
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 1_048_576 else { return }
        guard !items.contains(where: { $0.text == text }) else { return }
        items.insert(ClipboardShelfItem(id: UUID(), text: text, copiedAt: Date()), at: 0)
        trimHistory()
    }

    func copy(_ item: ClipboardShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func toggleFavorite(_ item: ClipboardShelfItem) {
        guard storageReadable, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items
        if !updated[index].isFavorite && favorites.count >= 100 {
            errorMessage = "En fazla 100 pano favorisi saklayabilirsin."
            return
        }
        updated[index].isFavorite.toggle()
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
            return historyCount <= 5
        }
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
