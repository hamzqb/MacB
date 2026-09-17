import Foundation

/// What an OpenAI key looks like, before it goes anywhere near the Keychain.
///
/// Only the shape. Whether a key actually works is a question only OpenAI can
/// answer, and MacB asks it separately. This exists to catch the ordinary
/// mistakes — a half-copied paste, a key with a newline in it, a sentence
/// pasted into the wrong field — at the point where they can still be explained,
/// rather than storing them and failing later with a 401 and no idea why.
public enum AIKeyFormat {
    /// OpenAI's prefix. Project keys, user keys and service-account keys all
    /// carry it; the part after it varies and is not worth guessing at.
    public static let prefix = "sk-"
    /// Short enough to accept anything real, long enough to catch a truncated
    /// paste — no real key is anywhere near this short.
    public static let minimumLength = 20

    public static func looksLikeKey(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix(prefix)
            && trimmed.count >= minimumLength
            && !trimmed.contains(where: { $0.isWhitespace })
    }
}
