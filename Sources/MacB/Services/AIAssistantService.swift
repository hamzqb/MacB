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
    private let model: () -> String
    private var task: Task<Void, Never>?
    private var keyObserver: AnyCancellable?

    init(keys: AIKeyStore, model: @escaping () -> String) {
        self.keys = keys
        self.model = model
        // A key entered in Settings while the panel is open has to unlock the
        // question field at once, not the next time something else changes.
        keyObserver = keys.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var hasKey: Bool { keys.hasKey }

    static let missingKeyMessage = "Önce Ayarlar → Araçlar'dan OpenAI anahtarını gir."

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

    private func send(_ turn: AITurn) {
        guard let key = keys.read() else {
            errorMessage = Self.missingKeyMessage
            return
        }
        let history = turns
        turns.append(turn)
        errorMessage = nil
        isAnswering = true
        isSearching = false

        let body = AIResponseStream.requestBody(question: turn.prompt, model: model(), history: history)
        task = Task { [weak self] in
            await self?.stream(body: body, key: key, turnID: turn.id)
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

    private func stream(body: [String: Any], key: String, turnID: UUID) async {
        defer {
            // Only the question still on screen may say it has finished: a
            // stopped answer's stream winding down must not mark a newer one
            // as done.
            if turns.last?.id == turnID {
                isAnswering = false
                isSearching = false
            }
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                // The body of a failed request is a small JSON error from
                // OpenAI; read enough of it to say what went wrong.
                var text = ""
                for try await line in bytes.lines { text += line; if text.count > 4000 { break } }
                errorMessage = Self.message(forStatus: code, body: text)
                return
            }
            for try await line in bytes.lines {
                if Task.isCancelled { return }
                switch AIResponseStream.event(fromData: line) {
                case .text(let delta):
                    isSearching = false
                    update(turnID) { $0.answer += delta }
                case .searching:
                    isSearching = true
                case .finished(let citations):
                    update(turnID) { $0.citations = citations }
                    if selectionResult?.turnID == turnID {
                        selectionResult?.isComplete = true
                        copyResult()
                    }
                case .failed(let message):
                    errorMessage = message
                case .ignored:
                    break
                }
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            errorMessage = "OpenAI'ye ulaşılamadı: \(error.localizedDescription)"
        }
    }

    private func update(_ id: UUID, _ change: (inout AITurn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
    }

    private static func message(forStatus code: Int, body: String) -> String {
        if let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            switch code {
            case 401: return "OpenAI anahtarı reddetti. Ayarlar'dan yenisini gir."
            case 404: return "Model bulunamadı: \(message)"
            case 429: return "Kota ya da hız sınırı doldu: \(message)"
            default: return message
            }
        }
        return "OpenAI \(code) döndürdü."
    }
}
