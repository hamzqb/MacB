import AppKit
import Combine

struct RecentFileItem: Identifiable {
    let id: String
    let url: URL
    let name: String
    let modifiedAt: Date
    let isDirectory: Bool
}

struct ClipboardShelfItem: Identifiable {
    let id: UUID
    let text: String
    let copiedAt: Date
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
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    var enabled = true { didSet { enabled ? start() : stop() } }

    func start() {
        guard enabled, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        items = []
    }

    func refresh() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        let preview = text.count > 240 ? String(text.prefix(240)) + "…" : text
        guard items.first?.text != preview else { return }
        items.insert(ClipboardShelfItem(id: UUID(), text: preview, copiedAt: Date()), at: 0)
        if items.count > 5 { items.removeLast(items.count - 5) }
    }

    func copy(_ item: ClipboardShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
    }

    func remove(_ item: ClipboardShelfItem) {
        items.removeAll { $0.id == item.id }
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
