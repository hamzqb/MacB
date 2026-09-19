import Combine
import Foundation
import MacBCore

/// What MacB has spent on OpenAI, per day, kept on this Mac.
///
/// Numbers only: a date, token counts and a total. Never a question, never an
/// answer, never a transcript. A spending log that recorded what was asked
/// would be a diary of everything said to the assistant, which is the last
/// thing a file at rest should be.
///
/// It is an estimate and says so. The rates are written down in `AIPricing`
/// rather than fetched, so they go stale, and a provider's own dashboard is
/// always the authority. It exists to answer "is this conversation costing me
/// pennies or pounds", which is a question worth answering roughly.
@MainActor final class AICostMeter: ObservableObject {
    @Published private(set) var spending = AISpending()
    /// The last thing that was billed, for the island to show right after a
    /// conversation ends.
    @Published private(set) var lastCost: Double?

    private let url: URL
    private var isUnreadable = false

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB", isDirectory: true)
            .appendingPathComponent("spending.json")
        load()
    }

    var today: AISpendingDay { spending.today() }
    var thisMonth: Double { spending.thisMonth() }

    var todayText: String { AIPricing.money(today.dollars) }
    var monthText: String { AIPricing.money(thisMonth) }

    /// Records one request. Free providers cost nothing and are still counted
    /// as requests, so the settings window can say how much was asked for free.
    func record(provider: AIProvider, model: String, usage: AITokenUsage?, voiceSeconds: Double = 0) {
        guard let usage, !usage.isEmpty else { return }
        let dollars = AIPricing.rate(provider: provider, model: model).cost(of: usage)
        lastCost = dollars
        spending.add(dollars: dollars, voiceSeconds: voiceSeconds)
        save()
    }

    /// Forgets the record. There is no other copy.
    func reset() {
        spending = AISpending()
        lastCost = nil
        save()
    }

    // MARK: - Storage

    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AISpending.self, from: data) else {
            // A file that exists but cannot be read is not an empty one: never
            // write over it, or a bad parse silently erases the history.
            isUnreadable = true
            return
        }
        spending = decoded
    }

    private func save() {
        guard !isUnreadable else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(spending) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
