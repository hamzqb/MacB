import AppKit
import Combine

enum MediaSource: String, Identifiable {
    case none, spotify, appleMusic, browser
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Medya"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .browser: return "Tarayıcı"
        }
    }
    var symbol: String {
        switch self {
        case .none: return "play.rectangle"
        case .spotify: return "music.note"
        case .appleMusic: return "music.quarternote.3"
        case .browser: return "globe"
        }
    }
}

@MainActor
final class MediaService: ObservableObject {
    @Published private(set) var source: MediaSource = .none
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var isRunning = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var errorMessage: String?

    let spotify: SpotifyService
    let appleMusic: AppleMusicService
    let browser: BrowserMediaService
    private var subscriptions: Set<AnyCancellable> = []

    init(spotify: SpotifyService, appleMusic: AppleMusicService, browser: BrowserMediaService) {
        self.spotify = spotify
        self.appleMusic = appleMusic
        self.browser = browser
        wire()
    }

    func start() {
        spotify.start()
        appleMusic.start()
        browser.start()
        sync()
    }

    func stop() {
        spotify.stop()
        appleMusic.stop()
        browser.stop()
        sync()
    }

    func setPanelVisible(_ visible: Bool) {
        spotify.setPanelVisible(visible)
        appleMusic.setPanelVisible(visible)
        browser.setPanelVisible(visible)
    }

    func requestAuthorization() {
        switch source {
        case .none, .browser: break
        case .spotify: spotify.requestAuthorization()
        case .appleMusic: appleMusic.requestAuthorization()
        }
    }

    func playPause() {
        switch source {
        case .none: break
        case .spotify: spotify.playPause()
        case .appleMusic: appleMusic.playPause()
        case .browser: browser.playPause()
        }
    }

    func previousTrack() {
        switch source {
        case .none: break
        case .spotify: spotify.previousTrack()
        case .appleMusic: appleMusic.previousTrack()
        case .browser: browser.previousTrack()
        }
    }

    func nextTrack() {
        switch source {
        case .none: break
        case .spotify: spotify.nextTrack()
        case .appleMusic: appleMusic.nextTrack()
        case .browser: browser.nextTrack()
        }
    }

    private func wire() {
        let publishers: [AnyPublisher<Void, Never>] = [
            spotify.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            appleMusic.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            browser.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        ]
        publishers.forEach { publisher in
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.sync() }
                .store(in: &subscriptions)
        }
    }

    private func sync() {
        let next = bestSource()
        source = next
        switch next {
        case .none:
            title = ""
            artist = ""
            artwork = nil
            isPlaying = false
            isRunning = false
            isAuthorized = true
            errorMessage = nil
        case .spotify:
            title = spotify.trackTitle
            artist = spotify.artist
            artwork = spotify.artwork
            isPlaying = spotify.isPlaying
            isRunning = spotify.isRunning
            isAuthorized = spotify.isAuthorized
            errorMessage = spotify.errorMessage
        case .appleMusic:
            title = appleMusic.trackTitle
            artist = appleMusic.artist
            artwork = nil
            isPlaying = appleMusic.isPlaying
            isRunning = appleMusic.isRunning
            isAuthorized = appleMusic.isAuthorized
            errorMessage = appleMusic.errorMessage
        case .browser:
            title = browser.title
            artist = browser.sourceName
            artwork = nil
            isPlaying = browser.isPlaying
            isRunning = browser.isRunning
            isAuthorized = browser.isAuthorized
            errorMessage = browser.errorMessage
        }
    }

    private func bestSource() -> MediaSource {
        if spotify.isPlaying { return .spotify }
        if appleMusic.isPlaying { return .appleMusic }
        if browser.isPlaying { return .browser }
        return .none
    }
}
