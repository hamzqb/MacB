import AppKit
import Combine

/// What the system says is playing — the same thing Control Center shows —
/// from any app: Spotify, Music, a YouTube tab in Chrome or Safari, a podcast.
///
/// macOS 15.4 stopped answering ordinary apps' Now Playing questions, so
/// MacB asks through `/usr/bin/perl`, which the system still answers: perl
/// loads MacB's small `nowplaying.dylib` and streams a JSON line whenever
/// playback changes, and takes transport commands on stdin. Nothing is
/// downloaded or installed; perl ships with macOS. When it cannot run, the
/// per-app readers (Spotify, Music, browser scripting) still work.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var bundleID: String?
    /// True once the helper has answered at least once.
    @Published private(set) var isAvailable = false

    /// Elapsed time at `elapsedDate`, advancing at `rate` while playing.
    private var elapsed: Double = 0
    private var elapsedDate = Date()
    private var rate: Double = 0

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var restarts = 0
    private var started = false

    var position: Double {
        guard isPlaying, rate > 0 else { return elapsed }
        let now = elapsed + Date().timeIntervalSince(elapsedDate) * rate
        return duration > 0 ? min(duration, now) : now
    }

    /// The playing app's name, for "Google Chrome" under a video title.
    var appName: String? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var appIcon: NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func start() {
        guard !started else { return }
        started = true
        launch()
    }

    func stop() {
        started = false
        try? input?.close()
        process?.terminate()
        process = nil
        input = nil
    }

    func togglePlayPause() { send("toggle") }
    func nextTrack() { send("next") }
    func previousTrack() { send("previous") }
    func seek(to seconds: Double) {
        elapsed = max(0, seconds); elapsedDate = Date()
        send("seek \(max(0, seconds))")
    }

    private func send(_ command: String) {
        guard let input, let data = (command + "\n").data(using: .utf8) else { return }
        try? input.write(contentsOf: data)
    }

    private static var helperPath: String? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/nowplaying.dylib").path
        return FileManager.default.fileExists(atPath: bundled) ? bundled : nil
    }

    private static let loader = """
    use DynaLoader;
    my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or exit 4;
    my $sym = DynaLoader::dl_find_symbol($lib, "macb_nowplaying_stream") or exit 5;
    DynaLoader::dl_install_xsub("main::stream", $sym);
    &stream;
    """

    private func launch() {
        guard started, let helper = Self.helperPath,
              FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.loader, helper]
        let output = Pipe(), input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            Task { @MainActor in self?.receive(chunk) }
        }
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in self?.relaunchAfterExit() }
        }
        do {
            try process.run()
            self.process = process
            self.input = input.fileHandleForWriting
        } catch {
            self.process = nil
        }
    }

    /// A crash or a sleep can end the helper; it comes back, slower each
    /// time, and stops trying after a handful of quick failures.
    private func relaunchAfterExit() {
        process = nil; input = nil
        guard started, restarts < 6 else { return }
        restarts += 1
        let delay = min(30, pow(2, Double(restarts)))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.launch() }
    }

    private func receive(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            apply(line)
        }
    }

    private func apply(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        isAvailable = true
        restarts = 0
        let newTitle = (object["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if newTitle != title { title = newTitle }
        let newArtist = object["artist"] as? String ?? ""
        if newArtist != artist { artist = newArtist }
        album = object["album"] as? String ?? ""
        duration = object["duration"] as? Double ?? 0
        rate = object["rate"] as? Double ?? 0
        let playing = (object["playing"] as? Bool ?? false) || rate > 0
        if playing != isPlaying { isPlaying = playing }
        let bundle = object["bundle"] as? String
        if bundle != bundleID { bundleID = bundle }
        // The elapsed time is a reading taken at `timestamp`.
        let reading = object["elapsed"] as? Double ?? 0
        if let stamp = object["timestamp"] as? Double {
            let takenAt = Date(timeIntervalSince1970: stamp)
            elapsed = reading
            elapsedDate = min(Date(), takenAt)
        } else {
            elapsed = reading; elapsedDate = Date()
        }
        if let encoded = object["artwork"] as? String,
           let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
            artwork = image
        } else if (object["artworkHash"] as? String ?? "").isEmpty, artwork != nil {
            artwork = nil
        }
        objectWillChange.send()
    }
}
