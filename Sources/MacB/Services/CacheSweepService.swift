import AppKit
import MacBCore

/// One folder the sweep can reclaim, with everything the review list shows.
struct CacheSweepItem: Identifiable, Hashable, Sendable {
    let url: URL
    let group: CacheSweepGroup
    /// What the folder is, in the user's words: "Önbellek", "Xcode türetilmiş veri".
    let kindTitle: String
    /// The application the folder belongs to, resolved from its bundle identifier
    /// when macOS knows one, and the raw folder name when it does not.
    let owner: String
    /// True while the owning application is running. Its cache is still reclaimable,
    /// but it will be rebuilt immediately, so it is shown and left unticked.
    let isInUse: Bool
    var size: Int64
    var sizeIsPartial: Bool

    var id: String { url.standardizedFileURL.path }

    var sizeText: String {
        let text = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return sizeIsPartial ? "≥ " + text : text
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

enum CacheSweepError: LocalizedError {
    case unsafeItem
    var errorDescription: String? {
        switch self {
        case .unsafeItem: return "Güvenlik denetimi bu klasörün taşınmasını engelledi."
        }
    }
}

/// Finds reclaimable caches and moves only reviewed ones to Trash.
///
/// Same two rules as the uninstaller. Nothing is deleted, only recycled, so a
/// mistake costs a drag back out of the Trash. And the search is one level deep
/// in a fixed list of directories, so nothing outside a cache folder is ever a
/// candidate however it is named.
final class CacheSweepService {
    /// Folders smaller than this are not worth a line in the list. A checkbox
    /// costs the user more attention than five megabytes is worth.
    private static let minimumInterestingSize: Int64 = 5_000_000

    func scan() -> [CacheSweepItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var items: [CacheSweepItem] = []
        var seen = Set<String>()
        for source in CacheSource.all {
            let directory = home.appendingPathComponent(source.path, isDirectory: true)
            switch source.style {
            case .folder:
                if let item = makeItem(url: directory, source: source, name: directory.lastPathComponent,
                                       seen: &seen) {
                    items.append(item)
                }
            case .children:
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { continue }
                for name in names where CacheSweepRules.isSweepable(name: name) {
                    if let item = makeItem(url: directory.appendingPathComponent(name), source: source,
                                           name: name, seen: &seen) {
                        items.append(item)
                    }
                }
            }
        }
        items.sort { $0.size > $1.size }
        return items
    }

    /// Moves reviewed folders to Trash, rechecking each one on the way.
    ///
    /// The review list can sit open while the disk changes underneath it, so the
    /// safety rule is applied again here rather than trusted from the scan.
    /// Returns where each folder ended up, so the sweep can be taken back.
    @discardableResult
    func moveToTrash(_ items: [CacheSweepItem]) async throws -> [TrashMove] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var moves: [TrashMove] = []
        for item in items {
            guard isSafe(item.url, home: home) else { throw CacheSweepError.unsafeItem }
            moves += try await NSWorkspace.shared.recycleRecording([item.url])
        }
        return moves
    }

    // MARK: - Building

    private func makeItem(url: URL, source: CacheSource, name: String,
                          seen: inout Set<String>) -> CacheSweepItem? {
        let lexical = url.standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard FileManager.default.fileExists(atPath: lexical.path),
              lexical.resolvingSymlinksInPath().path == lexical.path,
              isSafe(lexical, home: home),
              seen.insert(lexical.path).inserted else { return nil }
        // MacB rebuilding its own cache mid-sweep is a bug report waiting to happen.
        if let own = Bundle.main.bundleIdentifier, name == own { return nil }

        let measured = AllocatedSize.of(lexical)
        guard measured.isPartial || measured.bytes >= Self.minimumInterestingSize else { return nil }

        let running = runningApplication(forIdentifier: name)
        return CacheSweepItem(url: lexical,
                              group: source.group == .applications
                                  ? CacheSweepRules.group(forCacheName: name, default: .applications)
                                  : source.group,
                              kindTitle: source.title,
                              owner: displayName(for: name) ?? name,
                              isInUse: running != nil,
                              size: measured.bytes,
                              sizeIsPartial: measured.isPartial)
    }

    /// A cache folder is usually named after a bundle identifier, and macOS can
    /// turn that back into the name on the application's icon.
    private func displayName(for name: String) -> String? {
        guard name.contains("."), !name.hasSuffix(".app"),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) else { return nil }
        let readable = url.deletingPathExtension().lastPathComponent
        return readable.isEmpty ? nil : readable
    }

    private func runningApplication(forIdentifier name: String) -> NSRunningApplication? {
        guard name.contains(".") else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: name).first
    }

    private func isSafe(_ url: URL, home: String) -> Bool {
        let lexical = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: lexical.path),
              lexical.resolvingSymlinksInPath().path == lexical.path else { return false }
        return CacheSweepRules.isSweepablePath(lexical.path, home: home)
    }
}
