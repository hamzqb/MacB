import Foundation

/// Somewhere MacB can send a question.
///
/// OpenAI is the only one that can do everything — the live voice assistant
/// speaks over their Realtime API and the web search that backs a cited answer
/// is theirs too. The rest are text providers with free tiers, and they all
/// speak the same OpenAI-compatible `/chat/completions` dialect, so the panel,
/// the selection tasks and the ring all work without an OpenAI bill.
///
/// Each key lives in its own Keychain item. One provider's key is never sent to
/// another provider: the request goes to `chatURL`, and `chatURL` is a constant
/// in this file, never anything a model, a web page or a setting can influence.
public enum AIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case openAI
    case groq
    case openRouter
    case gemini
    case huggingFace

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openAI: return "OpenAI"
        case .groq: return "Groq"
        case .openRouter: return "OpenRouter"
        case .gemini: return "Google Gemini"
        case .huggingFace: return "Hugging Face"
        }
    }

    /// The Keychain account name. Stable: renaming a case would orphan a key.
    public var account: String {
        switch self {
        case .openAI: return "openai"
        case .groq: return "groq"
        case .openRouter: return "openrouter"
        case .gemini: return "gemini"
        case .huggingFace: return "huggingface"
        }
    }

    /// What the key starts with, when the provider commits to a prefix.
    ///
    /// Google does not: their keys have been `AIza…` from the console and
    /// `AQ.…` from newer flows, so shape is all that can be checked there.
    public var keyPrefix: String? {
        switch self {
        case .openAI: return "sk-"
        case .groq: return "gsk_"
        case .openRouter: return "sk-or-"
        case .huggingFace: return "hf_"
        case .gemini: return nil
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI: return "gpt-5-mini"
        case .groq: return "llama-3.3-70b-versatile"
        case .openRouter: return "meta-llama/llama-3.3-70b-instruct:free"
        case .gemini: return "gemini-2.5-flash"
        case .huggingFace: return "meta-llama/Llama-3.3-70B-Instruct"
        }
    }

    /// Whether the provider has a free tier worth relying on.
    public var isFree: Bool { self != .openAI }

    /// Whether the model can search the web itself and cite what it read.
    public var canSearchWeb: Bool { self == .openAI }

    /// Whether the live voice assistant can run on it.
    public var canSpeak: Bool { self == .openAI }

    /// Where a streamed chat request goes.
    ///
    /// Everything except OpenAI uses the compatibility endpoint each of these
    /// services publishes, which is the same request and the same event stream.
    public var chatURL: URL {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1/responses")!
        case .groq: return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .huggingFace: return URL(string: "https://router.huggingface.co/v1/chat/completions")!
        }
    }

    /// The cheapest authenticated call there is, for checking a key.
    public var modelsURL: URL {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1/models")!
        case .groq: return URL(string: "https://api.groq.com/openai/v1/models")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/models")!
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/models")!
        case .huggingFace: return URL(string: "https://router.huggingface.co/v1/models")!
        }
    }

    /// Where to get a key, for the settings window.
    public var signUpURL: URL {
        switch self {
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")!
        case .groq: return URL(string: "https://console.groq.com/keys")!
        case .openRouter: return URL(string: "https://openrouter.ai/keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .huggingFace: return URL(string: "https://huggingface.co/settings/tokens")!
        }
    }

    /// One line for the settings window, so the choice is not a guess.
    public var note: String {
        switch self {
        case .openAI:
            return "Ücretli. Canlı sesli asistan ve kaynak gösteren web araması yalnız bunda var."
        case .groq:
            return "Ücretsiz ve çok hızlı. Panel, seçili metin ve halka için iyi. Web araması yok."
        case .openRouter:
            return "Ücretsiz modeller var. Model adını kendin yazabilirsin."
        case .gemini:
            return "Google'ın ücretsiz katmanı. Uzun metinlerde iyi."
        case .huggingFace:
            return "Ücretsiz katman dar; yedek olarak dursun."
        }
    }

    /// Models worth offering, newest and cheapest first.
    ///
    /// A list, not the list: these services add and retire models constantly,
    /// so the settings window offers these and lets a name be typed as well.
    public var modelChoices: [String] {
        switch self {
        case .openAI:
            return ["gpt-6-astra", "gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-4.1-mini"]
        case .groq:
            return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant",
                    "openai/gpt-oss-120b", "qwen/qwen3-32b"]
        case .openRouter:
            return ["meta-llama/llama-3.3-70b-instruct:free", "deepseek/deepseek-chat-v3.1:free",
                    "google/gemma-3-27b-it:free", "qwen/qwen3-235b-a22b:free"]
        case .gemini:
            return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
        case .huggingFace:
            return ["meta-llama/Llama-3.3-70B-Instruct", "Qwen/Qwen2.5-72B-Instruct"]
        }
    }

    /// Providers a question can actually be sent to, in the order they should be
    /// offered: the free and fast ones first, because that is the one somebody
    /// without a paid account wants picked for them.
    public static let textOrder: [AIProvider] = [.groq, .gemini, .openRouter, .openAI, .huggingFace]

    /// The provider to use when nobody has chosen one, given what is stored.
    ///
    /// Free before paid, so MacB never quietly starts spending money that a
    /// stored free key would have covered.
    public static func automatic(stored: Set<AIProvider>) -> AIProvider? {
        textOrder.first { stored.contains($0) }
    }
}

/// What a key looks like, before it goes anywhere near the Keychain.
///
/// Only the shape. Whether a key actually works is a question only the provider
/// can answer, and MacB asks it separately. This exists to catch the ordinary
/// mistakes — a half-copied paste, a key with a newline in it, a sentence
/// pasted into the wrong field — at the point where they can still be
/// explained, rather than storing them and failing later with a 401 and no idea
/// why.
public enum AIKeyFormat {
    /// OpenAI's prefix, kept as its own name because the settings window and
    /// the older tests both speak of it.
    public static let prefix = "sk-"
    /// Short enough to accept anything real, long enough to catch a truncated
    /// paste — no real key is anywhere near this short.
    public static let minimumLength = 20

    public static func looksLikeKey(_ value: String) -> Bool {
        looksLikeKey(value, for: .openAI)
    }

    public static func looksLikeKey(_ value: String, for provider: AIProvider) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumLength, !trimmed.contains(where: { $0.isWhitespace }) else {
            return false
        }
        guard let prefix = provider.keyPrefix else { return true }
        return trimmed.hasPrefix(prefix)
    }

    /// Why a key was refused, in the words of the provider that wants it.
    public static func complaint(for provider: AIProvider) -> String {
        guard let prefix = provider.keyPrefix else {
            return "Bu bir \(provider.title) anahtarına benzemiyor."
        }
        return "Bu bir \(provider.title) anahtarına benzemiyor. Anahtarlar \(prefix) ile başlar."
    }
}
