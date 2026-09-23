import Combine
import Foundation
import MacBCore

/// Remembers how each provider has been behaving, so the next question does
/// not go somewhere that just failed.
///
/// Counts and timestamps only. Nothing about what was asked, nothing about the
/// answer, nothing about the user — this could be handed to a stranger and it
/// would tell them only that a service was slow on a Tuesday.
@MainActor final class AIHealthStore: ObservableObject {
    @Published private(set) var health: [AIProvider: AIProviderHealth] = [:]

    private let defaults: UserDefaults
    private static let key = "aiProviderHealth"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode([String: AIProviderHealth].self, from: data) else { return }
        for (name, value) in stored {
            guard let provider = AIProvider(rawValue: name) else { continue }
            health[provider] = value
        }
    }

    func recordSuccess(_ provider: AIProvider, latency: TimeInterval) {
        var entry = health[provider] ?? AIProviderHealth()
        entry.recordSuccess(latency: latency)
        health[provider] = entry
        save()
    }

    func recordFailure(_ provider: AIProvider) {
        var entry = health[provider] ?? AIProviderHealth()
        entry.recordFailure()
        health[provider] = entry
        save()
    }

    /// One line for Settings, or nil when there is nothing worth saying.
    func note(for provider: AIProvider) -> String? {
        guard let entry = health[provider] else { return nil }
        if entry.isSick() { return "Son denemelerde cevap vermedi; MacB şimdilik başka sağlayıcıya gidiyor." }
        guard let latency = entry.lastLatency else { return nil }
        if latency > 20 { return String(format: "Son cevap %.0f saniyede geldi — yavaş.", latency) }
        return String(format: "Çalışıyor, son cevap %.1f saniyede başladı.", latency)
    }

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: health.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
