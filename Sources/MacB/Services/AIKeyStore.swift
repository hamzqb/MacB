import Combine
import Foundation
import MacBCore
import Security

/// Where the OpenAI key lives, which is the Keychain and nowhere else.
///
/// Not `UserDefaults`, not a file in Application Support, not a constant in the
/// source. A key in `UserDefaults` is a key in a plist that every process
/// running as this user can read, and a key in the source is a key in the git
/// history for good. This is a generic password item, readable only by this
/// application, only on this Mac, and only while the Mac is unlocked.
///
/// Deliberately not `userPresence`-protected, unlike the face vault: that would
/// put a Touch ID prompt in front of every single request, and a key that is
/// painful to use is a key somebody moves somewhere easier.
///
/// The key is never logged, never printed, never put in an error message, and
/// never shown back in the settings window — once it is in, MacB will say that
/// it has one and nothing more. There is no way to read it out of the interface,
/// only to replace it or delete it.
@MainActor final class AIKeyStore: ObservableObject {
    /// Whether a key is stored. The key itself is deliberately not published.
    @Published private(set) var hasKey = false
    /// The result of the last check against OpenAI, for the settings window.
    @Published private(set) var status: Status = .idle
    @Published var errorMessage: String?

    enum Status: Equatable {
        case idle
        case checking
        case valid(String)
        case invalid(String)
    }

    private let service: String
    private let account = "openai"

    init(service: String = "dev.hamzababal.MacB.ai") {
        self.service = service
        hasKey = exists()
    }

    // MARK: - Storage

    /// Stores a key, replacing whatever was there.
    ///
    /// Rejects anything that is obviously not a key before it goes near the
    /// Keychain, so a pasted sentence or a stray newline does not become a
    /// stored credential that fails on every request with no explanation.
    @discardableResult
    func save(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AIKeyFormat.looksLikeKey(key) else {
            errorMessage = "Bu bir OpenAI anahtarına benzemiyor. Anahtarlar sk- ile başlar."
            return false
        }
        guard let data = key.data(using: .utf8) else { return false }
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = SecItemAdd(query as CFDictionary, nil)
        guard result == errSecSuccess else {
            // The status code, never the key.
            errorMessage = "Anahtar Keychain'e yazılamadı (\(result))."
            return false
        }
        errorMessage = nil
        status = .idle
        hasKey = true
        return true
    }

    /// Forgets the key. Nothing else in MacB keeps a copy.
    func remove() {
        SecItemDelete(baseQuery() as CFDictionary)
        hasKey = false
        status = .idle
        errorMessage = nil
    }

    /// The stored key, for the one place that makes requests with it.
    ///
    /// Internal rather than published on purpose: nothing should be holding this
    /// in a view, a log line or an observable object.
    func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    /// Whether an item is stored, without reading the secret.
    ///
    /// Asking for attributes only never decrypts the item, so it never puts a
    /// Keychain permission prompt on screen. Reading the key itself at launch
    /// did: after a re-signed build, the app sat blocked in `init`, before any
    /// window or status item existed, until someone answered a prompt they had
    /// no reason to expect.
    private func exists() -> Bool {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    // MARK: - Verification

    /// Asks OpenAI whether the key works.
    ///
    /// The lightest authenticated call there is — a model list — so nothing is
    /// generated, nothing is billed beyond the request itself, and the answer is
    /// a plain yes or no. This is the only thing in MacB that sends the key
    /// anywhere, and it sends it to OpenAI, which is where it is meant to go.
    func verify() async {
        guard let key = read() else {
            status = .invalid("Kayıtlı anahtar yok.")
            return
        }
        status = .checking
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200: status = .valid("Anahtar çalışıyor.")
            case 401: status = .invalid("OpenAI anahtarı reddetti. İptal edilmiş ya da yanlış olabilir.")
            case 429: status = .invalid("Anahtar geçerli ama kota dolu görünüyor.")
            default: status = .invalid("OpenAI \(code) döndürdü.")
            }
        } catch {
            status = .invalid("OpenAI'ye ulaşılamadı: \(error.localizedDescription)")
        }
    }
}
