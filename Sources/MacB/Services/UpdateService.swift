import AppKit
import Combine
import Foundation
import MacBCore

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease
    }
}

@MainActor final class UpdateService: ObservableObject {
    enum State: Equatable {
        case idle, checking, current, available(String), failed(String)
    }

    @Published private(set) var state: State = .idle
    private let endpoint = URL(string: "https://api.github.com/repos/hamzqb/MacB/releases/latest")!
    private let releasesPage = URL(string: "https://github.com/hamzqb/MacB/releases")!
    private var task: Task<Void, Never>?

    func checkAutomatically() {
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= 24 * 60 * 60 else { return }
        check(silent: true)
    }

    func check(silent: Bool = false) {
        guard task == nil else { return }
        state = .checking
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                var request = URLRequest(url: endpoint, timeoutInterval: 8)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("MacB/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                guard !release.draft, !release.prerelease,
                      release.htmlURL.host == "github.com",
                      release.htmlURL.path.hasPrefix("/hamzqb/MacB/releases/") else {
                    throw URLError(.cannotParseResponse)
                }
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                state = VersionNumber.isNewer(latest, than: AppVersion.current) ? .available(latest) : .current
            } catch {
                state = silent ? .idle : .failed("Güncelleme denetlenemedi. İnternet bağlantını kontrol et.")
            }
        }
    }

    func openReleases() { NSWorkspace.shared.open(releasesPage) }

}
