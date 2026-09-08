import Foundation
import Combine
import LocalAuthentication

/// Uses the system authentication sheet; no password or biometric data enters MacB.
@MainActor final class BiometricAuthService: ObservableObject {
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isAuthenticated = false
    @Published var errorMessage: String?
    private var context: LAContext?
    private var generation = 0

    func authenticate(completion: ((Bool) -> Void)? = nil) {
        guard !isAuthenticating else { return }
        let context = LAContext()
        context.localizedCancelTitle = "Vazgeç"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            errorMessage = "Sistem doğrulaması kullanılamıyor. Mac oturumunun güvenlik ayarlarını kontrol et."
            completion?(false)
            return
        }
        self.context = context
        isAuthenticating = true
        isAuthenticated = false
        errorMessage = nil
        generation += 1
        let token = generation
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "MacB’de korunan içeriği açmak için kimliğini doğrula.") { [weak self] success, error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.isAuthenticating = false
                self.isAuthenticated = success
                self.context = nil
                if !success, let error = error as? LAError,
                   error.code != .userCancel && error.code != .appCancel && error.code != .systemCancel {
                    self.errorMessage = "Kimlik doğrulanamadı. Tekrar deneyebilirsin."
                }
                completion?(success)
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
