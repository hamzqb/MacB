import AppKit
import Combine

private struct BrowserCandidate {
    let appName: String
    let title: String
    let score: Int
}

@MainActor
final class BrowserMediaService: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var sourceName = ""
    @Published private(set) var isPlaying = false

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let browserNames = ["Safari", "Google Chrome", "Chrome", "Arc", "Brave Browser", "Microsoft Edge", "Firefox"]

    func start() {
        guard timer == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        title = ""; sourceName = ""; isPlaying = false
    }

    func refresh() {
        let runningBrowsers = Set(NSWorkspace.shared.runningApplications.compactMap { app -> String? in
            guard app.activationPolicy == .regular, let name = app.localizedName, browserNames.contains(name) else { return nil }
            return name
        })
        guard !runningBrowsers.isEmpty,
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            clear()
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName
        let candidates = windowList.compactMap { info -> BrowserCandidate? in
            guard let appName = info[kCGWindowOwnerName as String] as? String,
                  runningBrowsers.contains(appName),
                  let rawTitle = info[kCGWindowName as String] as? String,
                  !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            guard let score = score(title: rawTitle, appName: appName, frontmost: frontmost) else { return nil }
            return BrowserCandidate(appName: appName, title: cleanTitle(rawTitle), score: score)
        }
        guard let best = candidates.sorted(by: { $0.score > $1.score }).first else {
            clear()
            return
        }
        title = best.title
        sourceName = best.appName
        isPlaying = true
    }

    func playPause() { sendMediaKey(16) }
    func previousTrack() { sendMediaKey(18) }
    func nextTrack() { sendMediaKey(17) }

    private func clear() {
        title = ""; sourceName = ""; isPlaying = false
    }

    private func score(title: String, appName: String, frontmost: String?) -> Int? {
        let lower = title.lowercased()
        let strong = ["youtube music", "youtube", "spotify", "netflix", "twitch", "soundcloud", "vimeo", "prime video", "disney+", "hulu"]
        let medium = ["playing", "now playing", "watch", "listen"]
        var value = appName == frontmost ? 10 : 0
        if strong.contains(where: lower.contains) { value += 80 }
        if medium.contains(where: lower.contains) { value += 35 }
        if lower.contains(" - ") || lower.contains(" – ") || lower.contains(" — ") { value += 10 }
        return value >= 45 ? value : nil
    }

    private func cleanTitle(_ title: String) -> String {
        var value = title
        let suffixes = [" - YouTube", " — YouTube", " - YouTube Music", " | YouTube Music", " - Google Chrome", " - Safari", " - Brave Browser", " - Microsoft Edge"]
        for suffix in suffixes where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendMediaKey(_ key: Int) {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(NX_KEYTYPE_PLAY))
        let keyDown = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                         timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                         data1: (key << 16) | (0xA << 8), data2: -1)
        let keyUp = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                       timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                       data1: (key << 16) | (0xB << 8), data2: -1)
        keyDown?.cgEvent?.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp?.cgEvent?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
