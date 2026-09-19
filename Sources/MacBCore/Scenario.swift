import Foundation

/// One step of a scenario: a single, ordinary thing MacB already does.
///
/// The list is closed and every case is reversible. Nothing here deletes,
/// sends, pays or types a password, and nothing reaches outside what the user
/// could do from the ring in two clicks — a scenario is a shortcut for the
/// user's own habits, not a new set of powers.
public enum ScenarioStep: Codable, Equatable, Sendable, Identifiable {
    /// Keep the Mac awake for a while. Zero means until it is turned off.
    case keepAwake(minutes: Int)
    /// Put the windows back the way a saved arrangement had them.
    case arrangement(name: String)
    /// Open or bring forward an application.
    case openApplication(name: String)
    /// Open an address in the default browser.
    case openWebsite(url: String)
    /// Pause or resume whatever is playing.
    case media(play: Bool)
    /// Set the output volume, 0 to 100.
    case volume(percent: Int)
    /// Start the island's timer.
    case timer(minutes: Int)
    /// Run one of the user's own Shortcuts, by name.
    ///
    /// The escape hatch: anything MacB does not do itself, the user can build
    /// in Shortcuts and name here. It only ever runs a shortcut the user wrote
    /// into this scenario — never one a model, a page or a message names.
    case shortcut(name: String)

    public var id: String { title }

    public var title: String {
        switch self {
        case .keepAwake(let minutes):
            return minutes <= 0 ? "Uyanık tut (süresiz)" : "Uyanık tut (\(minutes) dk)"
        case .arrangement(let name): return "Pencere düzeni: \(name)"
        case .openApplication(let name): return "Aç: \(name)"
        case .openWebsite(let url): return "Site: \(url)"
        case .media(let play): return play ? "Müziği başlat" : "Müziği duraklat"
        case .volume(let percent): return "Ses %\(percent)"
        case .timer(let minutes): return "Zamanlayıcı \(minutes) dk"
        case .shortcut(let name): return "Kısayol: \(name)"
        }
    }

    public var symbol: String {
        switch self {
        case .keepAwake: return "cup.and.heat.waves.fill"
        case .arrangement: return "rectangle.3.group"
        case .openApplication: return "app.badge"
        case .openWebsite: return "safari"
        case .media: return "play.circle"
        case .volume: return "speaker.wave.2"
        case .timer: return "timer"
        case .shortcut: return "square.stack.3d.up"
        }
    }

    /// The kinds of step that can be added, as empty examples for a menu.
    public static let choices: [ScenarioStep] = [
        .keepAwake(minutes: 60), .arrangement(name: ""), .openApplication(name: ""),
        .openWebsite(url: ""), .media(play: false), .volume(percent: 30),
        .timer(minutes: 25), .shortcut(name: "")
    ]

    /// What to call this kind of step in a menu, with nothing filled in.
    public var kindTitle: String {
        switch self {
        case .keepAwake: return "Uyanık tut"
        case .arrangement: return "Pencere düzeni"
        case .openApplication: return "Uygulama aç"
        case .openWebsite: return "Site aç"
        case .media: return "Müzik"
        case .volume: return "Ses seviyesi"
        case .timer: return "Zamanlayıcı"
        case .shortcut: return "Kısayol çalıştır"
        }
    }

    /// Whether the step has everything it needs to run.
    public var isComplete: Bool {
        switch self {
        case .arrangement(let name), .openApplication(let name), .shortcut(let name):
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .openWebsite(let url):
            return !url.trimmingCharacters(in: .whitespaces).isEmpty
        case .keepAwake, .media, .volume, .timer:
            return true
        }
    }
}

/// A named set of steps: "toplantı moduna geç", "odaklan", "işi bitir".
public struct Scenario: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var steps: [ScenarioStep]

    public init(id: UUID = UUID(), name: String, steps: [ScenarioStep] = []) {
        self.id = id
        self.name = name
        self.steps = steps
    }

    public var isRunnable: Bool { steps.contains(where: \.isComplete) }

    /// What MacB says after running it.
    public func summary(ran: Int) -> String {
        ran == 0 ? "\(name): yapılacak bir şey yoktu." : "\(name): \(ran) adım yapıldı."
    }
}

public enum ScenarioMatching {
    /// The scenario somebody means, by name.
    ///
    /// Exact first, then a case- and accent-insensitive match, then one whose
    /// name contains what was said — "toplantı" finds "Toplantı modu". Nothing
    /// looser than that: running the wrong scenario is worse than asking again.
    public static func find(_ spoken: String, in scenarios: [Scenario]) -> Scenario? {
        let wanted = normalise(spoken)
        guard !wanted.isEmpty else { return nil }
        if let exact = scenarios.first(where: { $0.name == spoken }) { return exact }
        if let same = scenarios.first(where: { normalise($0.name) == wanted }) { return same }
        let contained = scenarios.filter { normalise($0.name).contains(wanted) }
        return contained.count == 1 ? contained[0] : nil
    }

    /// A name reduced to something two spellings of it can both reach.
    ///
    /// Folding handles ş, ğ, ü, ö and ç, but not Turkish's dotted and dotless
    /// i: "ı" carries no diacritic to remove, so "toplanti" would never find
    /// "toplantı" — which is exactly how somebody types it in a hurry, and how
    /// speech recognition often writes it. Those two are mapped by hand.
    public static func normalise(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{0131}", with: "i")
            .replacingOccurrences(of: "\u{0130}", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
    }

    /// At most this many scenarios. A list longer than this is a list nobody
    /// remembers the names in, and every name is sent to the model.
    public static let maximum = 20
}
