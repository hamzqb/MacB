import Foundation

/// One result from a web search: what it is, where it is, and what it said.
public struct WebResult: Equatable, Sendable {
    public var title: String
    public var url: URL
    public var snippet: String
    /// The readable text of the page, when it was fetched.
    public var text: String

    public init(title: String, url: URL, snippet: String, text: String = "") {
        self.title = title
        self.url = url
        self.snippet = snippet
        self.text = text
    }
}

/// When a question needs the web, and how to turn what comes back into
/// something a model can answer from.
///
/// Only OpenAI's own models can search while they answer. Everything else —
/// the free providers MacB prefers — answers from training data, which for
/// "what is the dollar today" is worse than useless. So MacB does the
/// searching itself, hands the model what it found, and asks for an answer
/// with the sources named.
public enum WebGrounding {
    /// Words that mean the answer changes with time or is about something
    /// specific enough that a model's memory is the wrong place to look.
    private static let freshness = [
        "bugün", "şu an", "şuan", "güncel", "son dakika", "haber", "haberler", "kaç tl", "kaç dolar",
        "kaç euro", "kur", "fiyat", "fiyatı", "ne kadar", "kaça", "hava durumu", "maç", "skor",
        "puan durumu", "çıktı mı", "yayınlandı", "yeni sürüm", "sürüm", "ne zaman çıkacak",
        "bu hafta", "bu ay", "dün", "yarın", "canlı", "borsa", "bitcoin", "altın",
        "today", "latest", "current", "news", "price", "release", "version", "score"
    ]

    /// A year that has not been in a model's training set for long.
    private static let years = ["2025", "2026", "2027"]

    /// Whether MacB should look things up before answering.
    ///
    /// Deliberately generous with questions and mean with instructions: a
    /// question about the world is cheap to ground and expensive to get wrong,
    /// while "bu metni düzelt" has nothing to look up.
    public static func needsSearch(_ question: String) -> Bool {
        let text = question.lowercased()
        guard text.count > 3 else { return false }
        if text.contains("http://") || text.contains("https://") { return true }
        if freshness.contains(where: text.contains) { return true }
        if years.contains(where: text.contains) { return true }
        // "kimdir", "nedir", "nerede" and friends: facts about the world.
        let factual = ["kimdir", "nedir", "nerede", "hangi yıl", "kaç yılında", "who is", "what is"]
        if factual.contains(where: text.contains) { return true }
        return false
    }

    /// The search terms to use: the question, without the words that only
    /// address MacB.
    public static func query(from question: String) -> String {
        var text = question
        for filler in ["macb", "lütfen", "bana", "acaba", "bir bakar mısın", "söyler misin", "?"] {
            text = text.replacingOccurrences(of: filler, with: " ", options: .caseInsensitive)
        }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The links DuckDuckGo's HTML page lists, in order.
    ///
    /// Parsed rather than requested as JSON because the JSON endpoint answers
    /// with "instant answers" only. Anything that is not a plain http link is
    /// dropped, including the redirector's own relative links.
    public static func parseResults(_ html: String, limit: Int = 5) -> [WebResult] {
        var results: [WebResult] = []
        var seen = Set<String>()
        let pattern = #"<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard results.count < limit,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }
            let href = decodeEntities(String(html[hrefRange]))
            guard let url = resolve(href), seen.insert(url.absoluteString).inserted else { continue }
            let title = plainText(String(html[titleRange]))
            guard !title.isEmpty else { continue }
            results.append(WebResult(title: title, url: url, snippet: ""))
        }
        return results
    }

    /// DuckDuckGo hands back its own redirector for most results; the real
    /// address is in its `uddg` parameter.
    public static func resolve(_ href: String) -> URL? {
        var value = href
        if value.hasPrefix("//") { value = "https:" + value }
        guard let components = URLComponents(string: value) else { return nil }
        if let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let url = URL(string: target), url.scheme?.hasPrefix("http") == true {
            return url
        }
        guard let url = components.url, url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    /// The readable text of a page: scripts, styles and tags gone, whitespace
    /// collapsed, and clipped to something a prompt can carry.
    public static func readableText(from html: String, limit: Int = 4_000) -> String {
        var text = html
        for tag in ["script", "style", "noscript", "svg", "head"] {
            text = remove(tag: tag, from: text)
        }
        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</(p|div|li|h[1-6]|tr)>", with: "\n",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = decodeEntities(text)
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { $0.count > 1 }
        return String(lines.joined(separator: "\n").prefix(limit))
    }

    /// What goes to the model: the question, what was found, and the rule that
    /// the answer names its sources.
    public static func prompt(question: String, results: [WebResult], now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM yyyy HH:mm"
        var lines = ["Bugünün tarihi: \(formatter.string(from: now)).",
                     "Aşağıdaki kaynaklar az önce internetten alındı. Soruyu bunlara dayanarak yanıtla.",
                     "Kaynaklarda olmayan bir şeyi uydurma; bilgi yoksa bilmediğini söyle.",
                     "Cevabın sonunda kullandığın kaynakları [1], [2] gibi numaralarla listele.", ""]
        for (index, result) in results.enumerated() {
            lines.append("[\(index + 1)] \(result.title) — \(result.url.absoluteString)")
            let body = result.text.isEmpty ? result.snippet : result.text
            if !body.isEmpty { lines.append(body) }
            lines.append("")
        }
        lines.append("Soru: \(question)")
        return lines.joined(separator: "\n")
    }

    /// Drops a whole element, its content included. `NSString` has no
    /// "dot matches newlines" option, so the pattern says so itself.
    private static func remove(tag: String, from html: String) -> String {
        html.replacingOccurrences(of: "(?s)<\(tag)[^>]*>.*?</\(tag)>", with: " ",
                                  options: [.regularExpression, .caseInsensitive])
    }

    private static func plainText(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(stripped).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func decodeEntities(_ text: String) -> String {
        var value = text
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#x27;": "'",
                        "&#39;": "'", "&nbsp;": " ", "&hellip;": "…", "&mdash;": "—", "&ndash;": "–"]
        for (entity, character) in entities {
            value = value.replacingOccurrences(of: entity, with: character)
        }
        return value
    }
}
