import AppKit
import Combine
import Foundation
import MacBCore

/// Asks OpenAI a question and streams the answer back, with a web search when
/// the model decides it needs one.
///
/// Only what the user typed or said goes out — or, when they pick "summarise"
/// or "fix" on the ring, the text they had selected — plus the last few
/// exchanges of the same conversation so a follow-up makes sense. No file, no
/// clipboard entry, no window title, nothing about the Mac. `store` is off on every request, so
/// OpenAI keeps no retrievable copy of the conversation, and MacB keeps it only
/// in memory: closing the panel's conversation forgets it.
@MainActor final class AIAssistantService: ObservableObject {
    @Published private(set) var turns: [AITurn] = []
    @Published private(set) var isAnswering = false
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    /// The answer that is about a selection, and what has been done with it.
    @Published private(set) var selectionResult: SelectionResult?
    /// A translation that needs a language macOS has not downloaded yet.
    @Published private(set) var languageDownload: LanguageDownload?
    /// macOS's own download sheet is up; the panel must not close under it.
    @Published var isDownloadingLanguage = false

    struct LanguageDownload {
        let source: String
        let target: String
        /// Runs the translation again once the language is there.
        let retry: () -> Void
    }

    /// A result that came from text selected in another application: copied
    /// when it is complete, and, where that application allows it, able to
    /// replace the selection.
    struct SelectionResult {
        /// Whether "put it back" may be offered at all.
        var canReplace: Bool { isComplete && !isTruncated && !isReplaced && selection.canReplace }

        let turnID: UUID
        let selection: SelectedTextService.Selection
        /// Only part of the selection was sent, so the answer covers only part
        /// of it and must never be written over the whole.
        var isTruncated = false
        /// The answer arrived in full. A stopped or failed one is never
        /// offered as a replacement.
        var isComplete = false
        var isCopied = false
        var isReplaced = false
        var note: String?
    }

    private let keys: AIKeyStore
    private let model: (AIProvider) -> String
    /// The model the user chose for a provider, when they chose one. Nil means
    /// MacB picks the right model for the job.
    private let chosenModel: (AIProvider) -> String?
    private let preferredProvider: () -> AIProvider?
    private let health: AIHealthStore?
    private let cost: AICostMeter?
    /// Whether MacB may look something up before answering. The question's
    /// own words go to the search engine and nothing else.
    private let searchesWebSetting: () -> Bool
    private var task: Task<Void, Never>?
    private var keyObserver: AnyCancellable?

