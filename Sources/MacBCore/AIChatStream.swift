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

    /// A whole conversation, not streamed, with tools the model may call.
    ///
    /// The free voice engine does not stream: it has nothing to do with half a
    /// sentence, because the sentence is spoken by macOS's synthesiser once it
    /// is complete. Asking for it whole makes the tool calls arrive whole too,
    /// which is the difference between parsing JSON and reassembling it from
    /// deltas.
    public static func toolRequestBody(messages: [[String: Any]], model: String,
                                       tools: [[String: Any]],
                                       maximumTokens: Int = 500) -> [String: Any] {
        var body: [String: Any] = ["model": model, "messages": messages,
                                   "max_tokens": maximumTokens, "temperature": 0.6]
        if !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        return body
    }

    /// The tool calls in a finished answer.
    ///
    /// Providers disagree about whether a call's arguments are a JSON string or
    /// an object already, and about whether an id is sent at all, so both are
    /// normalised here: the rest of MacB gets a `JarvisCall` with a string, the
    /// same shape the live engine produces, and a call with no id gets one made
    /// up rather than being dropped.
    public static func toolCalls(inResponse object: [String: Any]) -> [JarvisCall] {
        guard let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let raw = message["tool_calls"] as? [[String: Any]] else { return [] }
        return raw.enumerated().compactMap { index, entry in
            guard let function = entry["function"] as? [String: Any],
                  let name = function["name"] as? String, !name.isEmpty else { return nil }
            let arguments: String
            if let text = function["arguments"] as? String {
                arguments = text
            } else if let dictionary = function["arguments"] as? [String: Any],
                      let data = try? JSONSerialization.data(withJSONObject: dictionary),
                      let text = String(data: data, encoding: .utf8) {
                arguments = text
            } else {
                arguments = "{}"
            }
            let id = (entry["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "call_\(index)"
            return JarvisCall(callID: id, name: name, arguments: arguments)
        }
    }

    /// The assistant's message exactly as the provider sent it.
    ///
    /// Echoed back verbatim on the next turn rather than rebuilt from the
    /// calls, because providers attach things to it that they then require to
    /// come back. Google's Gemini 3 signs each function call with a
    /// `thought_signature` inside `extra_content` and refuses the next turn
    /// without it: "Function call is missing a thought_signature". Rebuilding
    /// the message drops anything MacB does not know about, and MacB should
    /// not have to know about it.
    public static func assistantMessage(inResponse object: [String: Any]) -> [String: Any]? {
        guard let choices = object["choices"] as? [[String: Any]],
              var message = choices.first?["message"] as? [String: Any] else { return nil }
        // A null content is legal in the wire format and unhelpful on the way
        // back; an empty string is what every provider accepts.
        if message["content"] is NSNull || message["content"] == nil { message["content"] = "" }
        return message
    }

    /// The message that carries the model's own tool calls back to it, so the
    /// next turn knows what it asked for.
    public static func assistantToolMessage(_ calls: [JarvisCall], text: String?) -> [String: Any] {
        var message: [String: Any] = ["role": "assistant", "content": text ?? ""]
        message["tool_calls"] = calls.map { call in
            ["id": call.callID, "type": "function",
             "function": ["name": call.name, "arguments": call.arguments]] as [String: Any]
        }
        return message
    }

    public static func toolResultMessage(callID: String, output: String) -> [String: Any] {
        ["role": "tool", "tool_call_id": callID, "content": output]
    }

    /// The message out of a failed request's body.
    ///
    /// Providers do not agree on the shape. OpenAI and Groq send an object
    /// with `error.message`; Google sends an array with one of those inside
    /// it, which read as an object returns nothing and left MacB saying
    /// "Sağlayıcı 404 döndürdü" while the body explained exactly what was
    /// wrong. Both are read here.
    public static func errorMessage(inBody data: Data) -> String? {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let object: [String: Any]?
        if let single = parsed as? [String: Any] {
            object = single
        } else if let list = parsed as? [[String: Any]] {
            object = list.first
        } else {
            object = nil
        }
        guard let error = object?["error"] as? [String: Any] else { return nil }
        return (error["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The text of a non-streamed answer, for the places that ask one question
    /// and want one string back.
    public static func outputText(inResponse object: [String: Any]) -> String? {
        guard let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content
    }
}
