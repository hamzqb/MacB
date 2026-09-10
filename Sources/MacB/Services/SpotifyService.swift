import AppKit
import Carbon
import Combine
import ImageIO

private struct SpotifySnapshot {
    var title = ""
    var artist = ""
    var artworkURL = ""
    var playing = false
    var error: String?
    var denied = false
}

private final class ArtworkRedirectPolicy: NSObject, URLSessionTaskDelegate {
    static func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host == "scdn.co" || host.hasSuffix(".scdn.co") || host == "spotifycdn.com" || host.hasSuffix(".spotifycdn.com")
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.allows) == true ? request : nil)
    }
}

@MainActor
final class SpotifyService: ObservableObject {
    @Published var trackTitle = ""
    @Published var artist = ""
    @Published var artwork: NSImage?
    @Published var isPlaying = false
    @Published var isRunning = false
    @Published var isAuthorized = false
    @Published var errorMessage: String?

    private let queue = DispatchQueue(label: "MacB.Spotify", qos: .utility)
    private var observers: [NSObjectProtocol] = []
    private var pollingTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var panelVisible = false
    private var started = false
    private var inFlight = false
    private var pendingCommands: [String] = []
    private var generation = 0
    private var artworkKey = ""
    private let artworkCache = NSCache<NSURL, NSImage>()

