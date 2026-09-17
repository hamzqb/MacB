import Foundation

/// Finding one entry in a clipboard history, by typing part of it.
///
/// A history is a list of things somebody already had, which is exactly the
/// case where scrolling is the wrong tool: they know what they copied, they
/// just cannot remember when. The filters in the island answer "what kind of
/// thing"; this answers "the one with this in it".
///
/// Turkish is the reason this is not one `localizedCaseInsensitiveContains`.
/// The language has four letters where English has two — I ı İ i — and no
/// locale makes them all equal, because no locale is supposed to: folding with
/// the Turkish locale turns "İstanbul" into "ıstanbul" and folding without it
/// leaves "ı" alone, so either way half the searches somebody actually types
/// find nothing. A search field is not orthography, though. Anybody typing
/// "istanbul" in a hurry means "İstanbul", and typing "gunaydin" means
/// "günaydın", so all four i's are flattened to one before anything else
/// happens, and the accents go with them.
public enum ClipboardSearch {
    /// The four i's, and what they all become.
    private static let turkishI: [Character: Character] = [
        "İ": "i", "I": "i", "ı": "i", "i": "i"
    ]

    /// The form both sides of a comparison are put into.
    public static func normalized(_ value: String) -> String {
        let flattened = String(value.map { turkishI[$0] ?? $0 })
        // Locale-independent from here: the one locale-sensitive decision has
        // already been made above, on purpose and in one place.
        return flattened.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                 locale: nil)
    }

    /// Whether an entry matches what has been typed.
    ///
    /// An empty query matches everything, so the list is whole until somebody
    /// actually starts typing.
    public static func matches(haystack: [String?], query: String) -> Bool {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return true }
        return haystack.compactMap { $0 }.contains { normalized($0).contains(needle) }
    }
}
