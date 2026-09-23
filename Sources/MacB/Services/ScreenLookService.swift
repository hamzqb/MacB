import AppKit
import Foundation
import ScreenCaptureKit

/// Takes one picture of the window the user is looking at, when they ask a
/// question about it.
///
/// One window, not the screen: whatever else is open — a message, a bank page,
/// another person's work — is not in the picture. MacB's own windows are never
/// the subject, the picture is never written to disk, and it exists only for
/// the length of the request it is attached to.
enum ScreenLookService {
    enum Failure: LocalizedError {
        case noWindow
        case denied

        var errorDescription: String? {
            switch self {
            case .noWindow: return "Bakılacak bir pencere bulunamadı."
            case .denied: return "Ekran kaydı izni yok. Sistem Ayarları → Gizlilik ve Güvenlik → Ekran Kaydı'ndan MacB'ye izin ver."
            }
        }
    }

    /// A JPEG of the frontmost window of the frontmost application, and its
    /// name so the answer can say what it looked at.
    static func captureFrontmostWindow(maximumWidth: CGFloat = 1_600) async throws -> (jpeg: Data, appName: String) {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw Failure.denied
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let candidates = content.windows.filter { window in
            window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                && window.frame.width > 200 && window.frame.height > 150
                && window.isOnScreen
        }
        let window = candidates.first { $0.owningApplication?.processID == frontmost }
            ?? candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        guard let window else { throw Failure.noWindow }

        let configuration = SCStreamConfiguration()
        let scale = min(1, maximumWidth / max(1, window.frame.width))
        configuration.width = Int(window.frame.width * scale * 2)
        configuration.height = Int(window.frame.height * scale * 2)
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            throw Failure.noWindow
        }
        let name = window.owningApplication?.applicationName ?? "pencere"
        return (data, name)
    }
}
