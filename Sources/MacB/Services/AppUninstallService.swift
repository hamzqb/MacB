import AppKit

struct AppRemovalCandidate: Identifiable, Hashable, Sendable {
    enum Kind: String { case application, support, cache, preference, container, savedState }
    let url: URL
    let kind: Kind
    var id: String { url.standardizedFileURL.path }
    var size: Int64
}

enum AppUninstallError: LocalizedError {
    case invalidApplication, protectedApplication, unsafeCandidate
    var errorDescription: String? {
        switch self {
        case .invalidApplication: return "Geçerli bir uygulama seç."
        case .protectedApplication: return "macOS sistem uygulamaları kaldırılamaz."
        case .unsafeCandidate: return "Güvenlik denetimi bu öğenin taşınmasını engelledi."
        }
    }
}

/// Finds exact, user-visible leftovers and moves only reviewed candidates to Trash.
final class AppUninstallService {
    func candidates(for applicationURL: URL) throws -> [AppRemovalCandidate] {
        let app = applicationURL.standardizedFileURL
        guard app.isFileURL, app.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: app), let identifier = bundle.bundleIdentifier else {
            throw AppUninstallError.invalidApplication
        }
        guard Self.validBundleIdentifier(identifier) else { throw AppUninstallError.invalidApplication }
        guard app.resolvingSymlinksInPath().path == app.path else {
            throw AppUninstallError.unsafeCandidate
        }
        guard !app.path.hasPrefix("/System/"), !identifier.hasPrefix("com.apple.") else {
            throw AppUninstallError.protectedApplication
        }
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        let exact: [(URL, AppRemovalCandidate.Kind)] = [
            (app, .application),
            (library.appendingPathComponent("Application Support/\(identifier)"), .support),
            (library.appendingPathComponent("Caches/\(identifier)"), .cache),
            (library.appendingPathComponent("Preferences/\(identifier).plist"), .preference),
            (library.appendingPathComponent("Containers/\(identifier)"), .container),
            (library.appendingPathComponent("Saved Application State/\(identifier).savedState"), .savedState)
        ]
        var seen = Set<String>()
        return exact.compactMap { url, kind in
            let lexical = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: lexical.path),
                  lexical.resolvingSymlinksInPath().path == lexical.path,
                  seen.insert(lexical.path).inserted else { return nil }
            let candidate = AppRemovalCandidate(url: lexical, kind: kind, size: allocatedSize(of: lexical))
            return isSafeCandidate(candidate) ? candidate : nil
        }
    }

    func moveToTrash(_ candidates: [AppRemovalCandidate]) async throws {
        for candidate in candidates {
            // Revalidate immediately before every recycle operation so a path swapped
            // after the review screen cannot redirect deletion through a symlink.
            guard isSafeCandidate(candidate) else { throw AppUninstallError.unsafeCandidate }
            _ = try await NSWorkspace.shared.recycle([candidate.url])
        }
    }

    private func isSafeCandidate(_ candidate: AppRemovalCandidate) -> Bool {
        let lexical = candidate.url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: lexical.path),
              lexical.resolvingSymlinksInPath().path == lexical.path else { return false }
        let path = lexical.path
        guard !path.hasPrefix("/System/"), !path.hasPrefix("/usr/"), !path.hasPrefix("/bin/"), !path.hasPrefix("/sbin/") else { return false }
        if candidate.kind == .application {
            let home = FileManager.default.homeDirectoryForCurrentUser.path + "/"
            return path.hasPrefix("/Applications/") || path.hasPrefix(home)
        }
        return path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/Library/")
    }

    private static func validBundleIdentifier(_ identifier: String) -> Bool {
        guard identifier.count <= 255, !identifier.contains("/"), !identifier.contains("..") else { return false }
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return parts.allSatisfy { $0.unicodeScalars.allSatisfy(allowed.contains) }
    }

    private func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            let value = try? url.resourceValues(forKeys: keys)
            return Int64(value?.totalFileAllocatedSize ?? value?.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            if let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
