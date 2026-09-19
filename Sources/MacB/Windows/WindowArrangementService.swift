import AppKit
import ApplicationServices
import Combine
import MacBCore

/// Saves where the windows are and puts them back.
///
/// Only windows of applications that are already running are moved. Nothing
/// is launched, closed, hidden or resized beyond the saved frame, and a
/// window that cannot be moved is left where it is. Saved arrangements are
/// kept in MacB's own folder; window titles can name private documents, so
/// the file is readable by this user only.
@MainActor final class WindowArrangementService: ObservableObject {
    @Published private(set) var arrangements: [WindowArrangement] = []
    @Published private(set) var lastMessage: String?

    private let fileURL: URL
    private var pendingAutomatic: DispatchWorkItem?
    private var lastSignature: DisplaySignature?
    /// Set when the saved file could not be read. Saving then refuses rather
    /// than replacing arrangements it could not see with an empty list.
    private var storageUnreadable = false

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB")) {
        fileURL = directory.appendingPathComponent("window-arrangements.json")
        load()
        lastSignature = Self.currentSignature()
    }

    // MARK: Saving

    @discardableResult
    func saveCurrent(named name: String) -> WindowArrangement? {
        guard AXIsProcessTrusted() else {
            lastMessage = "Pencereleri okumak için Erişilebilirlik izni gerekiyor."
            return nil
        }
        let windows = Self.snapshot()
        guard !windows.isEmpty else {
            lastMessage = "Kaydedilecek pencere bulunamadı."
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Düzen \(arrangements.count + 1)" : trimmed
        let arrangement = WindowArrangement(name: title, displays: Self.currentSignature(), windows: windows)
        arrangements.append(arrangement)
        persist()
        lastMessage = "\(windows.count) pencere kaydedildi."
        return arrangement
    }

    /// Takes the windows as they are now into an existing arrangement.
    func update(_ id: UUID) {
        guard let index = arrangements.firstIndex(where: { $0.id == id }) else { return }
        let windows = Self.snapshot()
        guard !windows.isEmpty else { lastMessage = "Kaydedilecek pencere bulunamadı."; return }
        arrangements[index].windows = windows
        arrangements[index].displays = Self.currentSignature()
        arrangements[index].savedAt = Date()
        persist()
        lastMessage = "\(arrangements[index].name) güncellendi."
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = arrangements.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        arrangements[index].name = trimmed
        persist()
    }

    func setAutomatic(_ id: UUID, _ on: Bool) {
        guard let index = arrangements.firstIndex(where: { $0.id == id }) else { return }
        arrangements[index].restoresAutomatically = on
        persist()
    }

    /// Takes an arrangement off MacB's list. The windows are not touched.
    func forget(_ id: UUID) {
        arrangements.removeAll { $0.id == id }
        persist()
    }

    // MARK: Restoring

    @discardableResult
    func apply(_ arrangement: WindowArrangement) -> Int {
        guard AXIsProcessTrusted() else {
            lastMessage = "Pencereleri taşımak için Erişilebilirlik izni gerekiyor."
            return 0
        }
        let live = Self.liveWindows()
        let pairs = WindowArrangementMatcher.match(saved: arrangement.windows, live: live.map(\.descriptor))
        var moved = 0
        for (savedIndex, liveIndex) in pairs.enumerated() {
            guard let liveIndex else { continue }
            if Self.move(live[liveIndex].element, to: arrangement.windows[savedIndex].frame) { moved += 1 }
        }
        let missing = pairs.filter { $0 == nil }.count
        lastMessage = missing > 0
            ? "\(moved) pencere yerleşti, \(missing) pencere açık değil."
            : "\(moved) pencere yerleşti."
        return moved
    }

    /// The ring's slice: the arrangement for this display setup, or the latest.
    func applyPreferred() -> String {
        guard let arrangement = WindowArrangementMatcher.preferred(for: Self.currentSignature(), in: arrangements) else {
            return "Kayıtlı pencere düzeni yok"
        }
        let moved = apply(arrangement)
        return moved > 0 ? "\(arrangement.name): \(moved) pencere" : "\(arrangement.name): taşınacak pencere yok"
    }

    /// Called when screens are attached, removed or rearranged. Waits for the
    /// windows to settle — macOS moves them itself first — then puts back the
    /// arrangement marked for the new setup, if there is one.
    func displaysChanged(notice: @escaping (String) -> Void) {
        let signature = Self.currentSignature()
        guard signature != lastSignature else { return }
        lastSignature = signature
        pendingAutomatic?.cancel()
        guard let arrangement = WindowArrangementMatcher.automatic(for: signature, in: arrangements) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let moved = self.apply(arrangement)
            if moved > 0 { notice("\(arrangement.name) düzeni uygulandı") }
        }
        pendingAutomatic = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    // MARK: Reading windows

    private struct Live {
        let element: AXUIElement
        let descriptor: LiveWindow
        let frame: CGRect
        let appName: String
    }

    static func currentSignature() -> DisplaySignature {
        DisplaySignature(bounds: NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                ?? CGMainDisplayID()
            return CGDisplayBounds(id)
        })
    }

    private static func snapshot() -> [SavedWindow] {
        liveWindows().map {
            SavedWindow(bundleIdentifier: $0.descriptor.bundleIdentifier, appName: $0.appName,
                        title: $0.descriptor.title, index: $0.descriptor.index, frame: $0.frame)
        }
    }

    /// Every ordinary, visible window of every regular application.
    private static func liveWindows() -> [Live] {
        var result: [Live] = []
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != me {
            guard let bundle = app.bundleIdentifier else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.3)
            guard let windows = axAttribute(element, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            var index = 0
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.3)
                guard (axAttribute(window, kAXSubroleAttribute) as? String) == (kAXStandardWindowSubrole as String),
                      (axAttribute(window, kAXMinimizedAttribute) as? Bool) != true,
                      let frame = axFrame(window), frame.width > 40, frame.height > 40 else { continue }
                let title = axAttribute(window, kAXTitleAttribute) as? String ?? ""
                result.append(Live(element: window,
                                   descriptor: LiveWindow(bundleIdentifier: bundle, title: title, index: index),
                                   frame: frame, appName: app.localizedName ?? bundle))
                index += 1
            }
        }
        return result
    }

    private static func move(_ element: AXUIElement, to frame: CGRect) -> Bool {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        var movable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &movable) == .success,
              movable.boolValue else { return false }
        let first = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        // Moved again after resizing: some applications clamp the size and
        // shift the window while doing it.
        _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        return first == .success
    }

    // MARK: Storage

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do { arrangements = try JSONDecoder().decode([WindowArrangement].self, from: data) }
        catch {
            storageUnreadable = true
            lastMessage = "Kayıtlı düzenler okunamadı; dosyaya dokunulmayacak."
        }
    }

    private func persist() {
        guard !storageUnreadable else {
            lastMessage = "Kayıtlı düzenler dosyası okunamadığı için üzerine yazılmadı."
            return
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(arrangements).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            lastMessage = "Düzen kaydedilemedi: \(error.localizedDescription)"
        }
    }
}
