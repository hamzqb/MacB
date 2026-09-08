import AppKit
import Combine
import MacBCore

struct ShelfItem: Identifiable {
    let id: UUID
    let url: URL?
    let name: String
    let isAvailable: Bool
    let isDirectory: Bool
}

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var errorMessage: String?
    private var persistence: ShelfPersistence?

    init(fileURL: URL? = nil) {
        let location = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB/shelf.json")
        do {
            persistence = try ShelfPersistence(fileURL: location)
            refreshAvailability()
        } catch {
            errorMessage = "Dosya rafı okunamadı. Mevcut kayıtlar korunuyor: \(error.localizedDescription)"
        }
    }

    func add(urls: [URL]) {
        guard let persistence else { return }
        do {
            try persistence.add(urls: urls)
            errorMessage = nil
            refreshAvailability()
        } catch { errorMessage = "Dosyalar rafa eklenemedi: \(error.localizedDescription)" }
    }

    func remove(id: UUID) {
        guard let persistence else { return }
        do {
            try persistence.remove(id: id)
            errorMessage = nil
            refreshAvailability()
        } catch { errorMessage = "Raf kaydı kaldırılamadı: \(error.localizedDescription)" }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Rafa ekle"
        panel.message = "Dosya veya klasörleri taşımadan rafa ekleyin."
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in self?.add(urls: panel.urls) }
        }
    }

    func copy(item: ShelfItem) {
        guard item.isAvailable, let url = item.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    func refreshAvailability() {
        guard let persistence else { return }
        do { try persistence.refreshBookmarks() }
        catch { errorMessage = "Dosya referansları güncellenemedi: \(error.localizedDescription)" }
        items = persistence.resolve().map {
            ShelfItem(id: $0.record.id, url: $0.url, name: $0.record.name,
                      isAvailable: $0.isAvailable, isDirectory: $0.record.isDirectory)
        }
    }
}
