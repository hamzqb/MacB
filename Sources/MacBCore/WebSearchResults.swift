import Foundation

/// A free web search: DuckDuckGo's plain HTML results page, read on the Mac.
///
/// The assistant used to search through OpenAI's web search tool, which bills
/// every call on top of the tokens. Most questions are answered by the first
/// few result snippets and one page, and those cost nothing to fetch. The paid
/// route stays as a fallback for when this page cannot be read.
public enum WebSearchResults {
    public struct Result: Equatable, Sendable {
        public let title: String
        public let url: URL
        public let snippet: String

        public var site: String { url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? "" }

        public init(title: String, url: URL, snippet: String) {
            self.title = title
            self.url = url
            self.snippet = snippet
        }
    }

    public static let maximumResults = 5

    /// The results page for a query, in Turkish and for Turkey.
    public static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")
        components?.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "kl", value: "tr-tr")]
        return components?.url
    }

    /// Titles, links and snippets from the results page, ads left out.
    public static func parse(_ html: String, limit: Int = maximumResults) -> [Result] {
        var results: [Result] = []
        var seen = Set<String>()
        // Each result is an anchor with class result__a, followed somewhere
        // after by its snippet anchor, before the next result begins.
        let blocks = html.components(separatedBy: "class=\"result__a\"").dropFirst()
        for block in blocks {
            guard let href = attribute("href", in: block),
                  let url = resolve(href),
                  let titleEnd = block.range(of: "</a>"),
                  let titleStart = block.range(of: ">") else { continue }
            guard titleStart.upperBound <= titleEnd.lowerBound else { continue }
            let title = plain(String(block[titleStart.upperBound..<titleEnd.lowerBound]))
            var snippet = ""
            if let marker = block.range(of: "class=\"result__snippet\""),
               let open = block[marker.upperBound...].range(of: ">"),
               let close = block[open.upperBound...].range(of: "</a>") {
                snippet = plain(String(block[open.upperBound..<close.lowerBound]))
            }
            guard !title.isEmpty, seen.insert(url.absoluteString).inserted else { continue }
            results.append(Result(title: title, url: url, snippet: snippet))
            if results.count == limit { break }
        }
        return results
    }

    /// Readable text of a page: scripts, styles and tags gone, entities
    /// decoded, whitespace collapsed, clipped.
    public static func pageText(_ html: String, limit: Int = 1_800) -> String {
        var text = html
        for tag in ["script", "style", "noscript", "svg", "nav", "footer", "header"] {
            text = text.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: " ",
                                             options: [.regularExpression, .caseInsensitive])
        }
        return String(plain(text).prefix(limit))
    }

    /// Tags stripped, entities decoded, whitespace collapsed.
    public static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#x27;": "'", "&#39;": "'",
                        "&nbsp;": " ", "&apos;": "'"]
        for (entity, character) in entities { text = text.replacingOccurrences(of: entity, with: character) }
        text = decodeNumericEntities(text)
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private static func attribute(_ name: String, in text: String) -> String? {
        guard let start = text.range(of: "\(name)=\""),
              let end = text[start.upperBound...].range(of: "\"") else { return nil }
        return String(text[start.upperBound..<end.lowerBound]).replacingOccurrences(of: "&amp;", with: "&")
    }

    /// A result link, which is either the page itself or a DuckDuckGo
    /// redirect carrying it in `uddg`. Ad redirects are dropped.
    private static func resolve(_ href: String) -> URL? {
        let absolute = href.hasPrefix("//") ? "https:" + href : href
        guard let url = URL(string: absolute), let host = url.host else { return nil }
        if host.hasSuffix("duckduckgo.com") {
            guard url.path == "/l" || url.path == "/l/",
                  let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "uddg" })?.value,
                  let resolved = URL(string: target) else { return nil }
            return isWeb(resolved) ? resolved : nil
        }
        return isWeb(url) ? url : nil
    }

    private static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.hasSuffix("duckduckgo.com") else { return false }
        return true
    }

    private static func decodeNumericEntities(_ text: String) -> String {
        guard text.contains("&#") else { return text }
        var output = ""
        var rest = Substring(text)
        while let start = rest.range(of: "&#") {
            output += rest[..<start.lowerBound]
            let after = rest[start.upperBound...]
            if let end = after.firstIndex(of: ";"), after.distance(from: after.startIndex, to: end) <= 8 {
                let body = after[..<end]
                let value = body.hasPrefix("x") || body.hasPrefix("X")
                    ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
                if let value, let scalar = Unicode.Scalar(value) {
                    output.unicodeScalars.append(scalar)
                    rest = after[after.index(after: end)...]
                    continue
                }
            }
            output += "&#"
            rest = after
        }
        return output + rest
    }
}
