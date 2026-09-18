import Combine
import Foundation
import MacBCore

/// Asks OpenAI a question and streams the answer back, with a web search when
/// the model decides it needs one.
///
/// Only what the user typed goes out, plus the last few exchanges of the same
/// conversation so a follow-up makes sense. No file, no clipboard entry, no
/// window title, nothing about the Mac. `store` is off on every request, so
/// OpenAI keeps no retrievable copy of the conversation, and MacB keeps it only
/// in memory: closing the panel's conversation forgets it.
@MainActor final class AIAssistantService: ObservableObject {
    @Published private(set) var turns: [AITurn] = []
    @Published private(set) var isAnswering = false
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

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

    func ask(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else { return }
        guard let key = keys.read() else {
            errorMessage = "Önce Ayarlar → Araçlar'dan OpenAI anahtarını gir."
            return
        }
        let history = turns
        let turn = AITurn(question: question)
        turns.append(turn)
        errorMessage = nil
        isAnswering = true
        isSearching = false

        let body = AIResponseStream.requestBody(question: question, model: model(), history: history)
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
