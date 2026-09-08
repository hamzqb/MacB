import AppKit
import ApplicationServices
import Combine

@MainActor final class PermissionStore: ObservableObject {
    @Published private(set) var accessibility = false
    @Published private(set) var screenCapture = false
    private var timer: Timer?

    init() { refresh() }
    func refresh() {
        accessibility = AXIsProcessTrusted()
        screenCapture = CGPreflightScreenCaptureAccess()
    }
    func startObserving() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 1
    }
    func stopObserving() { timer?.invalidate(); timer = nil }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
    }
    func requestScreenCapture() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
        if !screenCapture { openPrivacy("Privacy_ScreenCapture") }
    }
    func openPrivacy(_ section: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") else { return }
        NSWorkspace.shared.open(url)
    }
}
