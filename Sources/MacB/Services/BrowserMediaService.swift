import AppKit
import Carbon
import Combine
import MacBCore

private enum BrowserScriptKind: Sendable { case chromium, safari }

private struct ScriptableBrowser: Sendable {
    let bundleID: String
    let name: String
    let kind: BrowserScriptKind
}

private struct BrowserTarget: Sendable {
    let browser: ScriptableBrowser
    let windowIndex: Int
    let tabIndex: Int
}

private struct BrowserSnapshot: Sendable {
    var probe: BrowserMediaProbe?
    var target: BrowserTarget?
    var authorized = false
    var setupMessage: String?
}

@MainActor
final class BrowserMediaService: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var sourceName = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var isRunning = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var errorMessage: String?

    private let queue = DispatchQueue(label: "MacB.BrowserMedia", qos: .utility)
    private var pollingTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var currentTarget: BrowserTarget?
    private var panelVisible = false
    private var started = false
    private var inFlight = false
    private var generation = 0
    private var lastFullScanAt = Date.distantPast

    private static let supportedBrowsers = [
        ScriptableBrowser(bundleID: "com.apple.Safari", name: "Safari", kind: .safari),
        ScriptableBrowser(bundleID: "com.google.Chrome", name: "Google Chrome", kind: .chromium),
        ScriptableBrowser(bundleID: "com.google.Chrome.beta", name: "Google Chrome Beta", kind: .chromium),
        ScriptableBrowser(bundleID: "com.google.Chrome.dev", name: "Google Chrome Dev", kind: .chromium),
        ScriptableBrowser(bundleID: "com.brave.Browser", name: "Brave Browser", kind: .chromium),
        ScriptableBrowser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", kind: .chromium),
        ScriptableBrowser(bundleID: "company.thebrowser.Browser", name: "Arc", kind: .chromium)
    ]

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.restartPolling(forceFullScan: true) }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pollingTask?.cancel(); self?.pollingTask = nil }
        })
        restartPolling(forceFullScan: true)
    }

    func stop() {
        started = false
        generation += 1
        inFlight = false
        pollingTask?.cancel(); pollingTask = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        clear(resetRunningState: true)
    }

    func setPanelVisible(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        restartPolling(forceFullScan: visible)
    }

    func requestAuthorization() {
        let browsers = runningBrowsers()
        guard !browsers.isEmpty, !inFlight else {
            if browsers.isEmpty { errorMessage = "Önce Safari veya desteklenen bir Chromium tarayıcısını açın." }
            return
        }
        inFlight = true
        let token = generation
        queue.async { [weak self] in
            for browser in browsers { _ = Self.permissionStatus(for: browser, prompt: true) }
            let snapshot = Self.readSnapshot(from: browsers, preferredTarget: nil, allowFullScan: true)
            Task { @MainActor in
                guard let self, self.started, self.generation == token else { return }
                self.inFlight = false
                self.apply(snapshot)
            }
        }
    }

    func playPause() {
        guard let target = currentTarget else { return }
        queue.async { [weak self] in
            let script = Self.commandScript(for: target, javascript: Self.pauseJavaScript)
            var error: NSDictionary?
            _ = NSAppleScript(source: script)?.executeAndReturnError(&error)
            Task { @MainActor in self?.poll() }
        }
    }

    func previousTrack() { sendMediaKey(NX_KEYTYPE_PREVIOUS) }
    func nextTrack() { sendMediaKey(NX_KEYTYPE_NEXT) }

    private func restartPolling(forceFullScan: Bool = false) {
        pollingTask?.cancel(); pollingTask = nil
        guard started else { return }
        if forceFullScan { lastFullScanAt = .distantPast }
        let browsers = runningBrowsers()
        isRunning = !browsers.isEmpty
        if browsers.isEmpty { clear(resetRunningState: true); return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.started else { return }
                self.poll()
                let delay: UInt64 = self.panelVisible && self.isPlaying ? 1_500_000_000 : 10_000_000_000
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
            }
        }
    }

    private func poll() {
        guard started, !inFlight else { return }
        var browsers = runningBrowsers()
        guard !browsers.isEmpty else { clear(resetRunningState: true); return }
        if let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           let index = browsers.firstIndex(where: { $0.bundleID == frontmostID }) {
            browsers.insert(browsers.remove(at: index), at: 0)
        }
        isRunning = true
        inFlight = true
        let token = generation
        let preferredTarget = currentTarget
        let fullScanInterval: TimeInterval = panelVisible ? 3 : 15
        let allowFullScan = Date().timeIntervalSince(lastFullScanAt) >= fullScanInterval
        if allowFullScan { lastFullScanAt = Date() }
        queue.async { [weak self] in
            let snapshot = Self.readSnapshot(from: browsers, preferredTarget: preferredTarget, allowFullScan: allowFullScan)
            Task { @MainActor in
                guard let self else { return }
                self.inFlight = false
                guard self.started, self.generation == token else { return }
                self.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: BrowserSnapshot) {
        isAuthorized = snapshot.authorized
        errorMessage = snapshot.setupMessage
        guard let probe = snapshot.probe, probe.isPlaying else {
            title = ""; sourceName = ""; isPlaying = false
            return
        }
        title = probe.title
        sourceName = probe.artist.isEmpty ? (snapshot.target?.browser.name ?? "Tarayıcı") : probe.artist
        isPlaying = true
        currentTarget = snapshot.target
    }

    private func clear(resetRunningState: Bool) {
        title = ""; sourceName = ""; isPlaying = false; currentTarget = nil
        if resetRunningState { isRunning = false; isAuthorized = false; errorMessage = nil }
    }

    private func runningBrowsers() -> [ScriptableBrowser] {
        Self.supportedBrowsers.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
    }

    nonisolated private static func permissionStatus(for browser: ScriptableBrowser, prompt: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: browser.bundleID)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, prompt)
    }

    nonisolated private static func readSnapshot(
        from browsers: [ScriptableBrowser],
        preferredTarget: BrowserTarget?,
        allowFullScan: Bool
    ) -> BrowserSnapshot {
        var authorized = false
        var setupMessage: String?
        if let target = preferredTarget,
           browsers.contains(where: { $0.bundleID == target.browser.bundleID }),
           permissionStatus(for: target.browser, prompt: false) == noErr {
            authorized = true
            var error: NSDictionary?
            let result = NSAppleScript(source: commandScript(for: target, javascript: probeJavaScript))?
                .executeAndReturnError(&error).stringValue ?? ""
            if let probe = BrowserMediaProbe.decode(result), probe.isPlaying {
                return BrowserSnapshot(probe: probe, target: target, authorized: true)
            }
        }
        guard allowFullScan else { return BrowserSnapshot(authorized: authorized) }
        for browser in browsers {
            guard permissionStatus(for: browser, prompt: false) == noErr else { continue }
            authorized = true
            var error: NSDictionary?
            let result = NSAppleScript(source: probeScript(for: browser))?.executeAndReturnError(&error).stringValue ?? ""
            if !result.isEmpty, let decoded = decode(result, browser: browser) { return decoded }
            if let number = error?[NSAppleScript.errorNumber] as? Int, [-10000, -1708].contains(number) {
                setupMessage = browser.kind == .safari
                    ? "Safari → Ayarlar → Geliştirici bölümünde Apple Events’ten JavaScript’e izin verin."
                    : "Tarayıcının Geliştirici menüsünde Apple Events’ten JavaScript’e izin verin."
            }
        }
        return BrowserSnapshot(authorized: authorized, setupMessage: setupMessage)
    }

    nonisolated private static func decode(_ result: String, browser: ScriptableBrowser) -> BrowserSnapshot? {
        let parts = result.components(separatedBy: String(UnicodeScalar(30)))
        guard parts.count == 3, let windowIndex = Int(parts[0]), let tabIndex = Int(parts[1]),
              let probe = BrowserMediaProbe.decode(parts[2]), probe.isPlaying else { return nil }
        let target = BrowserTarget(browser: browser, windowIndex: windowIndex, tabIndex: tabIndex)
        return BrowserSnapshot(probe: probe, target: target, authorized: true)
    }

    nonisolated private static func probeScript(for browser: ScriptableBrowser) -> String {
        let javascript = appleScriptString(probeJavaScript)
        let execution: String
        switch browser.kind {
        case .chromium: execution = "execute tab t of window w javascript \(javascript)"
        case .safari: execution = "do JavaScript \(javascript) in tab t of window w"
        }
        return """
        with timeout of 3 seconds
            tell application id "\(browser.bundleID)"
                repeat with w from 1 to (count of windows)
                    repeat with t from 1 to (count of tabs of window w)
                        try
                            set probeResult to \(execution)
                            if probeResult is not "" then return (w as text) & (ASCII character 30) & (t as text) & (ASCII character 30) & probeResult
                        end try
                    end repeat
                end repeat
            end tell
        end timeout
        return ""
        """
    }

    nonisolated private static func commandScript(for target: BrowserTarget, javascript: String) -> String {
        let source = appleScriptString(javascript)
        let execution: String
        switch target.browser.kind {
        case .chromium: execution = "execute tab \(target.tabIndex) of window \(target.windowIndex) javascript \(source)"
        case .safari: execution = "do JavaScript \(source) in tab \(target.tabIndex) of window \(target.windowIndex)"
        }
        return "with timeout of 2 seconds\n tell application id \"\(target.browser.bundleID)\" to \(execution)\nend timeout"
    }

    nonisolated private static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    nonisolated private static let probeJavaScript = """
    (()=>{const a=[...document.querySelectorAll('video,audio')].filter(e=>!e.paused&&!e.ended&&!e.muted&&e.volume>0&&e.readyState>=2);if(!a.length)return '';const e=a.sort((x,y)=>(y.currentTime||0)-(x.currentTime||0))[0],m=navigator.mediaSession&&navigator.mediaSession.metadata,t=(m&&m.title)||document.title||location.hostname,r=(m&&m.artist)||location.hostname;return JSON.stringify({title:t,artist:r,isPlaying:true,currentTime:Number.isFinite(e.currentTime)?e.currentTime:0,duration:Number.isFinite(e.duration)?e.duration:0})})()
    """

    nonisolated private static let pauseJavaScript = """
    (()=>{for(const e of document.querySelectorAll('video,audio'))if(!e.paused&&!e.ended)e.pause();return 'ok'})()
    """

    private func sendMediaKey(_ key: Int32) {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(NX_KEYTYPE_PLAY))
        let keyDown = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                         timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                         data1: (Int(key) << 16) | (0xA << 8), data2: -1)
        let keyUp = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                       timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                       data1: (Int(key) << 16) | (0xB << 8), data2: -1)
        keyDown?.cgEvent?.post(tap: .cghidEventTap)
        keyUp?.cgEvent?.post(tap: .cghidEventTap)
    }
}
