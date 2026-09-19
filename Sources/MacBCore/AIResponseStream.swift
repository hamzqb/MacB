import Foundation

/// One source the model read and cited.
public struct AICitation: Equatable, Sendable, Identifiable {
    public let url: URL
    public let title: String
    public var id: String { url.absoluteString }

    public init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    /// What to call the source when it has no title worth showing.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (url.host ?? url.absoluteString) : trimmed
    }
}

/// What a line of the Responses API's event stream means for the answer on
/// screen.
///
/// The stream is server-sent events: `event:` and `data:` lines, one JSON
/// object per event. Only three things in it matter to somebody reading an
/// answer — more text arrived, the model went off to search, and it finished
/// with these sources — and everything else is bookkeeping this ignores rather
/// than fails on, so a new event type OpenAI adds next month is not an error.
///
/// Pure on purpose: the interesting failure in a streaming client is a line it
/// misreads, and that is provable with strings, without a network or a key.
public enum AIStreamEvent: Equatable, Sendable {
    /// More of the answer.
    case text(String)
    /// The model has started a web search. Worth saying, because it is the one
    /// part of an answer that takes seconds rather than milliseconds.
    case searching
    /// The answer is complete, with the sources it cited, deduplicated.
    case finished([AICitation])
    /// OpenAI said no. The message is theirs, meant for a person.
    case failed(String)
    /// Anything else in the stream.
    case ignored
}

public enum AIResponseStream {
    /// Reads one `data:` payload.
    public static func event(fromData line: String) -> AIStreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return .ignored }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return .ignored }

        switch type {
        case "response.output_text.delta":
            guard let delta = object["delta"] as? String, !delta.isEmpty else { return .ignored }
            return .text(delta)
        case "response.web_search_call.in_progress", "response.web_search_call.searching":
            return .searching
        case "response.completed":
            let response = object["response"] as? [String: Any] ?? [:]
            return .finished(citations(inResponse: response))
        case "response.failed", "error":
            return .failed(errorMessage(in: object) ?? "Yanıt alınamadı.")
        default:
            return .ignored
        }
    }

    /// Every `url_citation` in a finished response, in the order they were
    /// cited, each URL once.
    public static func citations(inResponse response: [String: Any]) -> [AICitation] {
        var seen = Set<String>()
        var found: [AICitation] = []
        for item in response["output"] as? [[String: Any]] ?? [] {
            for content in item["content"] as? [[String: Any]] ?? [] {
                for annotation in content["annotations"] as? [[String: Any]] ?? [] {
                    guard annotation["type"] as? String == "url_citation",
                          let string = annotation["url"] as? String,
                          let url = URL(string: string),
                          let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
                          seen.insert(url.absoluteString).inserted else { continue }
                    found.append(AICitation(url: url, title: annotation["title"] as? String ?? ""))
                }
            }
        }
        return found
    }

    private static func errorMessage(in object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let response = object["response"] as? [String: Any],
           let error = response["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }

    /// The request body for one question, with the conversation so far.
    ///
    /// The history travels in the request rather than being kept by OpenAI:
    /// `store` is off, so nothing asked here is retained on their side for later
    /// retrieval, and a follow-up question carries its own context instead.
    ///
    /// The instructions are the only thing MacB adds to what the user typed:
    /// answer in the language of the question, keep it short enough to read in
    /// a panel, and search when the answer depends on anything current. Nothing
    /// about the Mac, the user or their files is sent — only the conversation.
    public static func requestBody(question: String, model: String,
                                   history: [AITurn] = []) -> [String: Any] {
        var input: [[String: Any]] = []
        for turn in history.suffix(maximumHistory) {
            input.append(["role": "user", "content": turn.prompt])
            if !turn.answer.isEmpty { input.append(["role": "assistant", "content": turn.answer]) }
        }
        input.append(["role": "user", "content": question])
        return [
            "model": model,
            "input": input,
            "stream": true,
            "store": false,
            "tools": [["type": "web_search", "search_context_size": "medium"]],
            "instructions": """
                You are the assistant inside MacB, a small macOS utility. Answer in the \
                language the question is written in. Be direct and brief: the answer is read \
                in a small floating panel, so lead with the answer, then only the detail that \
                matters. Use web search whenever the answer depends on anything recent or \
                checkable, and cite what you used. Plain text with light Markdown only.
                """
        ]
    }

    /// How many earlier exchanges ride along with a new question.
    ///
    /// Enough for "and what about the other one?" to make sense; few enough that
    /// a long session does not quietly turn every question into a large bill.
    public static let maximumHistory = 6
}

/// One question and the answer it got.
public struct AITurn: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// What the panel shows as the question.
    public let question: String
    /// What was actually sent. The same as `question` for anything typed or
    /// spoken; for work on selected text it is the instruction plus the text,
    /// which is too long to show but has to ride along with a follow-up.
    public let prompt: String
    public var answer: String
    public var citations: [AICitation]

    public init(id: UUID = UUID(), question: String, prompt: String? = nil,
                answer: String = "", citations: [AICitation] = []) {
        self.id = id
        self.question = question
        self.prompt = prompt ?? question
        self.answer = answer
        self.citations = citations
    }
}

/// Something done to a piece of text the user selected in another application.
///
/// The instruction is written into the prompt rather than the system
/// instructions so the conversation that follows ("shorter", "now in English")
/// still knows what the text was and what was asked of it.
public enum AITextTask: String, CaseIterable, Sendable {
    case summarize
    case fix

    /// Past this many characters a selection is cut. A stray ⌘A on a long
    /// document should cost cents, not dollars.
    public static let maximumLength = 12_000

    public var title: String {
        switch self {
        case .summarize: return "Özetle"
        case .fix: return "Düzelt"
        }
    }

    /// The label the panel shows in place of the whole selection.
    public func question(for text: String) -> String {
        "\(title): “\(Self.preview(text))”"
    }

    /// A selection on one line, cut to fit a heading.
    public static func preview(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > 70 ? String(flat.prefix(70)) + "…" : flat
    }

    public func prompt(for text: String) -> String {
        let instruction: String
        switch self {
        case .summarize:
            instruction = "Summarize the text between the <text> tags in the language it is written in. "
                + "A few short bullet points, most important first. Reply with the summary only."
        case .fix:
            instruction = "Correct spelling, grammar and punctuation in the text between the <text> tags. "
                + "Keep its language, meaning, tone, line breaks and formatting. Do not search the web. "
                + "Reply with the corrected text only: no preface, no explanation, no quotes."
        }
        return "\(instruction)\n<text>\n\(text)\n</text>"
    }

    /// The selection as it will be sent, and whether it had to be cut.
    public static func clip(_ text: String) -> (text: String, truncated: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumLength else { return (trimmed, false) }
        return (String(trimmed.prefix(maximumLength)), true)
    }
}
