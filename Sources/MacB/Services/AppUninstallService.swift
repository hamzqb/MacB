import AppKit
import MacBCore
import Security

struct AppRemovalCandidate: Identifiable, Hashable, Sendable {
    let url: URL
    let kind: AppLeftoverKind
    let confidence: AppLeftoverConfidence
    let requiresAdministrator: Bool
    var id: String { url.standardizedFileURL.path }
    var size: Int64
    /// True when the folder was larger than the walk budget and the number is a
    /// floor rather than a total. A browser cache holds a hundred thousand files,
    /// and adding them all up is slower than the user is willing to wait.
    var sizeIsPartial: Bool = false

    var sizeText: String {
        let text = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return sizeIsPartial ? "≥ " + text : text
    }

    /// Where the item lives, written the way the user reads it, so the review
    /// list does not repeat the home directory on every line.
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// What the scan found, plus the parts of it that are not files.
struct AppRemovalReport: Sendable {
    let identity: AppIdentity
    let candidates: [AppRemovalCandidate]
    /// Set when the application is running: it has to stop before its own bundle
    /// can be recycled, and MacB asks rather than killing it.
    let runningProcessCount: Int
}

enum AppUninstallError: LocalizedError {
    case invalidApplication, protectedApplication, unsafeCandidate, stillRunning, requiresAdministrator
    var errorDescription: String? {
        switch self {
        case .invalidApplication: return "Geçerli bir uygulama seç."
        case .protectedApplication: return "macOS sistem uygulamaları ve MacB'nin kendisi kaldırılamaz."
        case .unsafeCandidate: return "Güvenlik denetimi bu öğenin taşınmasını engelledi."
        case .stillRunning: return "Uygulama hâlâ açık. Önce kapat, sonra tekrar dene."
        case .requiresAdministrator: return "Bu öğe /Library altında. MacB yönetici izni istemez, onu kendin taşımalısın."
        }
    }
}

/// Finds what an application leaves behind and moves only reviewed items to Trash.
///
/// Two rules shape the whole design. Nothing is ever deleted, only recycled, so
/// every decision is reversible from the Trash. And the search is one level deep
/// in a fixed list of directories, so a name match can never walk into data that
/// belongs to something else.
final class AppUninstallService {
    func report(for applicationURL: URL) throws -> AppRemovalReport {
        let app = applicationURL.standardizedFileURL
        guard app.isFileURL, app.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: app), let identifier = bundle.bundleIdentifier else {
            throw AppUninstallError.invalidApplication
        }
        guard Self.validBundleIdentifier(identifier) else { throw AppUninstallError.invalidApplication }
        guard app.resolvingSymlinksInPath().path == app.path else { throw AppUninstallError.unsafeCandidate }
        guard !app.path.hasPrefix("/System/"), !identifier.hasPrefix("com.apple.") else {
            throw AppUninstallError.protectedApplication
        }
        guard identifier != Bundle.main.bundleIdentifier else { throw AppUninstallError.protectedApplication }

        let identity = Self.identity(of: app, bundle: bundle, identifier: identifier)
        var candidates: [AppRemovalCandidate] = []
        var seen = Set<String>()

        if let candidate = makeCandidate(url: app, kind: .application, confidence: .exact,
                                         requiresAdministrator: false, seen: &seen) {
            candidates.append(candidate)
        }
        for location in AppLeftoverLocation.all {
            candidates.append(contentsOf: scan(location, identity: identity, seen: &seen))
        }

        candidates.sort {
            $0.confidence != $1.confidence ? $0.confidence > $1.confidence : $0.size > $1.size
        }
        return AppRemovalReport(identity: identity, candidates: candidates,
                                runningProcessCount: Self.runningProcesses(identity).count)
    }

