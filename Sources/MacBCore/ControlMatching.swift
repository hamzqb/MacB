import Foundation

/// Deciding which control on screen somebody meant.
///
/// What a person says and what is written on a button agree about as often as
/// not: "kaydet" for "Kaydet…", "gönder" for "Gönder ⌘↩", "yeni sekme" for
/// "Sekme Aç". Matching them exactly is why an assistant that can plainly see
/// a button answers that there is no such button. This is the part of that
/// judgement that is pure text, so it can be argued about in a test rather
/// than on a screen.
public enum ControlMatching {
    /// Turkish-aware folding: dotted and dotless i become the same letter, as
    /// does every accent, and the ends are trimmed of spaces and punctuation.
    public static func normalise(_ text: String) -> String {
        text.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// How well a name answers to what was asked for, 0 when it does not at
    /// all. Both sides are expected to be normalised already.
    public static func match(_ name: String, _ wanted: String) -> Int {
        guard !name.isEmpty, !wanted.isEmpty else { return 0 }
        if name == wanted { return 100 }
        if name.hasPrefix(wanted) { return 80 }
        if name.contains(wanted) { return 60 }
        let words = wanted.split(separator: " ").map(String.init).filter { $0.count > 1 }
        if words.count > 1, words.allSatisfy({ name.contains($0) }) { return 50 }
        if words.count > 1, let word = words.first, name.contains(word) { return 30 }
        let distance = editDistance(name, wanted)
        let longest = max(name.count, wanted.count)
        // Within a quarter of the longer name is a typo or an ending, not a
        // different button.
        if longest > 3, distance * 4 <= longest { return max(1, 40 - distance) }
        return 0
    }

    /// Levenshtein, on names short enough that the simple version is free.
    public static func editDistance(_ first: String, _ second: String) -> Int {
        let left = Array(first.prefix(48))
        let right = Array(second.prefix(48))
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }
        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}
