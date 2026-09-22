import AppKit
import ApplicationServices
import Combine

/// Quits selected applications when their last user-facing window disappears.
///
/// The service is deliberately conservative: it only watches bundle identifiers
/// the user picked, it never force-quits, and it does not touch system apps that
/// would make the desktop feel broken if they vanished.
@MainActor final class AutoQuitOnCloseService: ObservableObject {
    struct App: Identifiable, Hashable {
        let bundleIdentifier: String
        let name: String
        let icon: NSImage?
        var id: String { bundleIdentifier }
    }

    @Published private(set) var trackedApps: [App] = []
    @Published private(set) var lastMessage: String?

    private let preferences: Preferences
    private var timer: Timer?
    private var previousWindowCounts: [String: Int] = [:]
    /// Apps seen with no window once; a second empty sample quits them.
    private var emptySamples: [String: Int] = [:]
    private let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        Bundle.main.bundleIdentifier ?? "dev.hamzababal.MacB"
    ]

    init(preferences: Preferences) {
        self.preferences = preferences
        refreshTrackedApps()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled, preferences.quitAppsWhenLastWindowCloses, !preferences.quitOnCloseBundleIDs.isEmpty else {
            timer?.invalidate()
            timer = nil
            previousWindowCounts.removeAll()
            emptySamples.removeAll()
            refreshTrackedApps()
            return
        }
        refreshTrackedApps()
        sample(terminateIfClosed: false)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample(terminateIfClosed: true) }
        }
    }

    /// Running apps that could go on the list. Picked from a menu: a button
    /// for "the front app" always found MacB in front, because the button is
    /// in MacB's own window.
    var candidates: [App] {
        let listed = Set(preferences.quitOnCloseBundleIDs)
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application -> App? in
                guard let identifier = application.bundleIdentifier, !protectedBundleIDs.contains(identifier),
                      !listed.contains(identifier), seen.insert(identifier).inserted else { return nil }
                return App(bundleIdentifier: identifier, name: application.localizedName ?? displayName(for: identifier),
                           icon: application.icon)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func add(bundleIdentifier: String, name: String? = nil) {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard !protectedBundleIDs.contains(normalized) else {
            lastMessage = "Bu uygulamayı otomatik kapatma listesine almıyorum."
            return
        }
        guard !preferences.quitOnCloseBundleIDs.contains(normalized) else {
            lastMessage = "Zaten listede."
            return
        }
        preferences.quitOnCloseBundleIDs.append(normalized)
        refreshTrackedApps()
        lastMessage = "\(name ?? displayName(for: normalized)) listeye eklendi."
        setEnabled(true)
    }

    func remove(_ app: App) {
        preferences.quitOnCloseBundleIDs.removeAll { $0 == app.bundleIdentifier }
        previousWindowCounts.removeValue(forKey: app.bundleIdentifier)
        emptySamples.removeValue(forKey: app.bundleIdentifier)
        refreshTrackedApps()
        lastMessage = "\(app.name) listeden çıkarıldı."
        setEnabled(true)
    }

    func refreshTrackedApps() {
        trackedApps = preferences.quitOnCloseBundleIDs
            .filter { !protectedBundleIDs.contains($0) }
            .map { identifier in
                let running = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == identifier }
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
                let icon = running?.icon ?? url.map { NSWorkspace.shared.icon(forFile: $0.path) }
                let name = running?.localizedName ?? url?.deletingPathExtension().lastPathComponent ?? identifier
                return App(bundleIdentifier: identifier, name: name, icon: icon)
            }
    }

    /// Quits an app only on clear evidence that its last window is gone:
    /// - Accessibility answered, with no window. An app too busy to answer
    ///   (a beachball, a modal save sheet) is unknown, not empty — reading
    ///   that as "no windows" quit apps in the middle of work.
    /// - The window server agrees. Accessibility lists only the current
    ///   Space's windows for many apps, so moving to another desktop or into
    ///   a full-screen app made every window elsewhere look closed.
    /// - It stayed that way for two samples in a row, so an app swapping one
    ///   window for another (a document closing as the next one opens) is
    ///   not caught in between.
    private func sample(terminateIfClosed: Bool) {
        guard AXIsProcessTrusted() else {
            lastMessage = "Otomatik kapatma için Erişilebilirlik izni gerekiyor."
            return
        }
        let identifiers = Set(preferences.quitOnCloseBundleIDs).subtracting(protectedBundleIDs)
        guard !identifiers.isEmpty else { return }
        let serverWindows = Self.windowServerCounts()
        for application in NSWorkspace.shared.runningApplications where application.activationPolicy == .regular {
            guard let identifier = application.bundleIdentifier, identifiers.contains(identifier) else { continue }
            guard let accessible = windowCount(for: application) else { continue }
            let count = max(accessible, serverWindows[application.processIdentifier] ?? 0)
            let previous = previousWindowCounts[identifier]
            previousWindowCounts[identifier] = count
            if count > 0 { emptySamples[identifier] = nil; continue }
            guard let previous else { continue }
            if previous > 0 { emptySamples[identifier] = 1; continue }
            guard terminateIfClosed, emptySamples[identifier] == 1 else { continue }
            emptySamples[identifier] = nil
            if application.terminate() {
                lastMessage = "\(application.localizedName ?? displayName(for: identifier)) kapatıldı."
            }
        }
    }

    /// Ordinary windows per process on every Space, minimised ones included,
    /// as the window server sees them.
    private static func windowServerCounts() -> [pid_t: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [:] }
        var counts: [pid_t: Int] = [:]
        for window in list {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) >= 80, (bounds["Height"] ?? 0) >= 60,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            counts[pid, default: 0] += 1
        }
        return counts
    }

    /// Nil when the app did not answer.
    private func windowCount(for application: NSRunningApplication) -> Int? {
        let element = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.18)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.filter { window in
            AXUIElementSetMessagingTimeout(window, 0.12)
            guard (axAttribute(window, kAXRoleAttribute) as? String) == kAXWindowRole else { return false }
            if (axAttribute(window, kAXMinimizedAttribute) as? Bool) == true { return true }
            let frame = axFrame(window) ?? .zero
            return frame.width >= 80 && frame.height >= 60
        }.count
    }

    private func displayName(for bundleIdentifier: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)?
            .deletingPathExtension().lastPathComponent ?? bundleIdentifier
    }
}