    /// Moves reviewed items to Trash, checking each one again on the way.
    ///
    /// The recheck is not paranoia about the user: the review sheet can sit open
    /// for minutes, and a path that was a folder when it was listed must not be
    /// a symlink into someone else's data by the time it is recycled.
    func moveToTrash(_ candidates: [AppRemovalCandidate]) async throws {
        for candidate in candidates {
            guard !candidate.requiresAdministrator else { throw AppUninstallError.requiresAdministrator }
            guard isSafeCandidate(candidate) else { throw AppUninstallError.unsafeCandidate }
            _ = try await NSWorkspace.shared.recycle([candidate.url])
        }
    }

    /// Asks the application to quit, the way the Dock does, and waits briefly.
    /// Nothing is force-killed: an editor with unsaved work gets to object.
    @discardableResult
    func quitApplication(_ identity: AppIdentity) async -> Bool {
        let running = Self.runningProcesses(identity)
        guard !running.isEmpty else { return true }
        for application in running { application.terminate() }
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Self.runningProcesses(identity).isEmpty { return true }
        }
        return Self.runningProcesses(identity).isEmpty
    }

    func isRunning(_ identity: AppIdentity) -> Bool { !Self.runningProcesses(identity).isEmpty }

    // MARK: - Scanning

    private func scan(_ location: AppLeftoverLocation, identity: AppIdentity,
                      seen: inout Set<String>) -> [AppRemovalCandidate] {
        let directory = Self.directory(for: location)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        var found: [AppRemovalCandidate] = []
        for name in names {
            let url = directory.appendingPathComponent(name)
            guard let confidence = AppLeftoverMatcher.confidence(fileName: name, kind: location.kind,
                                                                 identity: identity) else {
                // The folder is not the application's, but it may be the vendor's,
                // and the application's own folder can be one level inside it.
                found.append(contentsOf: scanVendorContainer(url, name: name, location: location,
                                                             identity: identity, seen: &seen))
                continue
            }
            if let candidate = makeCandidate(url: url, kind: location.kind, confidence: confidence,
                                             requiresAdministrator: location.requiresAdministrator,
                                             seen: &seen) {
                found.append(candidate)
            }
        }
        return found
    }

    /// Looks one level inside a vendor folder, and never deeper.
    ///
    /// The vendor folder itself is never a candidate: deleting Application
    /// Support/Google because Chrome is going would take Drive and Earth with it.
    private func scanVendorContainer(_ url: URL, name: String, location: AppLeftoverLocation,
                                     identity: AppIdentity, seen: inout Set<String>) -> [AppRemovalCandidate] {
        guard AppLeftoverMatcher.isVendorContainer(fileName: name, identity: identity) else { return [] }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let children = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return [] }
        var found: [AppRemovalCandidate] = []
        for child in children {
            guard let confidence = AppLeftoverMatcher.confidence(fileName: child, kind: location.kind,
                                                                 identity: identity) else { continue }
            if let candidate = makeCandidate(url: url.appendingPathComponent(child), kind: location.kind,
                                             confidence: confidence,
                                             requiresAdministrator: location.requiresAdministrator,
                                             seen: &seen) {
                found.append(candidate)
            }
        }
        return found
    }

    private func makeCandidate(url: URL, kind: AppLeftoverKind, confidence: AppLeftoverConfidence,
                               requiresAdministrator: Bool, seen: inout Set<String>) -> AppRemovalCandidate? {
        let lexical = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: lexical.path),
              lexical.resolvingSymlinksInPath().path == lexical.path,
              seen.insert(lexical.path).inserted else { return nil }
        let measured = allocatedSize(of: lexical)
        let candidate = AppRemovalCandidate(url: lexical, kind: kind, confidence: confidence,
                                            requiresAdministrator: requiresAdministrator,
                                            size: measured.bytes, sizeIsPartial: measured.isPartial)
        guard requiresAdministrator || isSafeCandidate(candidate) else { return nil }
        return candidate
    }

    private static func directory(for location: AppLeftoverLocation) -> URL {
        let root: URL
        switch location.root {
        case .userLibrary:
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        case .systemLibrary:
            root = URL(fileURLWithPath: "/Library", isDirectory: true)
        }
        return root.appendingPathComponent(location.path, isDirectory: true)
    }

    // MARK: - Identity

    private static func identity(of app: URL, bundle: Bundle, identifier: String) -> AppIdentity {
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? app.deletingPathExtension().lastPathComponent
        let executable = bundle.executableURL?.lastPathComponent
        return AppIdentity(bundleIdentifier: identifier, name: name,
                           executableName: executable,
                           teamIdentifier: teamIdentifier(of: app),
                           helperIdentifiers: helperIdentifiers(in: app))
    }

    /// The team identifier from the app's own signature, which is what group
    /// containers are prefixed with. Unsigned apps simply have none.
    private static func teamIdentifier(of app: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Login items, XPC services and bundled helpers file their leftovers under
    /// their own identifiers, which no amount of matching on the main bundle
    /// identifier would ever find.
    private static func helperIdentifiers(in app: URL) -> [String] {
        let containers = [
            app.appendingPathComponent("Contents/Library/LoginItems"),
            app.appendingPathComponent("Contents/Library/LaunchServices"),
            app.appendingPathComponent("Contents/XPCServices"),
            app.appendingPathComponent("Contents/Helpers")
        ]
        var identifiers: [String] = []
        for container in containers {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: container,
                                                                            includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                guard let bundle = Bundle(url: entry), let identifier = bundle.bundleIdentifier,
                      validBundleIdentifier(identifier) else { continue }
                identifiers.append(identifier)
            }
        }
        return identifiers
    }

    private static func runningProcesses(_ identity: AppIdentity) -> [NSRunningApplication] {
        identity.identifiers.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    }

    // MARK: - Safety

    private func isSafeCandidate(_ candidate: AppRemovalCandidate) -> Bool {
        let lexical = candidate.url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: lexical.path),
              lexical.resolvingSymlinksInPath().path == lexical.path else { return false }
        let path = lexical.path
        guard !path.hasPrefix("/System/"), !path.hasPrefix("/usr/"),
              !path.hasPrefix("/bin/"), !path.hasPrefix("/sbin/"), !path.hasPrefix("/private/var/db/") else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if candidate.kind == .application {
            return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/")
        }
        // Everything that is not the bundle itself has to be a leftover inside the
        // user's own library. A candidate anywhere else is a bug, not a find.
        guard path.hasPrefix(home + "/Library/") else { return false }
        // And it has to be inside one of the directories the scan actually looks
        // at, never the directory itself.
        return AppLeftoverLocation.all.contains { location in
            guard location.root == .userLibrary else { return false }
            let base = home + "/Library/" + location.path + "/"
            guard path.hasPrefix(base) else { return false }
            // One component is a leftover, two is a leftover inside a vendor
            // folder, and anything deeper is somebody else's data.
            return path.dropFirst(base.count).filter { $0 == "/" }.count <= 1
        }
    }

    private static func validBundleIdentifier(_ identifier: String) -> Bool {
        guard identifier.count <= 255, !identifier.contains("/"), !identifier.contains("..") else { return false }
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return parts.allSatisfy { $0.unicodeScalars.allSatisfy(allowed.contains) }
    }

    /// How many files the size walk visits before it gives up and reports a floor.
    /// Roughly a tenth of a second on a cold cache, which keeps a scan of a whole
    /// browser profile inside a couple of seconds.
    private static let sizeWalkBudget = 20_000

    private func allocatedSize(of url: URL) -> (bytes: Int64, isPartial: Bool) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            let value = try? url.resourceValues(forKeys: keys)
            return (Int64(value?.totalFileAllocatedSize ?? value?.fileAllocatedSize ?? 0), false)
        }
        var total: Int64 = 0
        var visited = 0
        for case let item as URL in enumerator {
            visited += 1
            if visited > Self.sizeWalkBudget { return (total, true) }
            if let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return (total, false)
    }
}
