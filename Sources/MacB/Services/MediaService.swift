import AppKit
import SwiftUI
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
    /// One colour taken from the cover, or nil when the cover has none worth
    /// using. Everything that follows the music is tinted with it.
    @Published private(set) var tint: Color?
    @Published private(set) var isPlaying = false
    /// Playback position and length in seconds. Zero means the source does not report them.
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
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
        let previousArtwork = artwork
        switch next {
        case .none:
            title = ""
            artist = ""
            artwork = nil
            isPlaying = false
            isRunning = false
            isAuthorized = true
            errorMessage = nil
            position = 0
            duration = 0
        case .spotify:
            title = spotify.trackTitle
            artist = spotify.artist
            artwork = spotify.artwork
            isPlaying = spotify.isPlaying
            isRunning = spotify.isRunning
            isAuthorized = spotify.isAuthorized
            errorMessage = spotify.errorMessage
            position = spotify.position
            duration = spotify.duration
        case .appleMusic:
            title = appleMusic.trackTitle
            artist = appleMusic.artist
            artwork = nil
            isPlaying = appleMusic.isPlaying
            isRunning = appleMusic.isRunning
            isAuthorized = appleMusic.isAuthorized
            errorMessage = appleMusic.errorMessage
            position = appleMusic.position
            duration = appleMusic.duration
        case .browser:
            title = browser.title
            artist = browser.sourceName
            artwork = nil
            isPlaying = browser.isPlaying
            isRunning = browser.isRunning
            isAuthorized = browser.isAuthorized
            errorMessage = browser.errorMessage
            position = browser.position
            duration = browser.duration
        }
        updateTint(previous: previousArtwork)
    }

    /// Reads the cover's colour once per cover, not once per poll: the services
    /// hand back the same image object until the track changes.
    private func updateTint(previous: NSImage?) {
        guard artwork !== previous else { return }
        guard let artwork else { tint = nil; return }
        tint = ArtworkPalette.tint(for: artwork)
    }

    private func bestSource() -> MediaSource {
        if spotify.isPlaying { return .spotify }
        if appleMusic.isPlaying { return .appleMusic }
        if browser.isPlaying { return .browser }
        // Pausing must not make the current track disappear. Keep the selected
        // source while it still exposes a real media item, then fall back to
        // another paused source with metadata.
        switch source {
        case .spotify where spotify.isRunning && !spotify.trackTitle.isEmpty: return .spotify
        case .appleMusic where appleMusic.isRunning && !appleMusic.trackTitle.isEmpty: return .appleMusic
        case .browser where browser.isRunning && !browser.title.isEmpty: return .browser
        default: break
        }
        if spotify.isRunning && !spotify.trackTitle.isEmpty { return .spotify }
        if appleMusic.isRunning && !appleMusic.trackTitle.isEmpty { return .appleMusic }
        if browser.isRunning && !browser.title.isEmpty { return .browser }
        return .none
    }
}
