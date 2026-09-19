import Combine
import Foundation
import MacBCore
import Security

/// Where the provider keys live, which is the Keychain and nowhere else.
///
/// Not `UserDefaults`, not a file in Application Support, not a constant in the
/// source. A key in `UserDefaults` is a key in a plist that every process
/// running as this user can read, and a key in the source is a key in the git
/// history for good. These are generic password items, readable only by this
/// application, only on this Mac, and only while the Mac is unlocked.
///
/// One item per provider, and a key is only ever sent to the provider it
/// belongs to — the address comes from `AIProvider`, a constant in the source,
/// never from a setting, a model or a page.
///
/// Deliberately not `userPresence`-protected, unlike the face vault: that would
/// put a Touch ID prompt in front of every single request, and a key that is
/// painful to use is a key somebody moves somewhere easier.
///
/// No key is ever logged, printed, put in an error message, or shown back in
/// the settings window — once one is in, MacB will say that it has it and
/// nothing more. There is no way to read one out of the interface, only to
/// replace it or delete it.
@MainActor final class AIKeyStore: ObservableObject {
    /// Which providers have a key. The keys themselves are deliberately not
    /// published.
    @Published private(set) var stored: Set<AIProvider> = []
    /// The result of the last check against each provider, for the settings
    /// window.
    @Published private(set) var status: [AIProvider: Status] = [:]
    @Published var errorMessage: String?

    enum Status: Equatable {
        case idle
        case checking
        case valid(String)
        case invalid(String)
    }

    private let service: String

    init(service: String = "dev.hamzababal.MacB.ai") {
        self.service = service
        stored = Set(AIProvider.allCases.filter { exists($0) })
    }

    // MARK: - What is stored

    /// Whether any provider can answer a question.
    var hasKey: Bool { !stored.isEmpty }
    /// Whether the live voice assistant can run, which only OpenAI can do.
    var hasVoiceKey: Bool { stored.contains(.openAI) }

    func has(_ provider: AIProvider) -> Bool { stored.contains(provider) }

    func status(of provider: AIProvider) -> Status { status[provider] ?? .idle }

    // MARK: - Storage

    /// Stores a key, replacing whatever was there.
    ///
    /// Rejects anything that is obviously not a key before it goes near the
    /// Keychain, so a pasted sentence or a stray newline does not become a
    /// stored credential that fails on every request with no explanation.
    @discardableResult
    func save(_ raw: String, for provider: AIProvider = .openAI) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AIKeyFormat.looksLikeKey(key, for: provider) else {
            errorMessage = AIKeyFormat.complaint(for: provider)
            return false
        }
        guard write(key, for: provider) else { return false }
        errorMessage = nil
        status[provider] = .idle
        stored.insert(provider)
        return true
    }

    /// Forgets a key. Nothing else in MacB keeps a copy.
    func remove(_ provider: AIProvider = .openAI) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
        stored.remove(provider)
        status[provider] = nil
        errorMessage = nil
    }

    /// A stored key, for the places that make requests with it.
    ///
    /// Internal rather than published on purpose: nothing should be holding one
    /// of these in a view, a log line or an observable object.
    func read(_ provider: AIProvider = .openAI) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    private func write(_ key: String, for provider: AIProvider) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        var query = baseQuery(provider)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrLabel as String] = "MacB — \(provider.title)"
        let result = SecItemAdd(query as CFDictionary, nil)
        guard result == errSecSuccess else {
            // The status code, never the key.
            errorMessage = "\(provider.title) anahtarı Keychain'e yazılamadı (\(result))."
            return false
        }
        return true
    }

    /// Whether an item is stored, without reading the secret.
    ///
    /// Asking for attributes only never decrypts the item, so it never puts a
    /// Keychain permission prompt on screen. Reading the key itself at launch
    /// did: after a re-signed build, the app sat blocked in `init`, before any
    /// window or status item existed, until someone answered a prompt they had
    /// no reason to expect.
    private func exists(_ provider: AIProvider) -> Bool {
        var query = baseQuery(provider)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    private func baseQuery(_ provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.account]
    }

    // MARK: - Bulk import

    /// Stores several keys at once, for the one-off import that moves keys off
    /// a piece of paper and into the Keychain.
    ///
    /// Returns which ones went in. Nothing is echoed back, and a key that fails
    /// the shape check is refused here exactly as it would be in the settings
    /// window.
    @discardableResult
    func importKeys(_ keys: [AIProvider: String]) -> [AIProvider: Bool] {
        var outcome: [AIProvider: Bool] = [:]
        for (provider, key) in keys {
            outcome[provider] = save(key, for: provider)
        }
        return outcome
    }

    // MARK: - Verification

    /// Asks the provider whether the key works.
    ///
    /// The lightest authenticated call there is — a model list — so nothing is
    /// generated, nothing is billed beyond the request itself, and the answer is
    /// a plain yes or no. This is the only thing in MacB that sends a key
    /// anywhere other than a question, and it sends it to the provider it
    /// belongs to, which is where it is meant to go.
    func verify(_ provider: AIProvider = .openAI) async {
        guard let key = read(provider) else {
            status[provider] = .invalid("Kayıtlı anahtar yok.")
            return
        }
        status[provider] = .checking
        var request = URLRequest(url: provider.modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200: status[provider] = .valid("Anahtar çalışıyor.")
            case 401, 403:
                status[provider] = .invalid("\(provider.title) anahtarı reddetti. İptal edilmiş ya da yanlış olabilir.")
            case 429: status[provider] = .invalid("Anahtar geçerli ama kota dolu görünüyor.")
            default: status[provider] = .invalid("\(provider.title) \(code) döndürdü.")
            }
        } catch {
            status[provider] = .invalid("\(provider.title)'ye ulaşılamadı: \(error.localizedDescription)")
        }
    }
}
