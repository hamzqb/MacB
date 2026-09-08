import AppKit

struct RecentTargetItem: Codable, Identifiable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let appName: String
    let usedAt: Date
}

@MainActor final class RecentTargetStore: ObservableObject {
    @Published private(set) var items: [RecentTargetItem] = []
    private let defaults: UserDefaults
    private let key = "recentDropTargets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode([RecentTargetItem].self, from: data) {
            items = saved.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil }
        }
    }

    func record(window: WindowRecord) {
        guard let bundleIdentifier = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier else { return }
        items.removeAll { $0.bundleIdentifier == bundleIdentifier }
        items.insert(RecentTargetItem(bundleIdentifier: bundleIdentifier, appName: window.appName, usedAt: Date()), at: 0)
        if items.count > 4 { items.removeLast(items.count - 4) }
        persist()
    }

    func open(_ target: RecentTargetItem) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) else {
            items.removeAll { $0.id == target.id }; persist(); return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }
}
