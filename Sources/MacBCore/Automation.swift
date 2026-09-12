import Foundation

/// Something MacB already noticed, offered to the rules as it happens.
///
/// Every case here is a thing the app watches anyway for its own sake. Nothing
/// is polled, opened or asked for in order to make automation possible.
public enum AutomationEvent: Equatable, Sendable {
    case lidOpened
    case lidClosing
    case chargerConnected
    case chargerDisconnected
    /// The current charge, offered on every reading. Rules decide what is low.
    case batteryLevel(Int)
    case mediaStarted
    case mediaStopped
    case timerFinished
    case appLaunched(String)
    case appQuit(String)
}

/// What a rule is waiting for.
public enum AutomationTrigger: Codable, Equatable, Hashable, Sendable {
    case lidOpened
    case lidClosing
    case chargerConnected
    case chargerDisconnected
    case batteryBelow(percent: Int)
    case mediaStarted
    case mediaStopped
    case timerFinished
    case appLaunched(bundleIdentifier: String)
    case appQuit(bundleIdentifier: String)

    /// The lowest and highest battery threshold a rule may wait for.
    ///
    /// Above ninety a rule would fire almost permanently, and below five the
    /// Mac is about to sleep and will not get to run anything.
    public static let batteryRange = 5...90
}

/// What a rule does about it.
///
/// Deliberately small, and deliberately without a shell. Everything here either
/// opens something the user chose or speaks to a part of MacB that is already
/// theirs; nothing deletes, moves or overwrites anything.
public enum AutomationAction: Codable, Equatable, Sendable {
    /// Opens an installed application. The name is carried for the settings
    /// list, so a rule still reads sensibly once the app is uninstalled.
    case openApplication(bundleIdentifier: String, name: String)
    case openLink(String)
    case showNotice(String)
    case startTimer(minutes: Int)
    case pauseMedia
    /// Runs one of the user's own Shortcuts, by name.
    case runShortcut(name: String)

    public static let timerRange = 1...180
    public static let noticeLimit = 48

    /// Whether the action is something MacB is willing to carry out.
    ///
    /// A link is checked here rather than at the moment of opening, so a rule
    /// that could never be safe cannot be saved in the first place. Only the
    /// web and files on this Mac: a custom scheme would hand an arbitrary
    /// application arbitrary arguments on an event the user is not watching.
    public var isSafe: Bool {
        switch self {
        case .openApplication(let identifier, _):
            return !identifier.trimmingCharacters(in: .whitespaces).isEmpty
        case .openLink(let link):
            guard let url = URL(string: link.trimmingCharacters(in: .whitespaces)),
                  let scheme = url.scheme?.lowercased() else { return false }
            guard ["http", "https", "file"].contains(scheme) else { return false }
            return url.host != nil || scheme == "file"
        case .showNotice(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .startTimer(let minutes):
            return AutomationAction.timerRange.contains(minutes)
        case .pauseMedia:
            return true
        case .runShortcut(let name):
            // A name is passed straight to the Shortcuts runner as one argument.
            // Newlines and control characters have no business in one and are
            // the shape of an attempt to smuggle a second command in.
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.rangeOfCharacter(from: .newlines) == nil
                && !trimmed.unicodeScalars.contains { $0.properties.generalCategory == .control }
        }
    }
}

public struct AutomationRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var isEnabled: Bool
    public var trigger: AutomationTrigger
    public var action: AutomationAction

    public init(id: UUID = UUID(), title: String, isEnabled: Bool = true,
                trigger: AutomationTrigger, action: AutomationAction) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.action = action
    }

    public var isRunnable: Bool { isEnabled && action.isSafe }
}

/// Decides which rules an event sets off.
///
/// Pure: it is handed events and hands back actions, and every decision about
/// repeating, thresholds and cooling off is arithmetic that can be proven in a
/// test rather than watched for on a real Mac.
public struct AutomationEngine: Equatable, Sendable {
    /// How long a rule sits quiet after firing.
    ///
    /// Media flips between playing and paused constantly while somebody is
    /// skipping tracks, and a rule that opens a window every time would make
    /// the Mac unusable.
    public static let cooldown: TimeInterval = 60

    public var rules: [AutomationRule]
    private var lastFired: [UUID: Date] = [:]
    /// Battery rules that have been above their threshold since last firing.
    /// Without this a rule at twenty per cent fires on every reading all the
    /// way down to empty.
    private var armed: Set<UUID> = []

    public init(rules: [AutomationRule] = []) {
        self.rules = rules
    }

    public mutating func setRules(_ rules: [AutomationRule]) {
        self.rules = rules
        let live = Set(rules.map(\.id))
        lastFired = lastFired.filter { live.contains($0.key) }
        armed = armed.intersection(live)
    }

    public mutating func actions(for event: AutomationEvent, now: Date = Date()) -> [AutomationAction] {
        var result: [AutomationAction] = []
        for rule in rules where rule.isRunnable {
            guard matches(rule: rule, event: event) else { continue }
            if let last = lastFired[rule.id], now.timeIntervalSince(last) < Self.cooldown { continue }
            lastFired[rule.id] = now
            result.append(rule.action)
        }
        return result
    }

    private mutating func matches(rule: AutomationRule, event: AutomationEvent) -> Bool {
        switch (rule.trigger, event) {
        case (.lidOpened, .lidOpened),
             (.lidClosing, .lidClosing),
             (.chargerConnected, .chargerConnected),
             (.chargerDisconnected, .chargerDisconnected),
             (.mediaStarted, .mediaStarted),
             (.mediaStopped, .mediaStopped),
             (.timerFinished, .timerFinished):
            return true
        case (.batteryBelow(let threshold), .batteryLevel(let level)):
            // Fires on the way down, once, and only becomes possible again
            // after the battery has been back above the line.
            guard level < threshold else { armed.insert(rule.id); return false }
            guard armed.contains(rule.id) else { return false }
            armed.remove(rule.id)
            return true
        case (.appLaunched(let wanted), .appLaunched(let actual)),
             (.appQuit(let wanted), .appQuit(let actual)):
            return wanted.caseInsensitiveCompare(actual) == .orderedSame
        default:
            return false
        }
    }

    public static func == (lhs: AutomationEngine, rhs: AutomationEngine) -> Bool {
        lhs.rules == rhs.rules
    }
}
