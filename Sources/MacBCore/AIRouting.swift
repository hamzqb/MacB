import Foundation

/// What a question needs, so it can be sent somewhere that can actually do it.
///
/// One provider is rarely best at everything: the one with the strongest
/// reasoning is slow to say hello, the fastest cannot see a picture, and the
/// one that calls functions reliably is not the one to ask a hard question.
/// Naming the job lets each be used for what it is good at.
public enum AITask: String, Sendable, CaseIterable {
    /// The panel, the ring, a spoken reply: a person is waiting.
    case chat
    /// A hard question, worth a slower and larger model.
    case reasoning
    /// There is a picture in the request.
    case vision
    /// The assistant's own loop, which lives or dies on calling the right
    /// function with the right arguments.
    case tools
}

extension AIProvider {
    /// The model to use for a job, or nil when this provider cannot do it.
    ///
    /// Names that the provider's own `/models` answers with. They change —
    /// NVIDIA retired `meta/llama-3.3-70b-instruct` under MacB and every
    /// request came back "410 Gone" — so Settings can always override this,
    /// and "Modelleri yenile" asks the service itself.
    public func model(for task: AITask) -> String? {
        switch self {
        case .openAI:
            switch task {
            case .chat, .tools: return "gpt-5-mini"
            case .reasoning: return "gpt-5"
            case .vision: return "gpt-5-mini"
            }
        case .nvidia:
            // Measured against the service rather than taken from its
            // catalogue, which lists far more than a given key can call:
            // Nemotron 3 Super answers in about a second and calls functions
            // properly, while the larger Nemotrons answer 503, gpt-oss never
            // answered at all, and the 90-billion vision model times out where
            // the 11-billion one replies at once.
            switch task {
            case .chat, .tools, .reasoning: return "nvidia/nemotron-3-super-120b-a12b"
            case .vision: return "meta/llama-3.2-11b-vision-instruct"
            }
        case .groq:
            switch task {
            case .chat, .tools, .reasoning: return "openai/gpt-oss-120b"
            case .vision: return nil
            }
        case .gemini:
            switch task {
            case .chat, .tools: return "gemini-3.6-flash"
            case .reasoning: return "gemini-pro-latest"
            case .vision: return "gemini-flash-latest"
            }
        case .openRouter:
            switch task {
            case .chat, .tools, .reasoning: return "meta-llama/llama-3.3-70b-instruct:free"
            case .vision: return "meta-llama/llama-3.2-90b-vision-instruct:free"
            }
        case .huggingFace:
            switch task {
            case .chat, .tools, .reasoning: return "meta-llama/Llama-3.3-70B-Instruct"
            case .vision: return nil
            }
        }
    }
}

/// How a provider has been behaving lately, on this Mac.
///
/// Nothing about the user is in here: how many requests failed, when, and how
/// long the last good one took. It exists because a free tier is a promise
/// rather than a guarantee — a model is retired, a queue backs up, a key hits
/// its daily limit — and the assistant should route around that by itself
/// instead of handing the same failure to the user twice.
public struct AIProviderHealth: Codable, Sendable, Equatable {
    public var failures: Int = 0
    public var lastFailure: Date?
    public var lastSuccess: Date?
    /// Seconds the last good answer took to start arriving.
    public var lastLatency: TimeInterval?

    public init() {}

    /// How long a failure keeps a provider out of first place.
    public static let sickFor: TimeInterval = 15 * 60

    /// Two failures with nothing good since, recently enough to still mean
    /// something. One failure is a bad minute; two is a pattern.
    public func isSick(now: Date = Date()) -> Bool {
        guard failures >= 2, let lastFailure else { return false }
        guard now.timeIntervalSince(lastFailure) < Self.sickFor else { return false }
        if let lastSuccess, lastSuccess > lastFailure { return false }
        return true
    }

    public mutating func recordSuccess(latency: TimeInterval, now: Date = Date()) {
        failures = 0
        lastSuccess = now
        lastLatency = latency
    }

    public mutating func recordFailure(now: Date = Date()) {
        failures += 1
        lastFailure = now
    }
}

