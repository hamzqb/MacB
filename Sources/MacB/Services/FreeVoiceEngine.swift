import Foundation
import MacBCore

/// The brain of the free voice mode: one question to the local model or a free
/// provider, with tools, and one answer back.
///
/// The local model comes first when it is downloaded and turned on: it needs
/// no internet, has no daily limit, and nothing it reads leaves the Mac. A free
/// provider is the fallback, when there is no local model or it fails.
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
        /// Answered on this Mac: nothing to record in the cost meter.
        var isLocal = false
        /// Every word of `text` has already gone to `onSpeech`.
        var wasStreamed = false

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
                return "Ücretsiz mod için yerel modeli indir ya da Ayarlar › Araçlar'dan Gemini veya Groq anahtarı ekle."
            case .http(let code, let message):
                return message.isEmpty ? "Sağlayıcı \(code) döndürdü." : message
            case .unreadable:
                return "Cevap okunamadı."
            }
        }
    }

    private let keys: AIKeyStore
    private let model: (AIProvider) -> String
    private let chosenModel: (AIProvider) -> String?
    private let preferred: () -> AIProvider?
    private let health: AIHealthStore?
    private let session: URLSession

    init(keys: AIKeyStore, model: @escaping (AIProvider) -> String,
         preferred: @escaping () -> AIProvider? = { nil },
         readsScreen: @escaping () -> Bool = { false },
         usesLocal: @escaping () -> Bool = { false }, session: URLSession = .shared,
         chosenModel: @escaping (AIProvider) -> String? = { _ in nil },
         health: AIHealthStore? = nil) {
        self.readsScreen = readsScreen
        self.usesLocal = usesLocal
        self.keys = keys
        self.model = model
        self.chosenModel = chosenModel
        self.preferred = preferred
        self.health = health
        self.session = session
    }

    /// The free provider a conversation will run on, if there is one.
    ///
    /// Never OpenAI: this is the engine that exists so that nothing is billed,
    /// and quietly falling back to the paid one would defeat the point.
    var provider: AIProvider? { route.first?.provider }

    /// Every free provider that could run this conversation, best first.
    ///
    /// The list matters as much as the first entry: a free tier goes down, or
    /// answers in two minutes, and the conversation should move on rather than
    /// stop. Never OpenAI — this is the engine that exists so that nothing is
    /// billed, and quietly falling back to the paid one would defeat the point.
    var route: [(provider: AIProvider, model: String)] {
        AIRouter.order(for: .tools, stored: keys.stored, preferred: preferred(),
                       health: health?.health ?? [:], freeOnly: true)
            .flatMap { provider in AIRouter.models(of: provider, for: .tools, chosen: chosenModel(provider)) }
    }

    var isAvailable: Bool { runsLocally || provider != nil }

    /// Whether the screen's text may go to the free provider. The user's call.
    let readsScreen: () -> Bool
    /// Whether the user wants the local model used when it is there.
    private let usesLocal: () -> Bool
    private let local = LocalLLM.shared

    /// The next answer comes from this Mac.
    var runsLocally: Bool { usesLocal() && LocalLLM.isInstalled() }

    /// What a conversation on this engine may use. The screen's text is
    /// always allowed to a local model: it never leaves the Mac.
    var conversationTools: [JarvisTool] {
        JarvisTool.freeEngineTools(readsScreen: runsLocally || readsScreen())
    }

    /// Starts loading the local model and reading the instructions and tools
    /// while the user is still speaking. Nothing happens for a provider.
    func prepare(messages: [[String: Any]], tools: [JarvisTool]) {
        guard runsLocally else { return }
        let system = LocalModel.withExamples(Array(messages.prefix(1)))
        var prompt = LocalModel.prompt(messages: system, tools: tools.map(\.chatDeclaration), reminder: "")
        // Everything up to the first user turn, which is what every turn of
        // this conversation starts with.
        if prompt.hasSuffix("<|im_start|>assistant\n") {
            prompt.removeLast("<|im_start|>assistant\n".count)
        }
        local.prepare(prompt: prompt)
    }

    func answer(messages: [[String: Any]],
                tools: [JarvisTool] = JarvisTool.freeEngineTools,
                maximumTokens: Int = 500,
                onSpeech: (@MainActor (String) -> Void)? = nil) async throws -> Reply {
        if runsLocally {
            do {
                return try await answerLocally(messages: messages, tools: tools, maximumTokens: maximumTokens,
                                               onSpeech: onSpeech)
            } catch {
                // A provider can still answer; without one, say why.
                guard provider != nil else { throw error }
            }
        }
        return try await answerByProvider(messages: messages, tools: tools, maximumTokens: maximumTokens)
    }

    private func answerLocally(messages: [[String: Any]], tools: [JarvisTool], maximumTokens: Int,
                               onSpeech: (@MainActor (String) -> Void)?) async throws -> Reply {
        var messages = messages
        let declarations = tools.map(\.chatDeclaration)
        // Too long for the model's memory: the oldest turns go first, the
        // instructions never.
        while true {
            let prompt = LocalModel.prompt(messages: LocalModel.withExamples(messages), tools: declarations)
            let stream = SpeechRelay(onSpeech)
            let onText: (@Sendable (String) -> Void)?
            if onSpeech != nil {
                onText = { text in stream.feed(text) }
            } else {
                onText = nil
            }
            do {
                let (generated, _) = try await local.generate(prompt: prompt, maximumTokens: maximumTokens,
                                                              onText: onText)
                await stream.finish(generated)
                let output = LocalModel.parse(generated, callPrefix: "local-\(UUID().uuidString.prefix(8))")
                return Reply(text: output.text, calls: output.calls, usage: nil, rawMessage: nil,
                             isLocal: true, wasStreamed: onSpeech != nil)
            } catch LocalLLM.Failure.tooLong where messages.count > 2 {
                messages.remove(at: 1)
                while messages.count > 2, messages[1]["role"] as? String == "tool" { messages.remove(at: 1) }
            }
        }
    }

    private func answerByProvider(messages: [[String: Any]], tools: [JarvisTool],
                                  maximumTokens: Int) async throws -> Reply {
        let route = self.route
        guard !route.isEmpty else { throw Failure.noProvider }
        var firstFailure: Error?
        for (attempt, candidate) in route.enumerated() {
            guard let key = keys.read(candidate.provider) else { continue }
            do {
                return try await ask(candidate, key: key, messages: messages, tools: tools,
                                     maximumTokens: maximumTokens,
                                     timeout: AIRouter.timeout(attempt: attempt, of: route.count))
            } catch {
                firstFailure = firstFailure ?? error
                health?.recordFailure(candidate.provider)
                if case Failure.http(let code, _) = error {
                    // A server error is usually a bad moment rather than a
                    // broken provider: ask the same one once more.
                    if AIRouter.shouldRetrySame(status: code),
                       let reply = try? await ask(candidate, key: key, messages: messages, tools: tools,
                                                  maximumTokens: maximumTokens,
                                                  timeout: AIRouter.timeout(attempt: attempt, of: route.count)) {
                        return reply
                    }
                    // A provider that refused for a reason another one would
                    // share — a malformed request, say — is not worth asking
                    // twice.
                    if !AIRouter.shouldTryAnother(status: code) { throw error }
                }
            }
        }
        throw firstFailure ?? Failure.noProvider
    }

    private func ask(_ candidate: (provider: AIProvider, model: String), key: String,
                     messages: [[String: Any]], tools: [JarvisTool],
                     maximumTokens: Int, timeout: TimeInterval) async throws -> Reply {
        let provider = candidate.provider
        let body = AIChatStream.toolRequestBody(messages: messages, model: candidate.model,
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
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let started = Date()
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw Failure.http(code, AIChatStream.errorMessage(inBody: data) ?? "")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable
        }
        health?.recordSuccess(provider, latency: Date().timeIntervalSince(started))
        return Reply(text: AIChatStream.outputText(inResponse: object) ?? "",
                     calls: AIChatStream.toolCalls(inResponse: object),
                     usage: AITokenUsage(chatCompletions: object["usage"]),
                     rawMessage: AIChatStream.assistantMessage(inResponse: object))
    }

    /// The provider a conversation will say it is running on, for the island.
    var providerTitle: String { runsLocally ? "yerel model" : (provider?.title ?? "ücretsiz") }
}

/// Carries sentences from the model's queue to the main actor, in order.
private final class SpeechRelay: @unchecked Sendable {
    private let onSpeech: (@MainActor (String) -> Void)?
    private var stream = SpokenStream()

    init(_ onSpeech: (@MainActor (String) -> Void)?) { self.onSpeech = onSpeech }

    /// On the model's queue. The main queue runs blocks in the order they
    /// were sent, so sentences cannot overtake each other.
    func feed(_ text: String) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                for sentence in stream.feed(text) { onSpeech?(sentence) }
            }
        }
    }

    @MainActor func finish(_ text: String) async {
        // Behind every sentence already queued.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        guard let onSpeech else { return }
        for sentence in stream.finish(text) { onSpeech(sentence) }
    }
}
