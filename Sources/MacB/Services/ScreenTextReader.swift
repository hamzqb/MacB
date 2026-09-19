import AppKit
import Foundation
import ScreenCaptureKit
import Vision

/// Reads the words on screen without sending a picture of it anywhere.
///
/// The cheap path. `look_at_screen` sends an image to OpenAI, which costs real
/// money per look and shows them everything that happens to be on the display —
/// a message, a bank balance, a face. This captures the screen, runs Apple's
/// own text recognition on this Mac, throws the image away, and hands back only
/// the text it found. For reading an advertisement, an error dialog, a page of
/// documentation or anything else made of words, it is both cheaper and less
/// revealing, and MacB prefers it.
///
/// The image never touches the disk and never leaves the process. What does
/// leave, when the user allows it, is text — which is still whatever was on
/// screen, so it is confirmed exactly like a screenshot is.
enum ScreenTextReader {
    /// How much text comes back at most. Long enough for a page, short enough
    /// that a wall of text does not become an expensive prompt.
    static let maximumLength = 6_000

    struct Reading {
        var text: String
        /// Lines found, before any clipping.
        var lineCount: Int
        var isTruncated: Bool
        /// Which window's text this is, when one was asked for.
        var source: String?
    }

    enum Failure: LocalizedError {
        case noScreen
        case captureFailed(String)
        case noText

        var errorDescription: String? {
            switch self {
            case .noScreen: return "Ekran bulunamadı."
            case .captureFailed(let message): return message
            case .noText: return "Ekranda okunacak yazı bulunamadı."
            }
        }
    }

    /// Everything readable on the display under the pointer.
    ///
    /// MacB's own windows are left out, so the island does not read itself back
    /// to the model.
    static func read() async throws -> Reading {
        let image = try await capture()
        let lines = try recognise(image)
        guard !lines.isEmpty else { throw Failure.noText }
        let joined = lines.joined(separator: "\n")
        let clipped = String(joined.prefix(maximumLength))
        return Reading(text: clipped, lineCount: lines.count,
                       isTruncated: clipped.count < joined.count, source: nil)
    }

    /// The text in one image. Used by the probe, which checks the recogniser
    /// against a picture it made itself rather than against the user's screen.
    static func read(image: CGImage) throws -> Reading {
        let lines = try recognise(image)
        guard !lines.isEmpty else { throw Failure.noText }
        let joined = lines.joined(separator: "\n")
        let clipped = String(joined.prefix(maximumLength))
        return Reading(text: clipped, lineCount: lines.count,
                       isTruncated: clipped.count < joined.count, source: nil)
    }

    // MARK: - Capture

    private static func capture() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let screenID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == screenID }) ?? content.displays.first else {
            throw Failure.noScreen
        }
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        // Full resolution here, unlike the screenshot path: recognition reads
        // small type far better at native size, and nothing is transmitted, so
        // the pixels cost nothing.
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    // MARK: - Recognition

    /// Apple's text recognition, on this Mac, in Turkish and English.
    ///
    /// Accurate rather than fast: this runs once, when asked, and reading a
    /// word wrongly is worse than taking another moment over it.
    private static func recognise(_ image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["tr-TR", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw Failure.captureFailed(error.localizedDescription)
        }
        let observations = request.results ?? []
        // Top to bottom, then left to right: Vision returns them in no
        // particular order, and text read out of order is worse than no text.
        // Vision's origin is bottom-left, so a larger y is higher up.
        let sorted = observations.sorted { first, second in
            let firstTop = first.boundingBox.maxY, secondTop = second.boundingBox.maxY
            if abs(firstTop - secondTop) > 0.01 { return firstTop > secondTop }
            return first.boundingBox.minX < second.boundingBox.minX
        }
        return sorted.compactMap { $0.topCandidates(1).first?.string }
            .map { turkish($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Turkish's own letters, where recognition returns a lookalike.
    ///
    /// Vision reads "Şu" as "Șu": an S with a comma below (Romanian) rather
    /// than an S with a cedilla (Turkish). They are different characters, so a
    /// search, a comparison or a sentence read aloud all come out wrong. Only
    /// these two pairs are touched — nothing else is rewritten, because
    /// correcting text a user asked to be read is how you end up reporting
    /// something they never saw.
    private static func turkish(_ text: String) -> String {
        guard text.contains("\u{0218}") || text.contains("\u{0219}") else { return text }
        return text
            .replacingOccurrences(of: "\u{0218}", with: "\u{015E}")
            .replacingOccurrences(of: "\u{0219}", with: "\u{015F}")
    }
}
