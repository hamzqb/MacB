import Foundation
import Combine
@preconcurrency import LocalAuthentication

/// Uses the system authentication sheet; no password or biometric data enters MacB.
@MainActor final class BiometricAuthService: ObservableObject {
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isAuthenticated = false
    @Published var errorMessage: String?
    private var context: LAContext?
    private var generation = 0

    func authenticate(reason: String = "MacB’de korunan içeriği açmak için kimliğini doğrula.",
                      completion: ((Bool) -> Void)? = nil) {
        evaluate(reason: reason, returnContext: false) { success, _ in completion?(success) }
    }

    /// Returns ownership of one evaluated context for an immediate protected
    /// Keychain operation. All ordinary boolean authentication paths invalidate
    /// their context before completing.
    func authenticateForKeychain(reason: String) async -> LAContext? {
        await withCheckedContinuation { continuation in
            evaluate(reason: reason, returnContext: true) { success, context in
                continuation.resume(returning: success ? context : nil)
            }
        }
    }

    private func evaluate(reason: String, returnContext: Bool,
                          completion: @escaping (Bool, LAContext?) -> Void) {
        guard !isAuthenticating else {
            completion(false, nil)
            return
        }
        context?.invalidate()
        context = nil
        let context = LAContext()
        context.localizedCancelTitle = "Vazgeç"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            errorMessage = "Sistem doğrulaması kullanılamıyor. Mac oturumunun güvenlik ayarlarını kontrol et."
            context.invalidate()
            completion(false, nil)
            return
        }
        self.context = context
        isAuthenticating = true
        isAuthenticated = false
        errorMessage = nil
        generation += 1
        let token = generation
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: reason) { [weak self] success, error in
            Task { @MainActor in
                guard let self else {
                    context.invalidate()
                    completion(false, nil)
                    return
                }
                guard self.generation == token else {
                    context.invalidate()
                    completion(false, nil)
                    return
                }
                self.isAuthenticating = false
                self.isAuthenticated = success
                self.context = nil
                if !success, let error = error as? LAError,
                   error.code != .userCancel && error.code != .appCancel && error.code != .systemCancel {
                    self.errorMessage = "Kimlik doğrulanamadı. Tekrar deneyebilirsin."
                }
                let grantedContext = success && returnContext ? context : nil
                if grantedContext == nil { context.invalidate() }
                completion(success, grantedContext)
            }
        }
    }

    func reset() {
        generation += 1
        context?.invalidate()
        context = nil
        isAuthenticating = false
        isAuthenticated = false
        errorMessage = nil
    }
}
