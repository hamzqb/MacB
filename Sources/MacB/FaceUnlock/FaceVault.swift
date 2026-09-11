import CryptoKit
import Foundation
import LocalAuthentication
import MacBCore
import Security

enum FaceVaultError: LocalizedError {
    case locked
    case keychain(OSStatus)
    case corrupted

    var errorDescription: String? {
        switch self {
        case .locked:
            return "Kasa kilitli. Touch ID veya Mac parolanla aç."
        case .keychain(let status):
            if status == errSecMissingEntitlement {
                return "Güvenli Anahtar Zinciri kaydı oluşturulamadı. İmzalı MacB sürümünü kullanıp tekrar dene."
            }
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return "Anahtar zinciri hatası: \(message)"
        case .corrupted:
            return "Yüz kaydı okunamadı. Kayıt bozulmuş olabilir."
        }
    }
}

/// The AES key behind the face vault.
///
/// The key is a Keychain item guarded by `userPresence`, so reading it costs a
/// Touch ID or Mac-password check no matter which process asks. The caller
/// hands over the `LAContext` it already authenticated, which satisfies that
/// guard without raising a second sheet for the same action. MacB never
/// receives the password or the biometric data behind either prompt.
///
/// While a session is open the key is held in memory only, and re-locking drops it.
@MainActor final class FaceVaultKey: ObservableObject {
    @Published private(set) var isUnlocked = false

    private var key: SymmetricKey?
    private let service = "dev.hamzababal.MacB.faceVault"
    /// The account name is the schema marker: only keys written by this build
    /// with the policy below are ever treated as protected.
    private let protectedAccount = "vault-key-user-presence-v2"
    private let legacyAccount = "vault-key"

    /// Opens the in-memory session using the context the caller authenticated.
    func unlock(context: LAContext?) throws {
        if key != nil { isUnlocked = true; return }
        guard let context else { throw FaceVaultError.locked }
        do {
            key = try loadKey(account: protectedAccount, context: context)
        } catch FaceVaultError.keychain(let status) where status == errSecItemNotFound {
            do {
                _ = try loadKey(account: legacyAccount, context: nil)
                key = try migrateLegacyKey(context: context)
            } catch FaceVaultError.keychain(let legacyStatus) where legacyStatus == errSecItemNotFound {
                key = try createKey(context: context)
            }
        }
        isUnlocked = key != nil
    }

    func lock() {
        key = nil
        isUnlocked = false
    }

    /// Removes the key entirely. Any ciphertext left behind becomes unreadable,
    /// which is the point: deleting the enrollment must not be recoverable.
    func destroy() {
        SecItemDelete(baseQuery(account: protectedAccount) as CFDictionary)
        SecItemDelete(baseQuery(account: legacyAccount) as CFDictionary)
        lock()
    }

    func seal(_ plaintext: Data) throws -> Data {
        guard let key else { throw FaceVaultError.locked }
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw FaceVaultError.corrupted }
        return combined
    }

    func open(_ ciphertext: Data) throws -> Data {
        guard let key else { throw FaceVaultError.locked }
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw FaceVaultError.corrupted
        }
    }

    // MARK: - Keychain

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func loadKey(account: String, context: LAContext?) throws -> SymmetricKey {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        if let context { query[kSecUseAuthenticationContext as String] = context }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw FaceVaultError.keychain(status)
        }
        return SymmetricKey(data: data)
    }

    /// Copy first, verify the protected copy, and delete the legacy item last.
    /// A failed migration leaves the old enrollment untouched and reports an
    /// error; it never silently weakens the security policy.
    private func migrateLegacyKey(context: LAContext) throws -> SymmetricKey {
        let legacy = try loadKey(account: legacyAccount, context: nil)
        SecItemDelete(baseQuery(account: protectedAccount) as CFDictionary)
        do {
            try store(legacy, account: protectedAccount, context: context)
            let verified = try loadKey(account: protectedAccount, context: context)
            guard keyData(verified) == keyData(legacy) else { throw FaceVaultError.corrupted }
            SecItemDelete(baseQuery(account: legacyAccount) as CFDictionary)
            return verified
        } catch {
            SecItemDelete(baseQuery(account: protectedAccount) as CFDictionary)
            throw error
        }
    }

    private func createKey(context: LAContext) throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        SecItemDelete(baseQuery(account: protectedAccount) as CFDictionary)
        try store(key, account: protectedAccount, context: context)
        return key
    }

    /// Writes the key behind `userPresence`, on this device only.
    private func store(_ key: SymmetricKey, account: String, context: LAContext) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error) else {
            throw FaceVaultError.keychain(errSecParam)
        }
        var attributes = commonAttributes(for: key, account: account)
        attributes[kSecAttrAccessControl as String] = access
        attributes[kSecUseAuthenticationContext as String] = context
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw FaceVaultError.keychain(status) }
    }

    private func commonAttributes(for key: SymmetricKey, account: String) -> [String: Any] {
        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        attributes[kSecAttrLabel as String] = "MacB Face Vault"
        attributes[kSecAttrDescription as String] = "Encryption key for local face templates"
        return attributes
    }

    private func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}

/// Encrypted persistence for enrolled identities.
///
/// There is no plaintext path. A locked vault throws instead of returning an
/// empty list, so the UI can tell "not enrolled" from "enrolled but locked".
@MainActor struct SecureFaceStore {
    private let vault: FaceVaultKey

    init(vault: FaceVaultKey) { self.vault = vault }

    private var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("MacB", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A distinct extension so ciphertext can never be mistaken for JSON.
        return directory.appendingPathComponent("face-identities.enc")
    }

    var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    func load() throws -> [FaceIdentity] {
        guard vault.isUnlocked else { throw FaceVaultError.locked }
        guard let ciphertext = try? Data(contentsOf: fileURL) else { return [] }
        let plaintext = try vault.open(ciphertext)
        do {
            return try JSONDecoder().decode([FaceIdentity].self, from: plaintext)
        } catch {
            throw FaceVaultError.corrupted
        }
    }

    func save(_ identities: [FaceIdentity]) throws {
        guard vault.isUnlocked else { throw FaceVaultError.locked }
        let plaintext = try JSONEncoder().encode(identities)
        let ciphertext = try vault.seal(plaintext)
        try ciphertext.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    /// Deletes the file and the key, so nothing recoverable is left behind.
    func destroy() {
        try? FileManager.default.removeItem(at: fileURL)
        vault.destroy()
    }
}
