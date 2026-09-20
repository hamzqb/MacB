import Foundation

/// What one request cost, in tokens, as the provider counted it.
///
/// Their count, not a guess of MacB's: an estimate made by counting characters
/// is wrong in both directions and wrong differently per model, and a money
/// number that is wrong is worse than no money number at all.
public struct AITokenUsage: Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    /// Audio in and out, which the Realtime API prices separately and much
    /// higher than text.
    public var inputAudioTokens: Int
    public var outputAudioTokens: Int
    /// Input that was served from the provider's cache, billed at a fraction.
    public var cachedInputTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0,
                inputAudioTokens: Int = 0, outputAudioTokens: Int = 0,
                cachedInputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.inputAudioTokens = inputAudioTokens
        self.outputAudioTokens = outputAudioTokens
        self.cachedInputTokens = cachedInputTokens
    }

    public var isEmpty: Bool {
        inputTokens == 0 && outputTokens == 0 && inputAudioTokens == 0 && outputAudioTokens == 0
    }

    public static func + (lhs: AITokenUsage, rhs: AITokenUsage) -> AITokenUsage {
        AITokenUsage(inputTokens: lhs.inputTokens + rhs.inputTokens,
                     outputTokens: lhs.outputTokens + rhs.outputTokens,
                     inputAudioTokens: lhs.inputAudioTokens + rhs.inputAudioTokens,
                     outputAudioTokens: lhs.outputAudioTokens + rhs.outputAudioTokens,
                     cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens)
    }

    /// From a Responses API `usage` object.
    public init?(responsesAPI object: Any?) {
        guard let object = object as? [String: Any] else { return nil }
        let details = object["input_tokens_details"] as? [String: Any] ?? [:]
        self.init(inputTokens: object["input_tokens"] as? Int ?? 0,
                  outputTokens: object["output_tokens"] as? Int ?? 0,
                  cachedInputTokens: details["cached_tokens"] as? Int ?? 0)
        if isEmpty { return nil }
    }

    /// From a chat-completions `usage` object, which every compatible provider
    /// sends under the same names.
    public init?(chatCompletions object: Any?) {
        guard let object = object as? [String: Any] else { return nil }
        self.init(inputTokens: object["prompt_tokens"] as? Int ?? 0,
                  outputTokens: object["completion_tokens"] as? Int ?? 0)
        if isEmpty { return nil }
    }

    /// From a Realtime API `response.done` usage object, where the text and the
    /// audio are counted apart because they are priced apart.
    public init?(realtime object: Any?) {
        guard let object = object as? [String: Any] else { return nil }
        let input = object["input_token_details"] as? [String: Any] ?? [:]
        let output = object["output_token_details"] as? [String: Any] ?? [:]
        let cached = input["cached_tokens"] as? Int ?? 0
        self.init(inputTokens: input["text_tokens"] as? Int ?? 0,
                  outputTokens: output["text_tokens"] as? Int ?? 0,
                  inputAudioTokens: input["audio_tokens"] as? Int ?? 0,
                  outputAudioTokens: output["audio_tokens"] as? Int ?? 0,
                  cachedInputTokens: cached)
        if isEmpty { return nil }
    }
}

/// What a thousand tokens costs, so the counter can show money rather than a
/// number nobody can price.
///
/// Published rates, in US dollars per million tokens, written down here rather
/// than fetched: a price list is not worth a network call, and a wrong price is
/// better than a hidden one. They go stale — the settings window says so, and
/// says the figure is an estimate.
public struct AIRate: Equatable, Sendable {
    public var input: Double
    public var output: Double
    public var inputAudio: Double
    public var outputAudio: Double
    public var cachedInput: Double

    public init(input: Double, output: Double, inputAudio: Double = 0,
                outputAudio: Double = 0, cachedInput: Double? = nil) {
        self.input = input
        self.output = output
        self.inputAudio = inputAudio
        self.outputAudio = outputAudio
        self.cachedInput = cachedInput ?? input / 10
    }

    public static let free = AIRate(input: 0, output: 0)

    /// Dollars for one usage at this rate.
    public func cost(of usage: AITokenUsage) -> Double {
        let million = 1_000_000.0
        return (Double(usage.inputTokens) * input
                + Double(usage.outputTokens) * output
                + Double(usage.inputAudioTokens) * inputAudio
                + Double(usage.outputAudioTokens) * outputAudio
                + Double(usage.cachedInputTokens) * cachedInput) / million
    }
}