    init(keys: AIKeyStore, model: @escaping (AIProvider) -> String,
         preferredProvider: @escaping () -> AIProvider? = { nil },
         cost: AICostMeter? = nil,
         searchesWeb: @escaping () -> Bool = { true },
         chosenModel: @escaping (AIProvider) -> String? = { _ in nil },
         health: AIHealthStore? = nil) {
        self.keys = keys
        self.model = model
        self.chosenModel = chosenModel
        self.preferredProvider = preferredProvider
        self.health = health
        self.cost = cost
        self.searchesWebSetting = searchesWeb
        // A key entered in Settings while the panel is open has to unlock the
        // question field at once, not the next time something else changes.
        keyObserver = keys.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var hasKey: Bool { keys.hasKey }

    var searchesWeb: Bool { searchesWebSetting() }

    /// Which provider a question goes to: the one chosen in Settings when it
    /// has a key, otherwise the best free one that does.
    var provider: AIProvider? {
        if let chosen = preferredProvider(), keys.has(chosen) { return chosen }
        return AIProvider.automatic(stored: keys.stored)
    }

    /// Where a question of this kind goes, in order, with the model each one
    /// should answer it with.
    ///
    /// More than one, because a free tier is a promise rather than a
    /// guarantee: a model is retired, a queue backs up, a key hits its limit.
    /// When the first cannot answer, MacB moves to the next by itself instead
    /// of handing the user an error they can do nothing about.
    func candidates(for task: AITask) -> [(provider: AIProvider, model: String)] {
        AIRouter.order(for: task, stored: keys.stored, preferred: preferredProvider(),
                       health: health?.health ?? [:])
            .flatMap { provider in AIRouter.models(of: provider, for: task, chosen: chosenModel(provider)) }
    }

    static let missingKeyMessage = "Önce Ayarlar → Araçlar'dan bir yapay zekâ anahtarı gir."

    func ask(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else { return }
        send(AITurn(question: question))
    }

    /// Summarises or corrects text selected in another application. Starts a
    /// fresh conversation: the selection is the subject, not an aside in
    /// whatever was being discussed before.
    func run(_ task: AITextTask, on selection: SelectedTextService.Selection) {
        stop()
        turns = []
        errorMessage = nil
        let (text, truncated) = AITextTask.clip(selection.text)
        let turn = AITurn(question: task.question(for: text), prompt: task.prompt(for: text))
        selectionResult = SelectionResult(turnID: turn.id, selection: selection, isTruncated: truncated,
                                          note: truncated ? "Seçim uzundu; ilk \(AITextTask.maximumLength) karakter gönderildi, yerine koyma kapalı." : nil)
        send(turn)
    }

    /// Shows a result that was produced on the Mac, such as a translation, in
    /// the same place and with the same copy and replace controls.
    func show(localResult answer: String, question: String, selection: SelectedTextService.Selection) {
        stop()
        errorMessage = nil
        languageDownload = nil
        let turn = AITurn(question: question, answer: answer)
        turns = [turn]
        selectionResult = SelectionResult(turnID: turn.id, selection: selection, isComplete: true)
        copyResult()
    }

    /// Shows a problem without a question, such as nothing being selected.
    func report(_ message: String, download: LanguageDownload? = nil) {
        stop()
        turns = []
        selectionResult = nil
        errorMessage = message
        languageDownload = download
    }

    /// The language arrived (or the download was refused): take the offer down.
    func finishLanguageDownload(success: Bool) {
        let download = languageDownload
        languageDownload = nil
        isDownloadingLanguage = false
        if success {
            errorMessage = nil
            download?.retry()
        } else {
            errorMessage = "Dil paketi indirilemedi. Sistem Ayarları › Genel › Dil ve Bölge › Çeviri Dilleri'nden de indirebilirsin."
        }
    }

    /// Puts the finished answer on the clipboard.
    func copyResult() {
        guard var result = selectionResult,
              let answer = turns.first(where: { $0.id == result.turnID })?.answer,
              !answer.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(answer, forType: .string)
        result.isCopied = true
        selectionResult = result
    }

    /// Writes the finished answer over the text it was made from.
    func replaceSelection(using reader: SelectedTextService) {
        guard var result = selectionResult, result.canReplace,
              let answer = turns.first(where: { $0.id == result.turnID })?.answer,
              !answer.isEmpty else { return }
        // The selection's own leading and trailing whitespace goes back around
        // the answer, so replacing a paragraph does not glue it to the next.
        let original = result.selection.text
        let leading = original.prefix { $0.isWhitespace || $0.isNewline }
        let trailing = String(original.reversed().prefix { $0.isWhitespace || $0.isNewline }.reversed())
        let replacement = String(leading) + answer.trimmingCharacters(in: .whitespacesAndNewlines) + trailing
        result.isReplaced = reader.replace(result.selection, with: replacement)
        if !result.isReplaced {
            result.note = "Yerine konmadı: seçim değişmiş ya da \(result.selection.appName) izin vermiyor. Sonuç panoda."
        }
        selectionResult = result
    }

    /// Answers a question about the window in front, by looking at it.
    ///
    /// The picture is one window — never the whole screen — and it goes only
    /// to a provider whose model can see. Nothing is written to disk; where no
    /// provider can see, the caller falls back to reading the screen's text on
    /// the Mac.
    func askAboutScreen(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = question.isEmpty ? "Ekranda ne var? Kısaca anlat." : question
        let route = usable(candidates(for: .vision))
        guard !route.isEmpty else {
            errorMessage = keys.stored.isEmpty ? Self.missingKeyMessage
                : "Anahtarı olan sağlayıcıların hiçbiri görsel anlamıyor. Ayarlar → Araçlar'dan NVIDIA, Gemini ya da OpenAI ekle."
            return
        }
        let turn = AITurn(question: prompt, prompt: prompt)
        turns.append(turn)
        errorMessage = nil
        isAnswering = true
        task = Task { [weak self] in
            guard let self else { return }
            let capture: (jpeg: Data, appName: String)
            do {
                capture = try await ScreenLookService.captureFrontmostWindow()
            } catch {
                self.errorMessage = error.localizedDescription
                self.finish(turn.id)
                return
            }
            var firstProblem: String?
            for (attempt, candidate) in route.enumerated() {
                if Task.isCancelled { return }
                guard let key = self.keys.read(candidate.provider) else { continue }
                let body = AIChatStream.visionRequestBody(
                    question: "Bu \(capture.appName) penceresinin görüntüsü. \(prompt)",
                    jpeg: capture.jpeg, model: candidate.model)
                var outcome = await self.stream(body: body, provider: candidate.provider, model: candidate.model,
                                                key: key, turnID: turn.id,
                                                timeout: AIRouter.timeout(attempt: attempt, of: route.count))
                // A server error is usually a bad moment rather than a broken
                // provider: ask the same one once more before moving on.
                if case .failed(_, _, true) = outcome {
                    outcome = await self.stream(body: body, provider: candidate.provider, model: candidate.model,
                                                key: key, turnID: turn.id,
                                                timeout: AIRouter.timeout(attempt: attempt, of: route.count))
                }
                switch outcome {
                case .answered, .cancelled:
                    self.finish(turn.id)
                    return
                case .failed(let message, let tryAnother, _):
                    firstProblem = firstProblem ?? message
                    guard tryAnother, attempt + 1 < route.count else {
                        self.errorMessage = firstProblem
                        self.finish(turn.id)
                        return
                    }
                }
            }
            self.errorMessage = firstProblem
            self.finish(turn.id)
        }
    }

    private func send(_ turn: AITurn) {
        let route = usable(candidates(for: .chat))
        guard !route.isEmpty else {
            errorMessage = provider == nil ? Self.missingKeyMessage
                : "Bugünlük harcama sınırına ulaşıldı (\(cost?.limitText ?? "")). Ayarlar \u{203A} Maliyet'ten değiştir ya da ücretsiz bir sağlayıcı seç."
            return
        }
        let history = turns
        turns.append(turn)
        errorMessage = nil
        isAnswering = true
        isSearching = false

        task = Task { [weak self] in
            guard let self else { return }
            var grounded: String?
            var firstProblem: String?
            for (attempt, candidate) in route.enumerated() {
                if Task.isCancelled { return }
                guard let key = self.keys.read(candidate.provider) else { continue }
                var question = turn.prompt
                // Only OpenAI's own models can search while they answer. For
                // the others MacB searches first and hands over what it found,
                // so an answer about today is about today. Searched once, even
                // when the question ends up going to a second provider.
                if !candidate.provider.canSearchWeb, self.searchesWeb, WebGrounding.needsSearch(turn.prompt) {
                    if grounded == nil {
                        await MainActor.run { self.isSearching = true }
                        let results = await WebSearchService.search(WebGrounding.query(from: turn.prompt))
                        await MainActor.run { self.isSearching = false }
                        if Task.isCancelled { return }
                        if !results.isEmpty {
                            grounded = WebGrounding.prompt(question: turn.prompt, results: results)
                        }
                    }
                    question = grounded ?? question
                }
                let body = candidate.provider.canSearchWeb
                    ? AIResponseStream.requestBody(question: question, model: candidate.model, history: history)
                    : AIChatStream.requestBody(question: question, model: candidate.model, history: history)
                var outcome = await self.stream(body: body, provider: candidate.provider, model: candidate.model,
                                                key: key, turnID: turn.id,
                                                timeout: AIRouter.timeout(attempt: attempt, of: route.count))
                // A server error is usually a bad moment rather than a broken
                // provider: ask the same one once more before moving on.
                if case .failed(_, _, true) = outcome {
                    outcome = await self.stream(body: body, provider: candidate.provider, model: candidate.model,
                                                key: key, turnID: turn.id,
                                                timeout: AIRouter.timeout(attempt: attempt, of: route.count))
                }
                switch outcome {
                case .answered, .cancelled:
                    self.finish(turn.id)
                    return
                case .failed(let message, let tryAnother, _):
                    firstProblem = firstProblem ?? message
                    guard tryAnother, attempt + 1 < route.count else {
                        self.errorMessage = firstProblem
                        self.finish(turn.id)
                        return
                    }
                }
            }
            self.errorMessage = firstProblem
            self.finish(turn.id)
        }
    }

    /// The candidates that may actually be used right now: the paid one is
    /// left out once the day's ceiling is reached, because a free key that is
    /// already stored should never be skipped in favour of a bill.
    private func usable(_ route: [(provider: AIProvider, model: String)]) -> [(provider: AIProvider, model: String)] {
        route.filter { candidate in
            guard !candidate.provider.isFree, let cost else { return true }
            return !cost.isOverDailyLimit
        }
    }

    /// Stops the answer where it is. What has arrived stays on screen.
    func stop() {
        task?.cancel()
        task = nil
        isAnswering = false
        isSearching = false
    }

    /// Forgets the conversation. There is no other copy of it.
    func clear() {
        stop()
        turns = []
        errorMessage = nil
        selectionResult = nil
        languageDownload = nil
    }

    /// What became of one attempt at an answer.
    private enum StreamOutcome {
        /// Something arrived and is on screen. Never retried: a second
        /// provider would write its answer underneath the first.
        case answered
        case cancelled
        case failed(message: String, tryAnother: Bool, retrySame: Bool = false)
    }

    private func stream(body: [String: Any], provider: AIProvider, model: String,
                        key: String, turnID: UUID, timeout: TimeInterval = 120) async -> StreamOutcome {
        var wrote = false
        let started = Date()
        var request = URLRequest(url: provider.chatURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if provider == .openRouter {
            // OpenRouter asks callers to identify themselves; this is the app,
            // not the user, and carries nothing about them.
            request.setValue("https://github.com/hamzqb/MacB", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("MacB", forHTTPHeaderField: "X-Title")
        }
        // The timeout is really "how long with nothing arriving": every chunk
        // of the stream resets it. So a provider that has started answering is
        // given as long as it needs, and one that has gone quiet is dropped
        // quickly enough to ask somewhere else while the user is still
        // waiting.
        request.timeoutInterval = timeout
        var failure: StreamOutcome?
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                // The body of a failed request is a small JSON error; read
                // enough of it to say what went wrong.
                var text = ""
                for try await line in bytes.lines { text += line; if text.count > 4000 { break } }
                health?.recordFailure(provider)
                return .failed(message: Self.message(forStatus: code, body: text, provider: provider),
                               tryAnother: AIRouter.shouldTryAnother(status: code),
                               retrySame: AIRouter.shouldRetrySame(status: code))
            }
            for try await line in bytes.lines {
                if Task.isCancelled { return .cancelled }
                let event = provider.canSearchWeb ? AIResponseStream.event(fromData: line)
                                                  : AIChatStream.event(fromData: line)
                switch event {
                case .text(let delta):
                    isSearching = false
                    if !wrote {
                        wrote = true
                        health?.recordSuccess(provider, latency: Date().timeIntervalSince(started))
                    }
                    update(turnID) { $0.answer += delta }
                case .searching:
                    isSearching = true
                case .finished(let citations, let usage):
                    cost?.record(provider: provider, model: model, usage: usage)
                    if !citations.isEmpty { update(turnID) { $0.citations = citations } }
                    if selectionResult?.turnID == turnID {
                        selectionResult?.isComplete = true
                        copyResult()
                    }
                case .failed(let message):
                    failure = .failed(message: message, tryAnother: !wrote)
                case .ignored:
                    break
                }
            }
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            return .cancelled
        } catch {
            health?.recordFailure(provider)
            return .failed(message: "\(provider.title)'ye ulaşılamadı: \(error.localizedDescription)",
                           tryAnother: !wrote)
        }
        if wrote { return .answered }
        if let failure { return failure }
        // A stream that ended without a word is a failure however politely it
        // was delivered.
        health?.recordFailure(provider)
        return .failed(message: "\(provider.title) boş cevap döndürdü.", tryAnother: true)
    }

    /// The question is done with, whether it was answered or not.
    ///
    /// Only the question still on screen may say so: a stopped answer's stream
    /// winding down must not mark a newer one as finished.
    private func finish(_ turnID: UUID) {
        guard turns.last?.id == turnID else { return }
        isAnswering = false
        isSearching = false
    }

    private func update(_ id: UUID, _ change: (inout AITurn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
    }

    private static func message(forStatus code: Int, body: String, provider: AIProvider) -> String {
        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            switch code {
            case 401, 403: return "\(provider.title) anahtarı reddetti. Ayarlar'dan yenisini gir."
            case 404:
                return "\(provider.title) bu modeli tanımıyor. Ayarlar → Araçlar'dan “Modelleri yenile”ye bas ve listeden seç. (\(message))"
            case 429: return "Kota ya da hız sınırı doldu: \(message)"
            default: return message
            }
        }
        return "OpenAI \(code) döndürdü."
    }
}
