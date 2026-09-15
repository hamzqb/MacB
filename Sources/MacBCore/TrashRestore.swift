import Foundation

/// One thing MacB moved to the Trash, and where it came from.
///
/// `NSWorkspace.recycle` hands back the new location of everything it moved, and
/// MacB used to throw that away. Keeping it is the whole difference between
/// "moved to Trash, open the Trash to put it back" — which asks the user to find
/// one folder among hundreds and remember where it belonged — and a button that
/// does it.
public struct TrashMove: Equatable, Codable, Sendable {
    /// Where the item was before MacB touched it.
    public let original: URL
    /// Where it is now, inside the Trash.
    public let trashed: URL

    public init(original: URL, trashed: URL) {
        self.original = original
        self.trashed = trashed
    }
}

/// What can be done about one recorded move, right now.
public enum TrashRestoreOutcome: Equatable, Sendable {
    /// The item is still in the Trash and its old place is free.
    case restore
    /// The Trash has been emptied, or the item was dragged out of it.
    case missingFromTrash
    /// Something is at the old path again — a cache the application rebuilt, or
    /// a reinstalled bundle. Putting the old copy back would overwrite it.
    case occupied
}

/// Decides, per item, whether an undo is still possible.
///
/// This is separated from the file system deliberately: the interesting part is
/// not the moving, it is refusing to move. An undo that overwrites whatever the
/// user has put at the old path since is worse than no undo, and that judgement
/// needs to be provable without a Trash to empty.
public enum TrashRestorePlan {
    public static func outcome(trashedExists: Bool, originalExists: Bool) -> TrashRestoreOutcome {
        guard trashedExists else { return .missingFromTrash }
        return originalExists ? .occupied : .restore
    }

    /// What to tell the user once the restore has run.
    ///
    /// Partial results are the common case — an application rebuilds one of its
    /// caches while the review sheet is open — so the message has to carry all
    /// three numbers rather than claiming success and hoping.
    public static func summary(restored: Int, missing: Int, occupied: Int) -> String {
        if restored == 0 && missing == 0 && occupied == 0 { return "Geri alınacak bir şey yok." }
        var parts: [String] = []
        if restored > 0 { parts.append("\(restored) öğe eski yerine kondu") }
        if missing > 0 { parts.append("\(missing) öğe Çöp Sepeti'nde bulunamadı") }
        if occupied > 0 { parts.append("\(occupied) öğenin eski yeri dolu olduğu için dokunulmadı") }
        return parts.joined(separator: ", ") + "."
    }
}
