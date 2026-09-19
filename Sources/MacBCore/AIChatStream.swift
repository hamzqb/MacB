import Foundation

/// The other dialect: OpenAI's older `/chat/completions`, which Groq,
/// OpenRouter, Google and Hugging Face all speak as their compatibility
/// endpoint.
///
/// Simpler than the Responses API and missing the one thing that matters —
/// there is no server-side web search here, so an answer from these providers
/// is what the model already knows and carries no citations. The panel says so
/// rather than pretending otherwise.
///
/// Pure on purpose, like `AIResponseStream`: the interesting failure in a
/// streaming client is a line it misreads, and that is provable with strings,
/// without a network or a key.
public enum AIChatStream {
    /// Reads one `data:` payload of a chat-completions stream.
    public static func event(fromData line: String) -> AIStreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return .ignored }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        // The stream ends with a literal sentinel rather than an event, so this
        // is where a finished answer is announced.
        guard payload != "[DONE]" else { return .finished([], nil) }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .ignored
        }
        if let error = object["error"] as? [String: Any] {
            return .failed(error["message"] as? String ?? "Yanıt alınamadı.")
        }
        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else {
            // The last chunk of some providers carries only the token counts.
            if let usage = AITokenUsage(chatCompletions: object["usage"]) { return .finished([], usage) }
            return .ignored
        }
        // Some providers send the whole message rather than a delta on the last
        // chunk; both carry the text under `content`.
        let delta = first["delta"] as? [String: Any] ?? first["message"] as? [String: Any] ?? [:]
        if let text = delta["content"] as? String, !text.isEmpty { return .text(text) }
        return .ignored
    }

    /// The request body for one question, with the conversation so far.
    ///
    /// The same shape for every compatible provider. The history travels in the
    /// request — none of these keep it — and nothing about the Mac, the user or
    /// their files is added: only the conversation and the instructions below.
    public static func requestBody(question: String, model: String,
                                   history: [AITurn] = []) -> [String: Any] {
        var messages: [[String: Any]] = [["role": "system", "content": instructions]]
        for turn in history.suffix(AIResponseStream.maximumHistory) {
            messages.append(["role": "user", "content": turn.prompt])
            if !turn.answer.isEmpty { messages.append(["role": "assistant", "content": turn.answer]) }
        }
        messages.append(["role": "user", "content": question])
        // Ask for the token counts on the last chunk, so the cost counter has
        // the provider's own number rather than a guess.
        return ["model": model, "messages": messages, "stream": true,
                "stream_options": ["include_usage": true]]
    }

    /// Told to say when it does not know, because this is the path with no web
    /// search behind it: a confident wrong answer is worse here than anywhere
    /// else in MacB.
    static let instructions = """
        You are the assistant inside MacB, a small macOS utility. Answer in the \
        language the question is written in. Be direct and brief: the answer is read \
        in a small floating panel, so lead with the answer, then only the detail that \
        matters. You cannot browse the web — if the answer depends on something recent \
        or checkable, say plainly that you cannot check it. Plain text with light \
        Markdown only.
        """

    /// The text of a non-streamed answer, for the places that ask one question
    /// and want one string back.
    public static func outputText(inResponse object: [String: Any]) -> String? {
        guard let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content
    }
}
