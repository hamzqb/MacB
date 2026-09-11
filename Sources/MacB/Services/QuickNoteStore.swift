import Combine
import Foundation

/// A single scratch note, kept as plain text on disk.
///
/// Deliberately not a note *list*: the widget is one card, and a second list to
/// manage would duplicate the tasks section that already exists. Writes are
/// debounced because the text field reports every keystroke, and a note is not
/// worth an atomic write per character.
@MainActor final class QuickNoteStore: ObservableObject {
    /// Long enough for a phone number, an address or a paragraph; short enough
    /// that the file cannot quietly become a document store.
    static let characterLimit = 2000

    @Published var text: String = "" {
        didSet {
            if text.count > Self.characterLimit { text = String(text.prefix(Self.characterLimit)) }
            guard text != oldValue else { return }
            scheduleSave()
        }
    }

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB/note.txt")
        if let stored = try? String(contentsOf: self.fileURL, encoding: .utf8) {
            text = String(stored.prefix(Self.characterLimit))
        }
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The first line, for the collapsed preview.
    var headline: String {
        text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }

    func clear() { text = "" }

    /// Writes immediately, for when the panel is closing and the debounce would
    /// otherwise be cancelled with unsaved text.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        write()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
