import AppKit
import ApplicationServices
import Combine
import MacBCore
import ScreenCaptureKit

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
    var bundleIdentifier: String? = nil
    var isMain: Bool = false
    var isFocused: Bool = false
    var captureAmbiguous: Bool = false
    var desktopLocation: WindowDesktopLocation = .unknown
    var isApplicationHidden: Bool = false
    var windowID: UInt32? = nil
    var desktopIndex: Int? = nil
    var isRemoteDesktopWindow = false

    var desktopName: String? { desktopIndex.map { "Masaüstü \($0)" } }
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
    private var refreshInProgress = false
    private var activeRefreshPID: pid_t?

    func refresh(pid: pid_t? = nil) async {
        guard AXIsProcessTrusted() else {
            windows = []; errorMessage = "Pencereler için Erişilebilirlik iznini açın."; return
        }
        if refreshInProgress {
            let activePID = activeRefreshPID
            while refreshInProgress {
                do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            }
            // A full scan satisfies every scoped request; an identical scoped scan
            // also makes another AX traversal unnecessary.
            if activePID == nil || activePID == pid { return }
        }
        refreshInProgress = true
        activeRefreshPID = pid
        defer { refreshInProgress = false; activeRefreshPID = nil }
        refreshGeneration += 1
        let generation = refreshGeneration
        let desktopSnapshot = await Self.desktopSnapshot()
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
                        let isMain = axAttribute(element, kAXMainAttribute) as? Bool ?? false
                        let isFocused = axAttribute(element, kAXFocusedAttribute) as? Bool ?? false
                        var settable: DarwinBoolean = false
                        let minimize = AXUIElementIsAttributeSettable(element, kAXMinimizedAttribute as CFString, &settable) == .success && settable.boolValue
                        let close = axAttribute(element, kAXCloseButtonAttribute) != nil
                        var record = WindowRecord(id: "", title: title.isEmpty ? (app.localizedName ?? "Pencere") : title,
                            appName: app.localizedName ?? "Uygulama", appIcon: app.icon, pid: app.processIdentifier,
                            element: element, frame: frame, isMinimized: minimized, canClose: close, canMinimize: minimize)
                        record.bundleIdentifier = app.bundleIdentifier
                        record.isMain = isMain
                        record.isFocused = isFocused
                        record.isApplicationHidden = app.isHidden
                        result.append(record)
                    }
                }
                continuation.resume(returning: result)
            }
        }
        guard generation == refreshGeneration else { return }
        var unique: [WindowRecord] = []
        for record in discovered where !unique.contains(where: { $0.pid == record.pid && CFEqual($0.element, record.element) }) {
            unique.append(record)
        }
        let byProcess = Dictionary(grouping: unique, by: \.pid)
        let userFacing = unique.filter { record in
            let peers = (byProcess[record.pid] ?? []).map {
                WindowVisibilityCandidate(title: $0.title, bundleIdentifier: $0.bundleIdentifier,
                                          isMain: $0.isMain, isFocused: $0.isFocused)
            }
            return WindowVisibilityPolicy.shouldKeep(
                WindowVisibilityCandidate(title: record.title, bundleIdentifier: record.bundleIdentifier,
                                          isMain: record.isMain, isFocused: record.isFocused),
                among: peers)
        }
        var matchedWindowIDs = Set<UInt32>()
        var records = userFacing.map { record -> WindowRecord in
            let previous = identities[record.pid]?.first { CFEqual($0.0, record.element) }?.1
            let windowID = WindowMatcher.uniqueMatch(pid: record.pid, title: record.title, frame: record.frame,
                                                      candidates: desktopSnapshot.descriptors)
            if let windowID { matchedWindowIDs.insert(windowID) }
            let id = windowID.map { "window-\($0)" } ?? previous ?? UUID().uuidString
            var identified = WindowRecord(id: id, title: record.title, appName: record.appName, appIcon: record.appIcon, pid: record.pid,
                element: record.element, frame: record.frame, isMinimized: record.isMinimized, canClose: record.canClose, canMinimize: record.canMinimize)
            identified.bundleIdentifier = record.bundleIdentifier
            identified.isMain = record.isMain
            identified.isFocused = record.isFocused
            identified.isApplicationHidden = record.isApplicationHidden
            identified.windowID = windowID
            if let windowID, let state = desktopSnapshot.states[windowID] {
                let assignment = WindowDesktopAssignment.resolve(
                    spaceIDs: desktopSnapshot.spaces.memberships[windowID] ?? [],
                    orderedSpaceIDs: desktopSnapshot.spaces.orderedSpaceIDs,
                    currentSpaceIDs: desktopSnapshot.spaces.currentSpaceIDs)
                identified.desktopLocation = assignment.location == .unknown
                    ? WindowDesktopClassifier.classify(isOnScreen: state.isOnScreen, isMinimized: record.isMinimized,
                                                        isApplicationHidden: record.isApplicationHidden)
                    : assignment.location
                identified.desktopIndex = assignment.index
            }
            let geometricPeers = userFacing.filter { peer in
                peer.pid == record.pid && abs(peer.frame.minX - record.frame.minX) <= 2 &&
                abs(peer.frame.minY - record.frame.minY) <= 2 && abs(peer.frame.width - record.frame.width) <= 2 &&
                abs(peer.frame.height - record.frame.height) <= 2
            }
            identified.captureAmbiguous = geometricPeers.contains { peer in
                guard !CFEqual(peer.element, record.element) else { return false }
                return record.title.isEmpty || peer.title.isEmpty || peer.title == record.title
            }
            return identified
        }
        // AX only exposes windows in the active Space. ScreenCaptureKit supplies the
        // missing WindowServer records, while SkyLight supplies their real Space IDs.
        if desktopSnapshot.spaces.isAvailable {
            let runningApps = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) })
            for (windowID, state) in desktopSnapshot.states where !matchedWindowIDs.contains(windowID) {
                guard state.layer == 0, state.frame.width >= 120, state.frame.height >= 80,
                      let app = runningApps[state.pid], app.activationPolicy == .regular,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                      pid == nil || app.processIdentifier == pid else { continue }
                let assignment = WindowDesktopAssignment.resolve(
                    spaceIDs: desktopSnapshot.spaces.memberships[windowID] ?? [],
                    orderedSpaceIDs: desktopSnapshot.spaces.orderedSpaceIDs,
                    currentSpaceIDs: desktopSnapshot.spaces.currentSpaceIDs)
                guard assignment.location == .other, assignment.index != nil else { continue }
                let title = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
                var remote = WindowRecord(id: "window-\(windowID)", title: title,
                    appName: app.localizedName ?? state.appName ?? "Uygulama", appIcon: app.icon,
                    pid: app.processIdentifier, element: applicationElement, frame: state.frame,
                    isMinimized: false, canClose: false, canMinimize: false)
                remote.bundleIdentifier = app.bundleIdentifier ?? state.bundleIdentifier
                remote.desktopLocation = assignment.location
                remote.desktopIndex = assignment.index
                remote.windowID = windowID
                remote.isApplicationHidden = app.isHidden
                remote.isRemoteDesktopWindow = true
                records.append(remote)
            }
        }
        if let pid {
            windows.removeAll { $0.pid == pid }; windows.append(contentsOf: records)
            identities[pid] = records.filter { !$0.isRemoteDesktopWindow }.map { ($0.element, $0.id) }
        } else {
            windows = records
            identities = Dictionary(grouping: records.filter { !$0.isRemoteDesktopWindow }, by: \.pid).mapValues { $0.map { ($0.element, $0.id) } }
        }
        if CommandLine.arguments.contains("--preview-switcher") {
            for record in records {
                NSLog("MacB switcher: %@ | %@ | %@", record.desktopName ?? "unassigned", record.appName, record.title)
            }
        }
        errorMessage = nil
    }

    private struct DesktopWindowState: Sendable {
        let isOnScreen: Bool
        let pid: pid_t
        let title: String
        let frame: CGRect
        let layer: Int
        let appName: String?
        let bundleIdentifier: String?
    }

    private struct DesktopSnapshot: Sendable {
        let descriptors: [WindowDescriptor]
        let states: [UInt32: DesktopWindowState]
        let spaces: DesktopSpaceSnapshot
        static let empty = DesktopSnapshot(descriptors: [], states: [:], spaces: .unavailable)
    }

    private static func desktopSnapshot() async -> DesktopSnapshot {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return .empty
        }
        let descriptors = content.windows.map {
            WindowDescriptor(id: $0.windowID, pid: $0.owningApplication?.processID ?? -1,
                             title: $0.title ?? "", frame: $0.frame)
        }
        let states = Dictionary(uniqueKeysWithValues: content.windows.map {
            ($0.windowID, DesktopWindowState(isOnScreen: $0.isOnScreen,
                pid: $0.owningApplication?.processID ?? -1, title: $0.title ?? "", frame: $0.frame,
                layer: $0.windowLayer, appName: $0.owningApplication?.applicationName,
                bundleIdentifier: $0.owningApplication?.bundleIdentifier))
        })
        let spaces = DesktopSpaceService().snapshot(windowIDs: Array(states.keys))
        return DesktopSnapshot(descriptors: descriptors, states: states, spaces: spaces)
    }

    func focus(_ window: WindowRecord, focusMode: Bool = false) { perform(window, action: .focus(focusMode)) }
    func minimize(_ window: WindowRecord) { guard window.canMinimize else { return }; perform(window, action: .minimize) }
    func close(_ window: WindowRecord) { guard window.canClose else { return }; perform(window, action: .close) }

    private enum Action { case focus(Bool), minimize, close }
    private func perform(_ window: WindowRecord, action: Action) {
        guard AXIsProcessTrusted() else { errorMessage = "Erişilebilirlik izni gerekli."; return }
        if window.isRemoteDesktopWindow {
            guard case .focus(let focusMode) = action else { return }
            let app = NSRunningApplication(processIdentifier: window.pid)
            app?.activate(options: [.activateAllWindows])
            if focusMode { hideOtherApplications(keeping: window.pid) }
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                await self?.refresh(pid: window.pid)
            }
            return
        }
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
