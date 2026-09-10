import AppKit
import Combine

private struct AppleMusicSnapshot {
    var title = ""
    var artist = ""
    var playing = false
    var error: String?
    var denied = false
}

@MainActor
final class AppleMusicService: ObservableObject {
    @Published var trackTitle = ""
    @Published var artist = ""
    @Published var isPlaying = false
    @Published var isRunning = false
    @Published var isAuthorized = false
    @Published var errorMessage: String?

    private let queue = DispatchQueue(label: "MacB.AppleMusic", qos: .utility)
    private var observers: [NSObjectProtocol] = []
    private var pollingTask: Task<Void, Never>?
    private var panelVisible = false
    private var started = false
    private var inFlight = false
    private var pendingCommands: [String] = []
    private var generation = 0

    func start() {
        guard !started else { return }
        started = true
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
        pollingTask?.cancel(); pollingTask = nil
        pendingCommands.removeAll()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    func setPanelVisible(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        pollingTask?.cancel(); pollingTask = nil
        refreshRunningState()
    }

    func requestAuthorization() {
        guard isRunning, !inFlight else {
            if !isRunning { errorMessage = "Önce Apple Music’i açın, ardından bağlantıya izin verin." }
            return
        }
        execute(command: nil, prompt: true)
    }

    func playPause() { command("playpause") }
    func previousTrack() { command("previous track") }
    func nextTrack() { command("next track") }

    func openAppleMusic() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            errorMessage = "Apple Music bulunamadı."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor [weak self] in
                if let error { self?.errorMessage = "Apple Music açılamadı: \(error.localizedDescription)" }
                self?.refreshRunningState()
            }
        }
    }

    private func refreshRunningState() {
        guard started else { return }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
        if !running {
            if isRunning { generation += 1 }
            isRunning = false
            isPlaying = false
            trackTitle = ""
            artist = ""
            pollingTask?.cancel(); pollingTask = nil
            pendingCommands.removeAll()
            return
        }
        isRunning = true
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.started, self.isRunning else { return }
                self.execute(command: nil, prompt: false)
                let delay: UInt64 = self.panelVisible ? 1_000_000_000 : 5_000_000_000
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
            }
        }
    }

    private func command(_ command: String) {
        guard isRunning else { return }
        guard isAuthorized else { requestAuthorization(); return }
        if inFlight {
            if pendingCommands.count < 3 { pendingCommands.append(command) }
        } else { execute(command: command, prompt: false) }
    }

    private func execute(command: String?, prompt: Bool) {
        guard started, isRunning, !inFlight else { return }
        inFlight = true
        let token = generation
        queue.async { [weak self] in
            let status = Self.permissionStatus(prompt: prompt)
            let snapshot: AppleMusicSnapshot
            if status != noErr {
                snapshot = AppleMusicSnapshot(error: status == -1744 ? nil : "Apple Music bağlantı izni gerekli.", denied: true)
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
                } else {
                    self.isPlaying = false
                    self.trackTitle = ""
                    self.artist = ""
                }
                if !self.pendingCommands.isEmpty {
                    let next = self.pendingCommands.removeFirst()
                    self.execute(command: next, prompt: false)
                }
            }
        }
    }

    nonisolated private static func permissionStatus(prompt: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Music")
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, prompt)
    }

    nonisolated private static func readSnapshot(command: String?) -> AppleMusicSnapshot {
        let commandLine: String
        if let command {
            commandLine = "\(command)\n"
        } else {
            commandLine = ""
        }
        let source = """
        with timeout of 2 seconds
            tell application id "com.apple.Music"
                \(commandLine)set stateText to player state as text
                if stateText is "stopped" then
                    return "|||stopped"
                end if
                set trackName to name of current track
                set artistName to artist of current track
                return trackName & "|" & artistName & "|" & stateText
            end tell
        end timeout
        """
        var errorInfo: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo).stringValue else {
            let number = (errorInfo?[NSAppleScript.errorNumber] as? Int) ?? 0
            if number == -1743 { return AppleMusicSnapshot(error: "Apple Music otomasyon izni kaldırıldı.", denied: true) }
            return AppleMusicSnapshot(error: "Apple Music şu anda yanıt vermiyor. Yeniden denenecek.")
        }
        let parts = result.components(separatedBy: "|")
        guard parts.count >= 3 else { return AppleMusicSnapshot() }
        return AppleMusicSnapshot(title: parts[0], artist: parts[1], playing: parts[2] == "playing")
    }
}
