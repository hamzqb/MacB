import AppKit
import Combine

enum MediaSource: String, CaseIterable, Identifiable {
    case spotify, appleMusic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        }
    }
    var symbol: String {
        switch self {
        case .spotify: return "music.note"
        case .appleMusic: return "music.quarternote.3"
        }
    }
}

@MainActor
final class MediaService: ObservableObject {
    @Published private(set) var source: MediaSource = .spotify
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var isRunning = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var errorMessage: String?

    let spotify: SpotifyService
    let appleMusic: AppleMusicService
    private var subscriptions: Set<AnyCancellable> = []

    init(spotify: SpotifyService, appleMusic: AppleMusicService) {
        self.spotify = spotify
        self.appleMusic = appleMusic
        wire()
    }

    func start() {
        spotify.start()
        appleMusic.start()
        sync()
    }

    func stop() {
        spotify.stop()
        appleMusic.stop()
        sync()
    }

    func setPanelVisible(_ visible: Bool) {
        spotify.setPanelVisible(visible)
        appleMusic.setPanelVisible(visible)
    }

    func choose(_ source: MediaSource) {
        self.source = source
        sync(preferred: source)
    }

    func requestAuthorization() {
        switch source {
        case .spotify: spotify.requestAuthorization()
        case .appleMusic: appleMusic.requestAuthorization()
        }
    }

    func openActiveSource() {
        switch source {
        case .spotify: spotify.openSpotify()
        case .appleMusic: appleMusic.openAppleMusic()
        }
    }

    func open(_ source: MediaSource) {
        choose(source)
        openActiveSource()
    }

    func playPause() {
        switch source {
        case .spotify: spotify.playPause()
        case .appleMusic: appleMusic.playPause()
        }
    }

    func previousTrack() {
        switch source {
        case .spotify: spotify.previousTrack()
        case .appleMusic: appleMusic.previousTrack()
        }
    }

    func nextTrack() {
        switch source {
        case .spotify: spotify.nextTrack()
        case .appleMusic: appleMusic.nextTrack()
        }
    }

    private func wire() {
        let publishers: [AnyPublisher<Void, Never>] = [
            spotify.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            appleMusic.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        ]
        publishers.forEach { publisher in
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.sync() }
                .store(in: &subscriptions)
        }
    }

    private func sync(preferred: MediaSource? = nil) {
        let next = preferred ?? bestSource()
        source = next
        switch next {
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
        }
    }

    private func bestSource() -> MediaSource {
        if spotify.isPlaying { return .spotify }
        if appleMusic.isPlaying { return .appleMusic }
        if source == .spotify, spotify.isRunning { return .spotify }
        if source == .appleMusic, appleMusic.isRunning { return .appleMusic }
        if spotify.isRunning { return .spotify }
        if appleMusic.isRunning { return .appleMusic }
        return source
    }
}
