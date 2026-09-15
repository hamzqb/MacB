import AppKit
import MacBCore

/// Puts back what MacB moved to the Trash.
///
/// Stateless on purpose: the batch that can still be taken back lives on the
/// coordinator that made it, so there is one published copy of it and the
/// settings window cannot be looking at a stale offer. This is only the part
/// that touches the disk.
///
/// Nothing here deletes. The worst it can do is move a folder out of the Trash,
/// and it refuses even that when something has taken the old path back.
enum TrashUndo {
    /// Puts everything back where it can, and says what it could not.
    static func restore(_ moves: [TrashMove]) -> String {
        let manager = FileManager.default
        var restored = 0, missing = 0, occupied = 0
        for move in moves {
            let outcome = TrashRestorePlan.outcome(
                trashedExists: manager.fileExists(atPath: move.trashed.path),
                originalExists: manager.fileExists(atPath: move.original.path))
            switch outcome {
            case .missingFromTrash:
                missing += 1
            case .occupied:
                occupied += 1
            case .restore:
                let parent = move.original.deletingLastPathComponent()
                // The uninstaller can empty a container folder completely, and
                // macOS removes the empty folder along with its last child.
                if !manager.fileExists(atPath: parent.path) {
                    try? manager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                do {
                    try manager.moveItem(at: move.trashed, to: move.original)
                    restored += 1
                } catch {
                    occupied += 1
                }
            }
        }
        return TrashRestorePlan.summary(restored: restored, missing: missing, occupied: occupied)
    }
}

extension NSWorkspace {
    /// `recycle` in the shape MacB needs: what moved, and where to.
    ///
    /// The API already reports the new location of everything it moves, keyed by
    /// the original URL. MacB used to discard that, which is the only reason
    /// undoing a sweep meant asking the user to go digging in the Trash.
    func recycleRecording(_ urls: [URL]) async throws -> [TrashMove] {
        let moved = try await recycle(urls)
        return urls.compactMap { url in
            guard let destination = moved[url] else { return nil }
            return TrashMove(original: url, trashed: destination)
        }
    }
}
