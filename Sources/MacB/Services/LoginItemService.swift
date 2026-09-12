import Foundation
import ServiceManagement

/// Starts MacB with the Mac, using the login item macOS itself manages.
///
/// No launchd plist is written and nothing is copied anywhere. `SMAppService`
/// registers this exact bundle, so the entry appears under Login Items in
/// System Settings and the user can revoke it there without MacB's help. That
/// also means macOS, not MacB, owns the truth: the switch reads the real status
/// rather than a preference that might disagree with it.
@MainActor final class LoginItemService: ObservableObject {
    @Published private(set) var isEnabled = false
    /// Why the last attempt did not take, in words, or nothing.
    @Published private(set) var errorMessage: String?
    /// Set when macOS is waiting for the user to allow the item themselves.
    @Published private(set) var needsApproval = false

    private let service = SMAppService.mainApp

    init() { refresh() }

    func refresh() {
        switch service.status {
        case .enabled:
            isEnabled = true; needsApproval = false
        case .requiresApproval:
            // macOS knows about the item but the user has switched it off, or
            // has not answered yet. Either way MacB must not override them.
            isEnabled = false; needsApproval = true
        default:
            isEnabled = false; needsApproval = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try service.register()
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            errorMessage = enabled
                ? "Açılışta başlatma ayarlanamadı: \(error.localizedDescription)"
                : "Açılışta başlatma kapatılamadı: \(error.localizedDescription)"
        }
        refresh()
    }

    /// Opens the system list, for when macOS is waiting on the user.
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
