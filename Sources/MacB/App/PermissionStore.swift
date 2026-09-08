import AppKit
import ApplicationServices
import Combine

@MainActor final class PermissionStore: ObservableObject {
    @Published private(set) var accessibility = false
    @Published private(set) var screenCapture = false
    @Published private(set) var inputMonitoring = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?

    init() { refresh() }
    func refresh() {
        accessibility = AXIsProcessTrusted()
        screenCapture = CGPreflightScreenCaptureAccess()
        inputMonitoring = CGPreflightListenEventAccess()
    }
    func startObserving() {
        refresh()
        guard timer == nil, observers.isEmpty else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.35
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAfterSystemSettings() }
        })
    }
    func stopObserving() {
        timer?.invalidate(); timer = nil
        refreshTask?.cancel(); refreshTask = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
        refreshAfterSystemSettings()
    }
    func requestScreenCapture() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
        if !screenCapture { openPrivacy("Privacy_ScreenCapture") }
        refreshAfterSystemSettings()
    }
    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        refresh()
        if !inputMonitoring { openPrivacy("Privacy_ListenEvent") }
        refreshAfterSystemSettings()
    }
    func openPrivacy(_ section: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshAfterSystemSettings() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            for delay in [0.25, 1.0, 2.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }
}
