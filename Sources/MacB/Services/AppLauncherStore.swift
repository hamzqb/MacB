import AppKit
import Combine
import MacBCore

struct LauncherItem: Identifiable, Equatable, @unchecked Sendable {
    /// The stored record, so removing an entry addresses the right one even when
    /// two shortcuts resolve to the same path.
    let recordID: UUID
    let url: URL
    let name: String
    let isDirectory: Bool
    var isAvailable: Bool

    var id: UUID { recordID }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// The apps and folders the user pinned for quick access.
///
/// This is deliberately not an application library: MacB does not scan what is
/// installed, does not sort anyone into categories, and keeps no folders of its
/// own. The section shows what the user chose, in the order they chose it, and
/// nothing else. Only references are stored; the bundles are never touched.
@MainActor final class AppLauncherStore: ObservableObject {
    @Published private(set) var items: [LauncherItem] = []
    @Published var errorMessage: String?

    private var persistence: ShelfPersistence?

    init(fileURL: URL? = nil) {
        let location = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB/launcher.json")
        do {
            persistence = try ShelfPersistence(fileURL: location)
            refresh()
        } catch {
            errorMessage = "Hızlı erişim listesi okunamadı: \(error.localizedDescription)"
        }
    }

    var isEmpty: Bool { items.isEmpty }

    /// Opens the picker. Applications and folders only, so a stray document
    /// cannot end up in a row meant for launching things.
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Ekle"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        add(urls: panel.urls)
    }

    func add(urls: [URL]) {
        guard let persistence else { return }
        let allowed = urls.filter {
            $0.pathExtension.lowercased() == "app"
                || (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard !allowed.isEmpty else {
            errorMessage = "Yalnızca uygulama ve klasör eklenebilir."
            return
        }
        do {
            try persistence.add(urls: allowed)
            errorMessage = nil
            refresh()
        } catch {
            errorMessage = "Eklenemedi: \(error.localizedDescription)"
        }
    }

    func open(_ item: LauncherItem) {
        guard item.isAvailable else {
            errorMessage = "\(item.name) bulunamadı."
            return
        }
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: LauncherItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Drops the shortcut. The application itself stays where it is.
    func remove(_ item: LauncherItem) {
        guard let persistence else { return }
        do {
            try persistence.remove(id: item.recordID)
            errorMessage = nil
            refresh()
        } catch {
            errorMessage = "Kaldırılamadı: \(error.localizedDescription)"
        }
    }

    func refresh() {
        guard let persistence else { return }
        items = persistence.resolve().map { resolved in
            LauncherItem(recordID: resolved.record.id,
                         url: resolved.url ?? URL(fileURLWithPath: resolved.record.path),
                         name: Self.cleanName(resolved.record.name),
                         isDirectory: resolved.record.isDirectory,
                         isAvailable: resolved.isAvailable)
        }
    }

    private static func cleanName(_ value: String) -> String {
        value.hasSuffix(".app") ? String(value.dropLast(4)) : value
    }
}