public enum AIPricing {
    /// The rate for a model, by the prefix of its name so a dated snapshot such
    /// as `gpt-realtime-2.1` is priced like the family it belongs to.
    ///
    /// Everything that is not OpenAI is priced at zero, because MacB only ever
    /// offers those providers' free tiers. If somebody puts a paid OpenRouter
    /// key in, the counter will read low and the settings window says it counts
    /// OpenAI only.
    public static func rate(provider: AIProvider, model: String) -> AIRate {
        guard provider == .openAI else { return .free }
        let name = model.lowercased()
        if name.contains("realtime") {
            // The mini model is priced as its own thing; without this line it
            // was counted at the full model's rate and the meter read three
            // times what the conversation actually cost.
            if name.contains("mini") {
                return AIRate(input: 0.6, output: 2.4, inputAudio: 10, outputAudio: 20, cachedInput: 0.06)
            }
            return AIRate(input: 4, output: 16, inputAudio: 32, outputAudio: 64, cachedInput: 0.4)
        }
        if name.hasPrefix("gpt-5-nano") { return AIRate(input: 0.05, output: 0.4) }
        if name.hasPrefix("gpt-5-mini") { return AIRate(input: 0.25, output: 2) }
        if name.hasPrefix("gpt-5") { return AIRate(input: 1.25, output: 10) }
        if name.hasPrefix("gpt-4.1-mini") { return AIRate(input: 0.4, output: 1.6) }
        if name.hasPrefix("gpt-4.1") { return AIRate(input: 2, output: 8) }
        if name.hasPrefix("gpt-4o-mini") { return AIRate(input: 0.15, output: 0.6) }
        if name.hasPrefix("gpt-4o") { return AIRate(input: 2.5, output: 10) }
        // An unknown OpenAI model: priced like their mid-range one rather than
        // like nothing, so the counter errs towards telling the truth.
        return AIRate(input: 1.25, output: 10)
    }

    /// Money as a person reads it. Small amounts get more decimals, because
    /// "$0.00" for every conversation teaches nothing.
    public static func money(_ dollars: Double) -> String {
        if dollars <= 0 { return "$0" }
        if dollars < 0.01 { return String(format: "$%.4f", dollars) }
        if dollars < 1 { return String(format: "$%.3f", dollars) }
        return String(format: "$%.2f", dollars)
    }
}

/// A ceiling on what MacB may spend in a day.
///
/// Not a billing control — OpenAI's own limits are that — but the thing that
/// stops one forgotten voice conversation running up a number nobody meant to
/// spend. MacB checks it before it opens anything that costs money, so the
/// refusal happens before the spending, not after.
public enum AIBudget {
    /// Zero means no ceiling, and is offered last on purpose.
    public static let choices: [Double] = [0.25, 0.50, 1, 2, 5, 0]

    public static let fallback: Double = 0.50

    public static func title(_ dollars: Double) -> String {
        dollars <= 0 ? "Sınırsız" : "Günde " + AIPricing.money(dollars)
    }

    /// Whether spending this much today means stopping.
    public static func isOver(spent: Double, limit: Double) -> Bool {
        limit > 0 && spent >= limit
    }
}

/// One day's spending, kept per day so the settings window can show today and
/// this month without keeping a log of what was asked.
///
/// Only numbers are stored: a date, token counts and a total. Never a question,
/// never an answer, never a model's reply.
public struct AISpendingDay: Codable, Equatable, Sendable {
    public var day: String
    public var dollars: Double
    public var requests: Int
    public var voiceSeconds: Double

    public init(day: String, dollars: Double = 0, requests: Int = 0, voiceSeconds: Double = 0) {
        self.day = day
        self.dollars = dollars
        self.requests = requests
        self.voiceSeconds = voiceSeconds
    }
}

public struct AISpending: Codable, Equatable, Sendable {
    public var days: [AISpendingDay]

    public init(days: [AISpendingDay] = []) {
        self.days = days
    }

    /// The key for a date, in the local calendar: spending is read by a person
    /// who means their own day, not a UTC one.
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Adds a cost to a day, keeping the list to the last `keptDays` days so it
    /// cannot grow without bound.
    public mutating func add(dollars: Double, voiceSeconds: Double = 0,
                             on date: Date = Date(), calendar: Calendar = .current) {
        let key = Self.key(for: date, calendar: calendar)
        if let index = days.firstIndex(where: { $0.day == key }) {
            days[index].dollars += dollars
            days[index].requests += 1
            days[index].voiceSeconds += voiceSeconds
        } else {
            days.append(AISpendingDay(day: key, dollars: dollars, requests: 1, voiceSeconds: voiceSeconds))
        }
        days.sort { $0.day < $1.day }
        if days.count > Self.keptDays { days.removeFirst(days.count - Self.keptDays) }
    }

    public static let keptDays = 90

    public func total(since date: Date, calendar: Calendar = .current) -> Double {
        let from = Self.key(for: date, calendar: calendar)
        return days.filter { $0.day >= from }.reduce(0) { $0 + $1.dollars }
    }

    public func today(_ now: Date = Date(), calendar: Calendar = .current) -> AISpendingDay {
        let key = Self.key(for: now, calendar: calendar)
        return days.first { $0.day == key } ?? AISpendingDay(day: key)
    }

    /// This calendar month so far.
    public func thisMonth(_ now: Date = Date(), calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.year, .month], from: now)
        let prefix = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        return days.filter { $0.day.hasPrefix(prefix) }.reduce(0) { $0 + $1.dollars }
    }
}
