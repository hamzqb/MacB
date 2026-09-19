import Combine
import Foundation
import MacBCore

/// Jarvis's long-term memory: a short Markdown list in MacB's own folder,
/// readable by this user only, that the user can read, edit or empty.
///
/// It holds only what the user asked Jarvis to remember. Nothing is added
/// behind their back, and the whole list is shown in Settings.
@MainActor final class JarvisMemoryStore: ObservableObject {
    @Published private(set) var facts: [String] = []
    let fileURL: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB")) {
        fileURL = directory.appendingPathComponent("jarvis-memory.md")
        reload()
    }

    /// Picks up edits made to the file by hand.
    func reload() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        facts = JarvisMemory.parse(text)
    }

    @discardableResult
    func remember(_ fact: String) -> Bool {
        let updated = JarvisMemory.adding(fact, to: facts)
        guard updated != facts else { return false }
        facts = updated
        save()
        return true
    }

    @discardableResult
    func forget(about: String) -> Int {
        let (kept, removed) = JarvisMemory.removing(about: about, from: facts)
        guard removed > 0 else { return 0 }
        facts = kept
        save()
        return removed
    }

    func remove(at index: Int) {
        guard facts.indices.contains(index) else { return }
        facts.remove(at: index)
        save()
    }

    func removeAll() {
        facts = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JarvisMemory.render(facts).write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            NSLog("MacB: Jarvis memory could not be saved")
        }
    }
}
