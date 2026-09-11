import Foundation

/// Everything MacB knows about the application being removed.
///
/// The bundle identifier alone finds about half of what an application leaves
/// behind. Login-item helpers file under their own identifiers, group
/// containers are prefixed with the team identifier, and crash reports are
/// named after the executable, so all four are carried together.
public struct AppIdentity: Equatable, Sendable {
    public let bundleIdentifier: String
    /// The display name, used only for the weakest kind of match.
    public let name: String
    public let executableName: String?
    public let teamIdentifier: String?
    /// Identifiers of helpers and login items found inside the bundle.
    public let helperIdentifiers: [String]

    public init(bundleIdentifier: String, name: String, executableName: String? = nil,
                teamIdentifier: String? = nil, helperIdentifiers: [String] = []) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.executableName = executableName
        self.teamIdentifier = teamIdentifier
        self.helperIdentifiers = helperIdentifiers
    }

    /// Every identifier worth matching, longest first so a helper identifier
    /// that extends the main one is reported against the more specific of the two.
    public var identifiers: [String] {
        ([bundleIdentifier] + helperIdentifiers)
            .filter { !$0.isEmpty }
            .reduced()
            .sorted { $0.count > $1.count }
    }
}

private extension Array where Element == String {
    func reduced() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

/// How sure MacB is that a file belongs to the application being removed.
///
/// This is the whole safety story of the uninstaller. Only `exact` and `likely`
/// are ticked when the review sheet opens; `possible` is a name match and stays
/// unticked, because a folder named after an application is sometimes shared
/// with the rest of a vendor's software.
public enum AppLeftoverConfidence: Int, Comparable, Sendable, CaseIterable {
    case possible = 0
    case likely = 1
    case exact = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .exact: return "Kesin"
        case .likely: return "Büyük ihtimalle"
        case .possible: return "Olabilir"
        }
    }

    public var detail: String {
        switch self {
        case .exact: return "Adı uygulamanın kimliğiyle birebir aynı."
        case .likely: return "Uygulamanın kimliğiyle başlıyor ya da yardımcısına ait."
        case .possible: return "Yalnızca uygulamanın adıyla eşleşti. Silmeden önce kendin bak."
        }
    }

    /// Whether the review sheet ticks this group by default.
    public var isSelectedByDefault: Bool { self >= .likely }
}

public enum AppLeftoverKind: String, Sendable, CaseIterable {
    case application, container, groupContainer, support, cache, httpStorage, webKit
    case preference, savedState, log, crashReport, launchAgent, launchDaemon
    case applicationScript, cookie

    public var title: String {
        switch self {
        case .application: return "Uygulama"
        case .container: return "Kapsayıcı"
        case .groupContainer: return "Grup kapsayıcısı"
        case .support: return "Destek dosyaları"
        case .cache: return "Önbellek"
        case .httpStorage: return "Ağ deposu"
        case .webKit: return "WebKit verisi"
        case .preference: return "Ayarlar"
        case .savedState: return "Kaydedilmiş durum"
        case .log: return "Günlükler"
        case .crashReport: return "Çökme raporu"
        case .launchAgent: return "Açılış görevi"
        case .launchDaemon: return "Sistem görevi"
        case .applicationScript: return "Uygulama betikleri"
        case .cookie: return "Çerezler"
        }
    }
}

/// One directory the scanner looks in, and what the things inside it are.
public struct AppLeftoverLocation: Equatable, Sendable {
    public enum Root: String, Sendable {
        /// ~/Library — everything here can be moved to the user's own Trash.
        case userLibrary
        /// /Library — visible in the review, but removing it needs an administrator,
        /// which MacB deliberately does not ask for.
        case systemLibrary
    }

    public let root: Root
    public let path: String
    public let kind: AppLeftoverKind

    public init(root: Root, path: String, kind: AppLeftoverKind) {
        self.root = root
        self.path = path
        self.kind = kind
    }

    public var requiresAdministrator: Bool { root == .systemLibrary }

    /// The directories an application actually writes to, listed one level deep.
    ///
    /// Nothing here is recursive: a leftover is a top-level file or folder named
    /// after the application, and walking deeper would turn a name match into a
    /// way to delete someone else's data.
    public static let all: [AppLeftoverLocation] = [
        AppLeftoverLocation(root: .userLibrary, path: "Application Support", kind: .support),
        AppLeftoverLocation(root: .userLibrary, path: "Caches", kind: .cache),
        AppLeftoverLocation(root: .userLibrary, path: "Containers", kind: .container),
        AppLeftoverLocation(root: .userLibrary, path: "Group Containers", kind: .groupContainer),
        AppLeftoverLocation(root: .userLibrary, path: "Preferences", kind: .preference),
        AppLeftoverLocation(root: .userLibrary, path: "Preferences/ByHost", kind: .preference),
        AppLeftoverLocation(root: .userLibrary, path: "Saved Application State", kind: .savedState),
        AppLeftoverLocation(root: .userLibrary, path: "HTTPStorages", kind: .httpStorage),
        AppLeftoverLocation(root: .userLibrary, path: "WebKit", kind: .webKit),
        AppLeftoverLocation(root: .userLibrary, path: "Logs", kind: .log),
        AppLeftoverLocation(root: .userLibrary, path: "Logs/DiagnosticReports", kind: .crashReport),
        AppLeftoverLocation(root: .userLibrary, path: "LaunchAgents", kind: .launchAgent),
        AppLeftoverLocation(root: .userLibrary, path: "Application Scripts", kind: .applicationScript),
        AppLeftoverLocation(root: .userLibrary, path: "Cookies", kind: .cookie),
        AppLeftoverLocation(root: .systemLibrary, path: "Application Support", kind: .support),
        AppLeftoverLocation(root: .systemLibrary, path: "LaunchAgents", kind: .launchAgent),
        AppLeftoverLocation(root: .systemLibrary, path: "LaunchDaemons", kind: .launchDaemon),
        AppLeftoverLocation(root: .systemLibrary, path: "Logs", kind: .log)
    ]
}

