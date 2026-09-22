import Foundation

/// Whether copied text looks like a credential: an API key, a token, a
/// private key. The clipboard history never keeps one.
///
/// Password managers mark their own copies as concealed, and those were
/// already skipped; an API key copied from a web page carries no such mark,
/// and one ended up in the history, written to disk. Known shapes are caught
/// by their prefix; anything else that is one long unbroken run of mixed
/// case letters and digits is treated as a secret too, because that is what
/// a generated key looks like and ordinary text almost never does.
public enum SecretDetector {
    static let prefixes = ["nvapi-", "sk-", "sk_live_", "sk_test_", "rk_live_", "pk_live_", "AIza", "ghp_", "gho_",
                           "ghu_", "ghs_", "github_pat_", "glpat-", "gsk_", "xai-", "hf_", "npm_", "xoxb-", "xoxp-",
                           "xoxa-", "xoxs-", "ya29.", "AKIA", "ASIA", "shpat_", "sq0atp-", "dop_v1_", "pat-"]

    public static func looksLikeSecret(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16 else { return false }
        if trimmed.contains("-----BEGIN") && trimmed.contains("PRIVATE KEY") { return true }
        // One token only: a sentence that mentions a key prefix is not a key.
        guard !trimmed.contains(where: \.isWhitespace) else { return false }
        if prefixes.contains(where: { trimmed.hasPrefix($0) }) { return true }
        if isJWT(trimmed) { return true }
        guard trimmed.count >= 32, !trimmed.contains("://"), !trimmed.contains("/"), !trimmed.contains("@") else {
            return false
        }
        let hasUpper = trimmed.contains(where: \.isUppercase)
        let hasLower = trimmed.contains(where: \.isLowercase)
        let hasDigit = trimmed.contains(where: \.isNumber)
        return hasUpper && hasLower && hasDigit
    }

    private static func isJWT(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && text.hasPrefix("eyJ") && parts.allSatisfy { $0.count >= 8 }
    }
}
