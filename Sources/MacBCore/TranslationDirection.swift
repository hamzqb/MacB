import Foundation

/// Which way a selection is translated.
///
/// Nobody wants to pick two languages from menus in the middle of reading: the
/// source is whatever the text turns out to be, and the target is the language
/// the user reads in — unless the text is already in it, in which case the
/// useful direction is the other one (a Turkish reply that needs to go out in
/// English).
public enum TranslationDirection {
    /// The language used when the text is already in the preferred one.
    public static let fallbackTarget = "en"

    /// Language codes are compared by their base language only, so `tr-TR`
    /// and `tr` count as the same thing and `pt-BR` text is not "translated"
    /// into `pt`.
    public static func target(source: String?, preferred: String,
                              fallback: String = fallbackTarget) -> String {
        let wanted = base(preferred)
        guard let source, base(source) == wanted else { return wanted }
        return base(fallback) == wanted ? "tr" : base(fallback)
    }

    public static func base(_ code: String) -> String {
        let lowered = code.lowercased().replacingOccurrences(of: "_", with: "-")
        return String(lowered.split(separator: "-").first ?? Substring(lowered))
    }

    /// The languages offered as a target in Settings, as (code, Turkish name).
    public static let choices: [(code: String, title: String)] = [
        ("tr", "Türkçe"), ("en", "İngilizce"), ("de", "Almanca"), ("fr", "Fransızca"),
        ("es", "İspanyolca"), ("it", "İtalyanca"), ("ar", "Arapça"), ("ru", "Rusça"),
        ("ja", "Japonca"), ("zh", "Çince")
    ]
}
