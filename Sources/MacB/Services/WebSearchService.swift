import Foundation
import MacBCore

/// Looks things up on the web so a model that cannot search still answers
/// from today rather than from memory.
///
/// One search, then the first few pages, read as text. Nothing about the Mac
/// goes with the request: a search carries the words of the question and
/// nothing else, no identifier, no account, no history.
enum WebSearchService {
    /// How many results are opened and read.
    static let pagesRead = 3
    private static let timeout: TimeInterval = 8

    static func search(_ query: String, limit: Int = 5) async -> [WebResult] {
        guard var components = URLComponents(string: "https://html.duckduckgo.com/html/") else { return [] }
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "kl", value: "tr-tr")]
        guard let url = components.url else { return [] }
        guard let html = await fetchText(url) else { return [] }
        var results = WebGrounding.parseResults(html, limit: limit)
        guard !results.isEmpty else { return [] }
        // The first few results are read in parallel; the rest keep their
        // titles so the answer can still cite them.
        await withTaskGroup(of: (Int, String).self) { group in
            for index in 0..<min(pagesRead, results.count) {
                let target = results[index].url
                group.addTask {
                    let page = await fetchText(target) ?? ""
                    return (index, WebGrounding.readableText(from: page))
                }
            }
            for await (index, text) in group where !text.isEmpty {
                results[index].text = text
            }
        }
        return results
    }

    private static func fetchText(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        // A plain desktop browser's identity: some sites answer nothing at all
        // to a request without one. It says nothing about this Mac or user.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("tr,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 400 else { return nil }
            // A page over a couple of megabytes is not an article.
            guard data.count < 3_000_000 else { return nil }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        } catch {
            return nil
        }
    }
}
