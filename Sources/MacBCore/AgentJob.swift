import Foundation

/// Something MacB was asked to do while nobody was watching.
///
/// "Önemsiz maillere bak, bana listele, yirmi dakikaya geliyorum" is one of
/// these. It runs with nobody at the Mac, which is exactly why it is not
/// allowed to do very much: there is no one to ask.
///
/// The rule the whole thing rests on: **a job reads, and proposes.** It never
/// acts. Anything with an effect outside the conversation — opening,
/// archiving, writing, remembering, changing a setting — is prepared, written
/// down, and waits for the user to come back and say yes. So the worst a job
/// that has been fed a poisoned web page or a poisoned subject line can do is
/// put a suggestion on a card that the user then reads and refuses.
public struct AgentJob: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// What the user asked for, in their words.
    public var request: String
    public var createdAt: Date
    public var finishedAt: Date?
    public var state: AgentJobState
    /// What it found, in Turkish, for the user to read when they return.
    public var report: String
    /// What it would like to do about it, each waiting for a yes.
    public var proposals: [AgentProposal]
    /// How many turns it took. Kept so a job that spins can be seen doing it.
    public var rounds: Int
    /// Whether the user has seen the result.
    public var isDelivered: Bool

    public init(id: UUID = UUID(), request: String, createdAt: Date = Date(),
                finishedAt: Date? = nil, state: AgentJobState = .queued,
                report: String = "", proposals: [AgentProposal] = [],
                rounds: Int = 0, isDelivered: Bool = false) {
        self.id = id
        self.request = request
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.state = state
        self.report = report
        self.proposals = proposals
        self.rounds = rounds
        self.isDelivered = isDelivered
    }

    public var isFinished: Bool {
        switch state {
        case .done, .failed, .cancelled: return true
        case .queued, .running: return false
        }
    }

    /// Ready to be put in front of somebody who has just come back.
    public var isWaitingForUser: Bool { isFinished && !isDelivered }

    /// A short name for the card, made from the request rather than asked for
    /// separately: naming a job is work the user did not sign up for.
    public var title: String {
        let flat = request
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > 48 else { return flat }
        return String(flat.prefix(48)) + "…"
    }
}

public enum AgentJobState: Codable, Equatable, Sendable {
    case queued
    case running
    case done
    case failed(String)
    case cancelled

    public var title: String {
        switch self {
        case .queued: return "sırada"
        case .running: return "çalışıyor"
        case .done: return "bitti"
        case .failed: return "olmadı"
        case .cancelled: return "iptal"
        }
    }

    public var symbol: String {
        switch self {
        case .queued: return "clock"
        case .running: return "gearshape.2"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        }
    }
}

/// Something a job would do, if it were allowed to do anything.
///
/// Carried with the arguments the model produced, unaltered, so that what the
/// user approves is exactly what runs — not a re-derivation of it that might
/// differ.
public struct AgentProposal: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// The tool's raw name. Kept as a string so a proposal saved by an older
    /// MacB cannot fail to decode into a newer enum.
    public var tool: String
    public var arguments: String
    /// The line the user reads before saying yes.
    public var text: String
    public var isDone: Bool
    public var isRefused: Bool

    public init(id: UUID = UUID(), tool: String, arguments: String, text: String,
                isDone: Bool = false, isRefused: Bool = false) {
        self.id = id
        self.tool = tool
        self.arguments = arguments
        self.text = text
        self.isDone = isDone
        self.isRefused = isRefused
    }

    public var isPending: Bool { !isDone && !isRefused }

    public var call: JarvisCall { JarvisCall(callID: id.uuidString, name: tool, arguments: arguments) }
}

/// What a job may do by itself, and what it may only suggest.
///
/// Three lists, and the interesting one is the third. A job runs with nobody
/// there, so the ordinary confirmation — a card in the island — cannot happen.
/// Rather than weakening that gate for unattended work, the gate is moved: a
/// tool that would normally ask is not run at all, it becomes a proposal.
public enum AgentPolicy {
    /// Runs by itself. Reading, and nothing else. Everything on this list
    /// leaves the Mac exactly as it found it.
    public static func runsUnattended(_ tool: JarvisTool) -> Bool {
        switch tool {
        case .webSearch, .readMail, .calendarEvents, .systemStatus, .weather, .codingAgents:
            return true
        default:
            return false
        }
    }

    /// Never, not even as a suggestion.
    ///
    /// The screen, because looking at an unattended Mac's screen is looking at
    /// whatever was left on it — and the user is not there to refuse. Power,
    /// because a background task must never put the Mac to sleep under
    /// somebody. Ending the conversation, because there is no conversation.
    public static func isForbidden(_ tool: JarvisTool) -> Bool {
        switch tool {
        case .lookAtScreen, .readScreenText, .readSelection, .powerAction, .endConversation,
             .startBackgroundJob, .backgroundJobs:
            return true
        default:
            return false
        }
    }

    /// Everything else: prepared, written down, and waiting.
    public static func isProposed(_ tool: JarvisTool) -> Bool {
        !runsUnattended(tool) && !isForbidden(tool)
    }

    /// The tools a background job is offered at all. The forbidden ones are not
    /// declared to it: the cheapest way to not call a tool is to not know it.
    public static var availableTools: [JarvisTool] {
        JarvisTool.allCases.filter { !isForbidden($0) }
    }

    /// How many turns a job gets before it is stopped. A job that has been
    /// round eight times is not converging, it is looping.
    public static let maximumRounds = 8

    /// And how long, whatever it is doing.
    public static let timeLimit: TimeInterval = 5 * 60

    /// At most this many jobs are remembered. Old delivered ones fall off the
    /// end; a job list nobody can see the bottom of is a log, and MacB does not
    /// keep logs of what was asked.
    public static let maximumJobs = 12
}
