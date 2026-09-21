import AppKit
import CryptoKit
import Foundation
import MacBCore

/// Getting the local model onto the Mac, and off it again.
///
/// Downloaded only when the user presses the button, from the address in
/// `LocalModel`, and kept only if its SHA-256 matches the published one — a
/// file cut short or altered on the way is thrown away, not loaded. Removing
/// it moves it to the Trash, like everything else MacB lets go of.
@MainActor final class LocalModelStore: NSObject, ObservableObject {
    static let shared = LocalModelStore()

    enum State: Equatable {
        case missing
        case downloading(Double)
        case verifying
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .missing

    private var task: URLSessionDownloadTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    let file = LocalModel.current

    private override init() {
        super.init()
        refresh()
    }

    func refresh() {
        if case .downloading = state { return }
        if state == .verifying { return }
        state = LocalLLM.isInstalled(file) ? .ready : .missing
    }

    func download() {
        switch state {
        case .downloading, .verifying, .ready: return
        default: break
        }
        state = .downloading(0)
        let task = session.downloadTask(with: file.url)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = LocalLLM.isInstalled(file) ? .ready : .missing
    }

    /// To the Trash, where the user can still take it back.
    func moveToTrash() {
        LocalLLM.shared.unload()
        let url = LocalLLM.url(for: file)
        NSWorkspace.shared.recycle([url]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func finished(at temporary: URL) {
        state = .verifying
        let file = file
        Task.detached(priority: .utility) {
            let matches = Self.sha256(of: temporary) == file.sha256
            var failure: String?
            if matches {
                do {
                    try FileManager.default.createDirectory(at: LocalLLM.modelsFolder, withIntermediateDirectories: true)
                    let destination = LocalLLM.url(for: file)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
                    } else {
                        try FileManager.default.moveItem(at: temporary, to: destination)
                    }
                } catch {
                    failure = "Model kaydedilemedi."
                }
            } else {
                failure = "İnen dosya doğrulanamadı; bozuk ya da eksik inmiş. Tekrar dene."
            }
            if failure != nil {
                try? FileManager.default.trashItem(at: temporary, resultingItemURL: nil)
            }
            await MainActor.run { [failure] in
                self.task = nil
                self.state = failure.map { .failed($0) } ?? .ready
            }
        }
    }

    nonisolated static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension LocalModelStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated {
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : file.bytes
            state = .downloading(min(1, Double(totalBytesWritten) / Double(total)))
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // The system deletes `location` when this returns: move it first.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("macb-model-\(UUID().uuidString).gguf")
        let moved = (try? FileManager.default.moveItem(at: location, to: kept)) != nil
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        MainActor.assumeIsolated {
            guard moved, status == 200 else {
                task = nil
                state = .failed("İndirme başarısız oldu (\(status)).")
                return
            }
            finished(at: kept)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        MainActor.assumeIsolated {
            self.task = nil
            state = .failed("İndirme kesildi: \(error.localizedDescription)")
        }
    }
}