/// Decides whether a file name belongs to an application, and how sure that is.
///
/// Pure string work on purpose. The rule that decides what gets deleted is the
/// one part of the uninstaller that must be provable without a filesystem, and
/// every rule below is a scenario in the test runner.
public enum AppLeftoverMatcher {
    /// Suffixes macOS adds to a preference or state file. Stripping them first
    /// turns "com.acme.app.plist" into an exact identifier match rather than a
    /// prefix one.
    private static let strippableSuffixes = [
        ".plist.lockfile", ".plist", ".savedState", ".binarycookies", ".sfl2", ".sfl3", ".lockfile"
    ]

    /// Vendor folders shared by everything that vendor ships.
    ///
    /// Uninstalling Chrome must not offer to delete "Application Support/Google",
    /// which also holds Drive and Earth. These names are barred from the weakest
    /// rule only; an exact identifier match inside them is still reported.
    private static let sharedVendorNames: Set<String> = [
        "google", "microsoft", "adobe", "apple", "mozilla", "java", "oracle",
        "jetbrains", "unity", "steam", "epicgames", "logitech", "nativeinstruments",
        "firebase", "crashlytics", "developer", "cloudkit", "caches", "containers"
    ]

    /// Names too generic to be evidence of anything.
    private static let genericNames: Set<String> = [
        "app", "mail", "music", "notes", "photos", "home", "calendar", "chat",
        "data", "logs", "user", "temp", "code", "test", "demo", "help", "tool",
        "file", "files", "word", "excel", "media", "video", "audio", "cache"
    ]

    public static func normalize(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    /// Strips the suffix macOS appended, leaving the identifier the file is named for.
    public static func stem(of fileName: String) -> String {
        for suffix in strippableSuffixes where fileName.hasSuffix(suffix) {
            return String(fileName.dropLast(suffix.count))
        }
        return fileName
    }

    /// Whether a directory is the vendor folder that this application files under.
    ///
    /// Chrome does not write to "Application Support/Chrome", it writes to
    /// "Application Support/Google/Chrome". The vendor folder itself is shared
    /// and must never be offered, but refusing to look inside it means finding
    /// almost nothing for exactly the applications that leave the most behind.
    /// One level deeper, and no further.
    public static func isVendorContainer(fileName: String, identity: AppIdentity) -> Bool {
        guard let vendor = vendorToken(of: identity) else { return false }
        return normalize(fileName) == vendor
    }

    /// The company component of a reverse-DNS identifier: com.google.Chrome is Google's.
    public static func vendorToken(of identity: AppIdentity) -> String? {
        let parts = identity.bundleIdentifier.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let vendor = normalize(String(parts[1]))
        // A vendor folder is only worth descending into when the name is long
        // enough to be a company rather than a word, and when it is not the
        // application's own name, which was already matched at the top level.
        guard vendor.count >= 4, vendor != normalize(identity.name) else { return nil }
        return vendor
    }

    public static func confidence(fileName: String, kind: AppLeftoverKind,
                                  identity: AppIdentity) -> AppLeftoverConfidence? {
        let stem = stem(of: fileName)
        guard !stem.isEmpty else { return nil }

        for identifier in identity.identifiers {
            if let result = identifierConfidence(stem: stem, identifier: identifier,
                                                 kind: kind, identity: identity) {
                return result
            }
        }

        // A crash report is named after the executable, not the bundle.
        if kind == .crashReport, let executable = identity.executableName, executable.count >= 3 {
            if stem == executable || stem.hasPrefix(executable + "_") || stem.hasPrefix(executable + "-") {
                return .likely
            }
        }

        return nameConfidence(stem: stem, kind: kind, identity: identity)
    }

    private static func identifierConfidence(stem: String, identifier: String,
                                             kind: AppLeftoverKind,
                                             identity: AppIdentity) -> AppLeftoverConfidence? {
        if stem == identifier { return .exact }
        if let team = identity.teamIdentifier, !team.isEmpty {
            if stem == "\(team).\(identifier)" { return .exact }
            if stem == "group.\(team).\(identifier)" { return .exact }
        }
        if stem == "group.\(identifier)" { return .exact }
        // ByHost preferences and helper bundles both extend the identifier with
        // another dotted component, which is the application's own namespace.
        if stem.hasPrefix(identifier + ".") || stem.hasPrefix(identifier + "-") { return .likely }
        if kind == .groupContainer, stem.hasSuffix("." + identifier) { return .likely }
        return nil
    }

    private static func nameConfidence(stem: String, kind: AppLeftoverKind,
                                       identity: AppIdentity) -> AppLeftoverConfidence? {
        // The weakest rule is barred from the places where a wrong guess is worst:
        // containers and group containers are always identifier-named, so a name
        // match there means something else is living under that name.
        guard kind != .container, kind != .groupContainer, kind != .application else { return nil }
        let name = normalize(identity.name)
        guard name.count >= 4, !sharedVendorNames.contains(name), !genericNames.contains(name) else { return nil }
        let candidate = normalize(stem)
        guard candidate == name else { return nil }
        return .possible
    }
}