/// Which provider a question goes to, and where it goes next when that one
/// cannot answer.
///
/// The order is the whole point. What the user chose in Settings comes first,
/// as long as it can do the job and is not currently failing; then the free
/// providers that can; then anything that charges; and last the ones that have
/// been failing, because "probably broken" still beats "nothing".
public enum AIRouter {
    /// The providers to try for a job, best first.
    /// How many providers one question may be tried on.
    ///
    /// Three. Every extra name is another wait the user sits through before
    /// being told it did not work, and if three services in a row have
    /// nothing to say, the fourth is not the problem.
    public static let maximumAttempts = 3

    public static func order(for task: AITask,
                             stored: Set<AIProvider>,
                             preferred: AIProvider? = nil,
                             health: [AIProvider: AIProviderHealth] = [:],
                             freeOnly: Bool = false,
                             limit: Int = maximumAttempts,
                             now: Date = Date()) -> [AIProvider] {
        var able = AIProvider.textOrder.filter { provider in
            stored.contains(provider) && provider.model(for: task) != nil && (!freeOnly || provider.isFree)
        }
        // Falling back is not a reason to start spending. A paid provider is
        // in the list only when the user chose it, or when no free key can do
        // the job at all — a free tier failing twice is not permission to
        // send the next question somewhere that charges for it.
        if preferred?.isFree != false, able.contains(where: { $0.isFree }) {
            able = able.filter(\.isFree)
        }
        func rank(_ provider: AIProvider) -> Int {
            var rank = AIProvider.textOrder.firstIndex(of: provider) ?? 50
            if !provider.isFree { rank += 100 }
            if health[provider]?.isSick(now: now) == true { rank += 1_000 }
            if provider == preferred { rank -= 500 }
            return rank
        }
        let sorted = able.sorted { first, second in
            let left = rank(first)
            let right = rank(second)
            // A stable order when nothing separates two providers, so the same
            // question does not wander between them.
            if left == right { return (AIProvider.textOrder.firstIndex(of: first) ?? 0)
                < (AIProvider.textOrder.firstIndex(of: second) ?? 0) }
            return left < right
        }
        return Array(sorted.prefix(max(1, limit)))
    }

    /// The models to try for one provider: what the user chose first, then
    /// MacB's own pick for the job.
    ///
    /// Both, because a chosen model goes stale. These services retire names
    /// without warning, and a name that was typed into Settings a month ago
    /// now answers "404 — unknown model". Falling back to the current pick
    /// means the answer still arrives; the setting is left alone, because it
    /// is the user's.
    public static func models(of provider: AIProvider, for task: AITask,
                              chosen: String?) -> [(provider: AIProvider, model: String)] {
        var names: [String] = []
        if let chosen, !chosen.isEmpty { names.append(chosen) }
        if let mine = provider.model(for: task), !names.contains(mine) { names.append(mine) }
        return names.map { (provider, $0) }
    }

    /// Whether a failed attempt is worth repeating somewhere else.
    ///
    /// A retired model, a queue, a rate limit, a provider having a bad day:
    /// another provider would very likely answer. A cancelled request would
    /// not — the user stopped it.
    public static func shouldTryAnother(status: Int) -> Bool {
        switch status {
        case 401, 403: return true       // this key is no good; another may be
        case 404, 410: return true       // model gone
        case 408, 429: return true       // too slow, too many
        case 500...599: return true
        default: return false
        }
    }

    /// Whether the same provider is worth asking again straight away.
    ///
    /// A server error from these services is often a bad second rather than a
    /// bad afternoon — NVIDIA answers the identical request with 500 about one
    /// time in three and with a tool call the rest of the time. One immediate
    /// retry costs nothing and saves the conversation from wandering off to a
    /// weaker provider.
    public static func shouldRetrySame(status: Int) -> Bool {
        (500...599).contains(status)
    }

    /// How long to wait for the first sign of life before trying somewhere
    /// else. The last provider in the list gets the long wait, because there
    /// is nowhere to go after it.
    public static func timeout(attempt: Int, of total: Int) -> TimeInterval {
        attempt + 1 >= total ? 60 : 20
    }
}