    func start() {
        guard !started else { return }
        started = true
        artworkCache.countLimit = 12
        artworkCache.totalCostLimit = 20 * 1_024 * 1_024
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshRunningState() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pollingTask?.cancel(); self?.pollingTask = nil }
        })
        refreshRunningState()
    }

    func stop() {
        started = false
        generation += 1
        pollingTask?.cancel()
        pollingTask = nil
        artworkTask?.cancel()
        artworkTask = nil
        pendingCommands.removeAll()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    func setPanelVisible(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        pollingTask?.cancel()
        pollingTask = nil
        refreshRunningState()
    }

    func requestAuthorization() {
        guard isRunning, !inFlight else {
            if !isRunning { errorMessage = "Önce Spotify’ı açın, ardından bağlantıya izin verin." }
            return
        }
        inFlight = true
        let token = generation
        queue.async { [weak self] in
            let status = Self.permissionStatus(prompt: true)
            Task { @MainActor in
                guard let self else { return }
                self.inFlight = false
                guard self.generation == token, self.started else { return }
                self.isAuthorized = status == noErr
                self.errorMessage = status == noErr ? nil : "Spotify otomasyon izni verilmedi. Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon bölümünü kontrol edin."
                self.poll()
            }
        }
    }

    func playPause() { command("playpause") }
    func previousTrack() { command("previous track") }
    func nextTrack() { command("next track") }

    func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            errorMessage = "Spotify yüklü değil. Spotify’ı yükledikten sonra tekrar deneyin."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor [weak self] in
                if let error { self?.errorMessage = "Spotify açılamadı: \(error.localizedDescription)" }
                self?.refreshRunningState()
            }
        }
    }

    private func refreshRunningState() {
        guard started else { return }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
        if !running {
            if isRunning { generation += 1 }
            isRunning = false
            isPlaying = false
            trackTitle = ""
            artist = ""
            artwork = nil
            artworkKey = ""
            artworkTask?.cancel()
            pollingTask?.cancel()
            pollingTask = nil
            pendingCommands.removeAll()
            return
        }
        isRunning = true
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.started, self.isRunning else { return }
                self.poll()
                let delay: UInt64 = self.panelVisible ? 1_000_000_000 : 5_000_000_000
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
            }
        }
    }

    private func poll() { execute(command: nil) }

    private func command(_ command: String) {
        guard isRunning else { return }
        guard isAuthorized else { requestAuthorization(); return }
        if inFlight {
            if pendingCommands.count < 3 { pendingCommands.append(command) }
        } else { execute(command: command) }
    }

    private func execute(command: String?) {
        guard started, isRunning, !inFlight else { return }
        inFlight = true
        let token = generation
        queue.async { [weak self] in
            let status = Self.permissionStatus(prompt: false)
            let snapshot: SpotifySnapshot
            if status != noErr {
                snapshot = SpotifySnapshot(error: status == -1744 ? nil : "Spotify bağlantı izni gerekli.", denied: true)
            } else {
                snapshot = Self.readSnapshot(command: command)
            }
            Task { @MainActor in
                guard let self else { return }
                self.inFlight = false
                guard self.started, self.generation == token, self.isRunning else { return }
                self.isAuthorized = !snapshot.denied
                self.errorMessage = snapshot.error
                if snapshot.error == nil && !snapshot.denied {
                    self.trackTitle = snapshot.title
                    self.artist = snapshot.artist
                    self.isPlaying = snapshot.playing
                    self.updateArtwork(snapshot.artworkURL, trackKey: snapshot.title + "\n" + snapshot.artist)
                } else {
                    self.isPlaying = false
                    self.artworkTask?.cancel()
                    self.artworkKey = ""
                    self.artwork = nil
                    self.trackTitle = ""
                    self.artist = ""
                }
                if !self.pendingCommands.isEmpty {
                    let next = self.pendingCommands.removeFirst()
                    self.execute(command: next)
                }
            }
        }
    }

    nonisolated private static func permissionStatus(prompt: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.spotify.client")
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, prompt)
    }

    nonisolated private static func code(_ value: String) -> FourCharCode {
        value.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    nonisolated private static func property(_ name: String, container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor? {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code("prop")), forKeyword: code("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code("prop")), forKeyword: code("form"))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(name)), forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        return record.coerce(toDescriptorType: code("obj "))
    }

    nonisolated private static func send(target: NSAppleEventDescriptor, eventClass: FourCharCode,
                                        eventID: FourCharCode, object: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID, targetDescriptor: target,
                                          returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let object { event.setParam(object, forKeyword: keyDirectObject) }
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 2)
        if let number = reply.paramDescriptor(forKeyword: keyErrorNumber), number.int32Value != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(number.int32Value))
        }
        return reply.paramDescriptor(forKeyword: keyDirectObject) ?? .null()
    }

    nonisolated private static func readSnapshot(command: String?) -> SpotifySnapshot {
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first,
              !process.isTerminated else { return SpotifySnapshot() }
        // Address the existing process, so Spotify quitting mid-request cannot launch it again.
        let target = NSAppleEventDescriptor(processIdentifier: process.processIdentifier)
        do {
            let commands = ["playpause": "PlPs", "previous track": "Prev", "next track": "Next"]
            if let command, let event = commands[command] {
                _ = try send(target: target, eventClass: code("spfy"), eventID: code(event))
            }
            func get(_ object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
                try send(target: target, eventClass: code("core"), eventID: code("getd"), object: object)
            }
            guard let stateProperty = property("pPlS"), let track = property("pTrk") else {
                return SpotifySnapshot(error: "Spotify yanıtı okunamadı. Yeniden denenecek.")
            }
            let state = try get(stateProperty).enumCodeValue
            guard state != code("kPSS") else { return SpotifySnapshot() }
            guard let titleProperty = property("pnam", container: track),
                  let artistProperty = property("pArt", container: track),
                  let artworkProperty = property("aUrl", container: track) else {
                return SpotifySnapshot(error: "Spotify yanıtı okunamadı. Yeniden denenecek.")
            }
            let title = try get(titleProperty).stringValue ?? ""
            let artist = try get(artistProperty).stringValue ?? ""
            let artwork = try get(artworkProperty).stringValue ?? ""
            return SpotifySnapshot(title: title, artist: artist, artworkURL: artwork, playing: state == code("kPSP"))
        } catch {
            let number = (error as NSError).code
            if number == -1743 { return SpotifySnapshot(error: "Spotify otomasyon izni kaldırıldı.", denied: true) }
            return SpotifySnapshot(error: number == -1712 ? "Spotify zamanında yanıt vermedi. Yeniden denenecek." : "Spotify şu anda yanıt vermiyor. Yeniden denenecek.")
        }
    }

    private func updateArtwork(_ value: String, trackKey: String) {
        let key = trackKey + "\n" + value
        guard key != artworkKey else { return }
        artworkKey = key
        artworkTask?.cancel()
        artwork = nil
        guard let url = URL(string: value), ArtworkRedirectPolicy.allows(url) else { return }
        if let cached = artworkCache.object(forKey: url as NSURL) { artwork = cached; return }
        artworkTask = Task { [weak self] in
            guard let data = await Self.fetchArtwork(url), !Task.isCancelled,
                  let self, self.artworkKey == key,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return }
            let image = NSImage(cgImage: thumbnail, size: .zero)
            self.artworkCache.setObject(image, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
            self.artwork = image
        }
    }

    nonisolated private static func fetchArtwork(_ url: URL) async -> Data? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: ArtworkRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.expectedContentLength <= 4 * 1_024 * 1_024,
                  response.mimeType?.hasPrefix("image/") == true else { return nil }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 4 * 1_024 * 1_024 else { return nil }
                data.append(byte)
            }
            return data
        } catch { return nil }
    }
}
