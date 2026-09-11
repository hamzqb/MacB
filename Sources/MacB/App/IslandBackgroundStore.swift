import AppKit
import Combine

/// The custom island background. Stores a security-scoped bookmark, never a copy of the picture.
@MainActor final class IslandBackgroundStore: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var name: String?
    @Published var errorMessage: String?

    private let defaults: UserDefaults
    private let key = "islandBackgroundBookmark"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    var hasImage: Bool { image != nil }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Seç"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store(url)
    }

    func clear() {
        defaults.removeObject(forKey: key)
        image = nil
        name = nil
        errorMessage = nil
    }

    private func store(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: [.nameKey],
                                                relativeTo: nil)
            defaults.set(bookmark, forKey: key)
            load()
        } catch {
            errorMessage = "Görsel kaydedilemedi: \(error.localizedDescription)"
        }
    }

    private func load() {
        guard let bookmark = defaults.data(forKey: key) else {
            image = nil
            name = nil
            return
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            errorMessage = "Arka plan görseline erişilemiyor."
            image = nil
            name = nil
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let loaded = NSImage(contentsOf: url) else {
            errorMessage = "Arka plan görseli okunamadı."
            image = nil
            name = nil
            return
        }
        image = loaded
        name = url.lastPathComponent
        errorMessage = nil
        if stale { store(url) }
    }
}
