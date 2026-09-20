import Foundation
import MacBCore

/// The brain of the free voice mode: one question to a free provider, with
/// tools, and one answer back.
///
/// Not streamed. The free engine has nothing to do with half a sentence —
/// macOS's synthesiser speaks the answer once it is whole — and asking for it
/// whole means the tool calls arrive whole too.
///
/// Everything here goes to a provider with a free tier, so a conversation held
/// this way costs nothing. It is slower than the live engine and it cannot be
/// interrupted mid-sentence, which is the honest price of free.
@MainActor final class FreeVoiceEngine {
    struct Reply {
        var text: String
        var calls: [JarvisCall]
        var usage: AITokenUsage?
        /// The provider's own assistant message, to be echoed back untouched
        /// on the next turn. See `AIChatStream.assistantMessage`.
        var rawMessage: [String: Any]?

        /// What goes into the conversation for this turn.
        var historyMessage: [String: Any] {
            rawMessage ?? AIChatStream.assistantToolMessage(calls, text: text)
        }
    }

    enum Failure: LocalizedError {
        case noProvider
        case http(Int, String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noProvider:
                return "Ücretsiz mod için bir anahtar gerekiyor. Ayarlar › Araçlar'dan Gemini ya da Groq ekle."
            case .http(let code, let message):
                return message.isEmpty ? "Sağlayıcı \(code) döndürdü." : message
            case .unreadable:
                return "Cevap okunamadı."
            }
        }
    }

    private let keys: AIKeyStore
    private let model: (AIProvider) -> String
    private let preferred: () -> AIProvider?
    private let session: URLSession

    init(keys: AIKeyStore, model: @escaping (AIProvider) -> String,
         preferred: @escaping () -> AIProvider? = { nil }, session: URLSession = .shared) {
        self.keys = keys
        self.model = model
        self.preferred = preferred
        self.session = session
    }

    /// The free provider a conversation will run on, if there is one.
    ///
    /// Never OpenAI: this is the engine that exists so that nothing is billed,
    /// and quietly falling back to the paid one would defeat the point.
    var provider: AIProvider? {
        if let chosen = preferred(), chosen.isFree, keys.has(chosen) { return chosen }
        return AIProvider.textOrder.first { $0.isFree && keys.has($0) }
    }

    var isAvailable: Bool { provider != nil }

    func answer(messages: [[String: Any]],
                tools: [JarvisTool] = JarvisTool.freeEngineTools,
                maximumTokens: Int = 500) async throws -> Reply {
        guard let provider, let key = keys.read(provider) else { throw Failure.noProvider }
        let body = AIChatStream.toolRequestBody(messages: messages, model: model(provider),
                                                tools: tools.map(\.chatDeclaration),
                                                maximumTokens: maximumTokens)

        var request = URLRequest(url: provider.chatURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if provider == .openRouter {
            request.setValue("https://github.com/hamzqb/MacB", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("MacB", forHTTPHeaderField: "X-Title")
        }
        request.timeoutInterval = 45
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw Failure.http(code, AIChatStream.errorMessage(inBody: data) ?? "")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable
        }
        return Reply(text: AIChatStream.outputText(inResponse: object) ?? "",
                     calls: AIChatStream.toolCalls(inResponse: object),
                     usage: AITokenUsage(chatCompletions: object["usage"]),
                     rawMessage: AIChatStream.assistantMessage(inResponse: object))
    }

    /// The provider a conversation will say it is running on, for the island.
    var providerTitle: String { provider?.title ?? "ücretsiz" }
}
