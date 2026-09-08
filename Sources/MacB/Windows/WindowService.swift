import AppKit
import ApplicationServices
import Combine

struct WindowRecord: Identifiable {
    let id: String
    let title: String
    let appName: String
    let appIcon: NSImage?
    let pid: pid_t
    let element: AXUIElement
    let frame: CGRect
    let isMinimized: Bool
    let canClose: Bool
    let canMinimize: Bool
    var captureAmbiguous: Bool = false
}

func axAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let position = axAttribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
          let size = axAttribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero; var dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
    return CGRect(origin: point, size: dimensions)
}

@MainActor final class WindowService: ObservableObject {
    @Published private(set) var windows: [WindowRecord] = []
    @Published var errorMessage: String?
    private let queue = DispatchQueue(label: "com.macb.windows", qos: .userInitiated)
    private var refreshGeneration = 0
    private var identities: [pid_t: [(AXUIElement, String)]] = [:]

    func refresh(pid: pid_t? = nil) async {
        guard AXIsProcessTrusted() else {
            windows = []; errorMessage = "Pencereler için Erişilebilirlik iznini açın."; return
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && (pid == nil || $0.processIdentifier == pid)
        }
        let discovered: [WindowRecord] = await withCheckedContinuation { continuation in
            queue.async {
                var result: [WindowRecord] = []
                for app in apps {
                    let application = AXUIElementCreateApplication(app.processIdentifier)
                    AXUIElementSetMessagingTimeout(application, 0.2)
                    guard let elements = axAttribute(application, kAXWindowsAttribute) as? [AXUIElement] else { continue }
                    for element in elements {
                        AXUIElementSetMessagingTimeout(element, 0.15)
                        guard (axAttribute(element, kAXRoleAttribute) as? String) == kAXWindowRole else { continue }
                        let title = axAttribute(element, kAXTitleAttribute) as? String ?? ""
                        let frame = axFrame(element) ?? .zero
                        let minimized = axAttribute(element, kAXMinimizedAttribute) as? Bool ?? false
                        var settable: DarwinBoolean = false
                        let minimize = AXUIElementIsAttributeSettable(element, kAXMinimizedAttribute as CFString, &settable) == .success && settable.boolValue
                        let close = axAttribute(element, kAXCloseButtonAttribute) != nil
                        result.append(WindowRecord(id: "", title: title.isEmpty ? (app.localizedName ?? "Pencere") : title,
                            appName: app.localizedName ?? "Uygulama", appIcon: app.icon, pid: app.processIdentifier,
                            element: element, frame: frame, isMinimized: minimized, canClose: close, canMinimize: minimize))
                    }
                }
                continuation.resume(returning: result)
            }
        }
        guard generation == refreshGeneration else { return }
        let records = discovered.map { record -> WindowRecord in
            let previous = identities[record.pid]?.first { CFEqual($0.0, record.element) }?.1
            let id = previous ?? UUID().uuidString
            var identified = WindowRecord(id: id, title: record.title, appName: record.appName, appIcon: record.appIcon, pid: record.pid,
                element: record.element, frame: record.frame, isMinimized: record.isMinimized, canClose: record.canClose, canMinimize: record.canMinimize)
            identified.captureAmbiguous = discovered.filter { peer in
                peer.pid == record.pid && abs(peer.frame.minX - record.frame.minX) <= 2 &&
                abs(peer.frame.minY - record.frame.minY) <= 2 && abs(peer.frame.width - record.frame.width) <= 2 &&
                abs(peer.frame.height - record.frame.height) <= 2
            }.count > 1
            return identified
        }
        if let pid {
            windows.removeAll { $0.pid == pid }; windows.append(contentsOf: records)
            identities[pid] = records.map { ($0.element, $0.id) }
        } else {
            windows = records
            identities = Dictionary(grouping: records, by: \.pid).mapValues { $0.map { ($0.element, $0.id) } }
        }
        errorMessage = nil
    }

    func focus(_ window: WindowRecord, focusMode: Bool = false) { perform(window, action: .focus(focusMode)) }
    func minimize(_ window: WindowRecord) { guard window.canMinimize else { return }; perform(window, action: .minimize) }
    func close(_ window: WindowRecord) { guard window.canClose else { return }; perform(window, action: .close) }

    private enum Action { case focus(Bool), minimize, close }
    private func perform(_ window: WindowRecord, action: Action) {
        guard AXIsProcessTrusted() else { errorMessage = "Erişilebilirlik izni gerekli."; return }
        queue.async { [weak self] in
            var result: AXError = .success
            switch action {
            case .focus:
                if window.isMinimized { result = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
                if result == .success { result = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) }
                if result == .success {
                    _ = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
                }
            case .minimize:
                result = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, window.isMinimized ? kCFBooleanFalse : kCFBooleanTrue)
            case .close:
                if let button = axAttribute(window.element, kAXCloseButtonAttribute), CFGetTypeID(button) == AXUIElementGetTypeID() {
                    result = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
                } else { result = .invalidUIElement }
            }
            Task { @MainActor in
                guard let self else { return }
                if case .focus(let focusMode) = action, result == .success {
                    NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
                    if focusMode { self.hideOtherApplications(keeping: window.pid) }
                }
                await self.refresh(pid: window.pid)
                if result != .success { self.errorMessage = "Pencere değişmiş veya bu işlemi desteklemiyor. Yeniden deneyin." }
            }
        }
    }

    private func hideOtherApplications(keeping pid: pid_t) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != pid && $0.processIdentifier != ownPID && !$0.isHidden }
            .forEach { $0.hide() }
    }
}
