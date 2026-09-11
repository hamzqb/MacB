import Foundation

/// What a reclaimable folder is for, so the list reads as three decisions rather
/// than four hundred folder names.
public enum CacheSweepGroup: String, Sendable, CaseIterable {
    case applications, developer, logs

    public var title: String {
        switch self {
        case .applications: return "Uygulama önbellekleri"
        case .developer: return "Geliştirici önbellekleri"
        case .logs: return "Günlükler"
        }
    }

    public var summary: String {
        switch self {
        case .applications: return "Uygulamaların yeniden indirebildiği geçici veriler."
        case .developer: return "Derleme çıktıları ve paket depoları. Sonraki derleme yavaşlar, kaybolan bir şey olmaz."
        case .logs: return "Uygulamaların yazdığı kayıt dosyaları. Bir hatayı bildirmeyeceksen gerek yok."
        }
    }

    public var symbol: String {
        switch self {
        case .applications: return "app.badge"
        case .developer: return "hammer"
        case .logs: return "doc.text"
        }
    }

    /// Sweeping in the order the user thinks about it: the biggest and safest first.
    public var order: Int {
        switch self {
        case .applications: return 0
        case .developer: return 1
        case .logs: return 2
        }
    }
}

/// One directory the cache sweep looks at.
///
/// A source is either a folder whose children are each reclaimable on their own,
/// or a single folder that is reclaimed whole. Nothing recurses further: a cache
/// is a top-level entry in one of these directories, and going deeper would turn
/// a cleanup into a way to lose a project.
public struct CacheSource: Equatable, Sendable {
    public enum Style: String, Sendable {
        /// Every child is its own item; the directory itself is never touched.
        case children
        /// The directory itself is the item.
        case folder
    }

    public let group: CacheSweepGroup
    /// Path relative to the user's home directory.
    public let path: String
    public let title: String
    public let style: Style

    public init(group: CacheSweepGroup, path: String, title: String, style: Style) {
        self.group = group
        self.path = path
        self.title = title
        self.style = style
    }

    /// Everything worth reclaiming, and nothing that holds the only copy of anything.
    ///
    /// Documents, containers, group containers and preferences are all absent on
    /// purpose. They look like clutter and they are where applications keep the
    /// data the user would miss.
    public static let all: [CacheSource] = [
        CacheSource(group: .applications, path: "Library/Caches", title: "Önbellek", style: .children),
        CacheSource(group: .logs, path: "Library/Logs", title: "Günlük", style: .children),
        CacheSource(group: .developer, path: "Library/Developer/Xcode/DerivedData",
                    title: "Xcode türetilmiş veri", style: .children),
        CacheSource(group: .developer, path: "Library/Developer/Xcode/iOS DeviceSupport",
                    title: "Aygıt sembolleri", style: .children),
        CacheSource(group: .developer, path: "Library/Developer/CoreSimulator/Caches",
                    title: "Simülatör önbelleği", style: .children),
        CacheSource(group: .developer, path: ".npm/_cacache", title: "npm paket önbelleği", style: .folder),
        CacheSource(group: .developer, path: ".gradle/caches", title: "Gradle önbelleği", style: .folder),
        CacheSource(group: .developer, path: ".cargo/registry/cache", title: "Cargo paket önbelleği", style: .folder)
    ]
}

/// Decides what may be swept, on names alone.
///
/// Same reasoning as the uninstaller: the rule that chooses what leaves the disk
/// has to be provable without a disk, so every rule here is a scenario in the
/// test runner and none of them touch the filesystem.
public enum CacheSweepRules {
    /// Caches that hold the only copy of something not yet written down elsewhere.
    ///
    /// The rest of ~/Library/Caches is, by Apple's own definition, data the owner
    /// can rebuild. These four cannot: they are a queue, not a copy.
    public static let protectedNames: Set<String> = [
        // Records edited offline and not yet pushed to iCloud.
        "CloudKit",
        // The sandbox bookkeeping that maps applications to their containers.
        "com.apple.containermanagerd",
        // Downloads still in flight, resumable only while this is intact.
        "com.apple.nsurlsessiond",
        // The receipt and update state of everything installed from the App Store.
        "com.apple.appstore"
    ]

    /// Caches that belong to build tools rather than to applications.
    ///
    /// They live in the same directory as everything else, and grouping them by
    /// what they are is the difference between a list and a wall of identifiers.
    private static let developerNames: Set<String> = [
        "homebrew", "orgswiftswiftpm", "gobuild", "pip", "cocoapods", "nodegyp",
        "typescript", "deno", "msplaywright", "puppeteer", "electron", "yarn",
        "pnpm", "uv", "bazel", "jetbrains", "comappledtxcode", "golang",
        "comappledtxcodeserver", "virtualenv", "ruby", "gem"
    ]

    public static func normalize(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    /// Whether an entry inside a swept directory may be offered at all.
    ///
    /// Hidden entries are skipped because a dot-file in a cache directory is
    /// somebody's marker, not their cache.
    public static func isSweepable(name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix(".") else { return false }
        guard !name.contains("/") else { return false }
        return !protectedNames.contains(name)
    }

    /// Which group an entry in ~/Library/Caches reads as.
    public static func group(forCacheName name: String, default fallback: CacheSweepGroup) -> CacheSweepGroup {
        developerNames.contains(normalize(name)) ? .developer : fallback
    }

    /// Whether a path is one the sweep is allowed to move.
    ///
    /// The check is on the standardised path, and it is deliberately the same
    /// shape as the uninstaller's: inside the home directory, inside a listed
    /// source, and no deeper than that source's style allows.
    public static func isSweepablePath(_ path: String, home: String,
                                       sources: [CacheSource] = CacheSource.all) -> Bool {
        guard !home.isEmpty, path.hasPrefix(home + "/"), !path.contains("/..") else { return false }
        let relative = String(path.dropFirst(home.count + 1))
        for source in sources {
            switch source.style {
            case .folder:
                if relative == source.path { return true }
            case .children:
                let base = source.path + "/"
                guard relative.hasPrefix(base) else { continue }
                let remainder = relative.dropFirst(base.count)
                // Exactly one component: the child itself, never anything inside it.
                if !remainder.isEmpty, !remainder.contains("/") { return true }
            }
        }
        return false
    }
}
