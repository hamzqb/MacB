import Foundation

/// Tells a screenshot from any other file that lands in the same folder.
///
/// macOS marks every screenshot it saves with an extended attribute,
/// `kMDItemIsScreenCapture`, before the file is even visible, and that mark is
/// the answer: it does not depend on the system language, the user's naming
/// scheme or a date format, all of which the file name does. The name is only
/// a fallback for a file whose attribute could not be read, and it knows the
/// two languages MacB speaks.
///
/// A name starting with a dot is never a screenshot, whatever it says: that is
/// the temporary file macOS writes first and renames when it is done, and
/// taking it would put a half-written image on the shelf.
public enum ScreenshotDetection {
    public static let attributeName = "com.apple.metadata:kMDItemIsScreenCapture"

    private static let namePrefixes = ["Screenshot", "Screen Shot", "Ekran Resmi", "Ekran Görüntüsü"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "pdf", "gif"]

    /// Whether a new file is a screenshot.
    ///
    /// `hasCaptureAttribute` is nil when the attribute could not be read at all,
    /// in which case the name decides.
    public static func isScreenshot(fileName: String, hasCaptureAttribute: Bool?) -> Bool {
        guard !fileName.hasPrefix(".") else { return false }
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard imageExtensions.contains(ext) || ext == "mov" else { return false }
        if let hasCaptureAttribute { return hasCaptureAttribute }
        return namePrefixes.contains { fileName.hasPrefix($0) }
    }

    /// Where screenshots go: the user's choice in the Screenshot app if there
    /// is one and it still exists, the Desktop otherwise.
    public static func folder(configured: String?, home: URL, exists: (String) -> Bool) -> URL {
        if let configured, !configured.isEmpty {
            let expanded = (configured as NSString).expandingTildeInPath
            if exists(expanded) { return URL(fileURLWithPath: expanded, isDirectory: true) }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }
}
