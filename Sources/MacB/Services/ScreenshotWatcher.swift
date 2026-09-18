import Foundation
import MacBCore

/// Notices new screenshots and hands them to the shelf.
///
/// Watches one folder — wherever the Screenshot app saves — with a kernel event
/// source, so nothing polls. The folder is read only when it changes, and only
/// files newer than the last look are considered, so a Desktop with a thousand
/// old screenshots on it does not flood the shelf the moment this is switched on.
///
/// Nothing is copied, moved or opened. The shelf keeps a reference to the file
/// where macOS put it, exactly as if it had been dragged there.
@MainActor final class ScreenshotWatcher {
    var onScreenshot: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var folder: URL?
    private var lastLook = Date()
    private var seen = Set<String>()

    var isRunning: Bool { source != nil }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard source == nil else { return }
        let configured = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let folder = ScreenshotDetection.folder(
            configured: configured, home: FileManager.default.homeDirectoryForCurrentUser,
            exists: { FileManager.default.fileExists(atPath: $0) })
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            // A screenshot arrives as a hidden temporary file that is then
            // renamed, and each step is its own event. A short pause lets the
            // rename finish so the finished file is what gets picked up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MainActor.assumeIsolated { self?.scan() }
            }
        }
        source.setCancelHandler { close(fd) }
        self.folder = folder
        self.descriptor = fd
        self.source = source
        lastLook = Date()
        seen = []
        source.resume()
    }

    private func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
        folder = nil
    }

    private func scan() {
        guard let folder else { return }
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: []) else { return }
        let since = lastLook.addingTimeInterval(-2)
        lastLook = Date()
        for url in entries where !seen.contains(url.path) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let created = values.creationDate, created >= since else { continue }
            guard ScreenshotDetection.isScreenshot(fileName: url.lastPathComponent,
                                                   hasCaptureAttribute: Self.captureAttribute(of: url)) else { continue }
            seen.insert(url.path)
            onScreenshot?(url)
        }
    }

    /// True when the file carries macOS's own "this is a screenshot" mark, nil
    /// otherwise.
    ///
    /// Never false: the mark can land a moment after the file does, and a
    /// missing mark is not proof of anything, so the name gets to decide.
    private static func captureAttribute(of url: URL) -> Bool? {
        getxattr(url.path, ScreenshotDetection.attributeName, nil, 0, 0, 0) > 0 ? true : nil
    }
}
