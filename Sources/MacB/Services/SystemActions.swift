import AppKit
import Foundation
import MacBCore

/// The handful of system things MacB will do to the Mac itself.
///
/// Sleep, the display, the lock screen and the appearance — and nothing else.
/// There is no shut down and no restart here on purpose: those close documents
/// somebody may not have saved, and a voice assistant that mishears is not
/// something that should be able to end a working session. Everything in this
/// file is undone by moving the mouse or saying the opposite.
enum SystemActions {
    enum Power: String {
        case sleep
        case displaySleep = "display_sleep"
        case lock
    }

    enum Appearance: String {
        case dark, light, auto
    }

    /// Puts the Mac, or just its screen, to sleep — or locks it.
    ///
    /// `pmset` for sleep, which needs no administrator and is what the Apple
    /// menu does. The lock goes through the login window the same way fast user
    /// switching does; MacB never types, injects or handles a password.
    @discardableResult
    static func power(_ action: Power) -> Bool {
        switch action {
        case .sleep: return run("/usr/bin/pmset", ["sleepnow"])
        case .displaySleep: return run("/usr/bin/pmset", ["displaysleepnow"])
        case .lock:
            let session = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
            if FileManager.default.isExecutableFile(atPath: session), run(session, ["-suspend"]) { return true }
            // Older and newer macOS have moved this around; sleeping the
            // display locks too when the Mac is set to ask for a password.
            return run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    /// What it will say afterwards. Written before the Mac goes to sleep,
    /// because afterwards there is nobody to say it to.
    static func message(for action: Power) -> String {
        switch action {
        case .sleep: return "Mac uyuyor."
        case .displaySleep: return "Ekran kapandı."
        case .lock: return "Ekran kilitlendi."
        }
    }

    /// Dark or light, through System Events, the same switch as the one in
    /// System Settings.
    @discardableResult
    static func appearance(_ mode: Appearance) -> Bool {
        let source: String
        switch mode {
        case .dark:
            source = "tell application \"System Events\" to tell appearance preferences to set dark mode to true"
        case .light:
            source = "tell application \"System Events\" to tell appearance preferences to set dark mode to false"
        case .auto:
            // There is no scripting term for automatic; the defaults key is
            // what System Settings itself writes.
            return run("/usr/bin/defaults", ["write", "-g", "AppleInterfaceStyleSwitchesAutomatically", "-bool", "true"])
        }
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    /// Runs a tool with its arguments as arguments — never through a shell, so
    /// nothing in a name or a query can become a command.
    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}

/// Finding something to play, by name.
///
/// MacB has no music account and asks for none. What it can do is what a person
/// would do: put the name into the service and open the first thing that comes
/// back. Only a video identifier is ever read out of the page — no titles, no
/// descriptions, no comments — so nothing written on YouTube reaches the model.
enum MusicSearch {
    enum Service: String {
        case youtube
        case spotify
        case appleMusic = "apple_music"
    }

    struct Outcome {
        var opened: Bool
        /// What to tell the user, and the model, happened.
        var message: String
        /// Whether it actually started playing, as opposed to opening a search.
        var isPlaying: Bool
    }

    static func play(_ query: String, on service: Service) async -> Outcome {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Outcome(opened: false, message: "Ne çalınacağı yazılmamış.", isPlaying: false)
        }
        switch service {
        case .youtube:
            guard let identifier = await firstYouTubeVideo(matching: trimmed) else {
                let search = url("https://www.youtube.com/results", query: "search_query", trimmed)
                let opened = search.map { NSWorkspace.shared.open($0) } ?? false
                return Outcome(opened: opened, message: "Video bulunamadı; YouTube'da arama açıldı.", isPlaying: false)
            }
            guard let watch = URL(string: "https://www.youtube.com/watch?v=" + identifier) else {
                return Outcome(opened: false, message: "Video adresi kurulamadı.", isPlaying: false)
            }
            let opened = NSWorkspace.shared.open(watch)
            return Outcome(opened: opened, message: opened ? "YouTube'da açıldı ve çalıyor." : "YouTube açılamadı.",
                           isPlaying: opened)
        case .spotify:
            // Spotify's own search, in the app when it is installed and on the
            // web when it is not. Playing a particular track outright needs an
            // account token MacB deliberately does not hold.
            let app = URL(string: "spotify:search:" + (trimmed.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? trimmed))
            if let app, NSWorkspace.shared.urlForApplication(toOpen: app) != nil, NSWorkspace.shared.open(app) {
                return Outcome(opened: true, message: "Spotify açıldı, arama hazır — çalmak için birine bas.",
                               isPlaying: false)
            }
            let web = url("https://open.spotify.com/search/" + (trimmed.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed) ?? trimmed))
            let opened = web.map { NSWorkspace.shared.open($0) } ?? false
            return Outcome(opened: opened, message: opened ? "Spotify web'de arama açıldı." : "Spotify açılamadı.",
                           isPlaying: false)
        case .appleMusic:
            let search = url("https://music.apple.com/search", query: "term", trimmed)
            let opened = search.map { NSWorkspace.shared.open($0) } ?? false
            return Outcome(opened: opened, message: opened ? "Müzik uygulamasında arama açıldı." : "Müzik açılamadı.",
                           isPlaying: false)
        }
    }

    /// The first video on a results page.
    ///
    /// The page is fetched and scanned for the first `videoId`, which is eleven
    /// characters of a fixed alphabet. Nothing else is read out of it and
    /// nothing from it is shown to the model, so a video title cannot say
    /// anything to MacB.
    static func firstYouTubeVideo(matching query: String) async -> String? {
        guard let search = url("https://www.youtube.com/results", query: "search_query", query) else { return nil }
        var request = URLRequest(url: search)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { return nil }
        return YouTubeResults.firstVideoIdentifier(in: html)
    }

    private static func url(_ base: String, query name: String, _ value: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: name, value: value)]
        return components?.url
    }

    private static func url(_ string: String) -> URL? { URL(string: string) }
}
