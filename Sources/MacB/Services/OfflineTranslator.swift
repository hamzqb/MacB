import AppKit
import MacBCore
import NaturalLanguage
import Translation

/// Translates text on the Mac, with the language models macOS downloads for
/// its own Translate feature.
///
/// Nothing leaves the machine and no key is needed, which is why selected text
/// is translated here rather than by the AI: the text someone translates is
/// often exactly the text they would rather not send anywhere.
@MainActor final class OfflineTranslator {
    enum Failure: Error {
        case needsNewerMacOS
        case unknownLanguage
        case sameLanguage
        case notDownloaded(source: String, target: String)
        case unsupported(source: String, target: String)
        case failed(String)

        var message: String {
            switch self {
            case .needsNewerMacOS:
                return "Cihaz üstü çeviri macOS 26 ister."
            case .unknownLanguage:
                return "Metnin dili anlaşılamadı."
            case .sameLanguage:
                return "Metin zaten hedef dilde."
            case .notDownloaded(let source, let target):
                return "\(Self.name(source)) → \(Self.name(target)) dil paketi indirilmemiş. Sistem Ayarları › Genel › Dil ve Bölge › Çeviri Dilleri'nden indir."
            case .unsupported(let source, let target):
                return "\(Self.name(source)) → \(Self.name(target)) çevirisi bu Mac'te desteklenmiyor."
            case .failed(let text):
                return "Çeviri yapılamadı: \(text)"
            }
        }

        var needsDownload: Bool {
            if case .notDownloaded = self { return true }
            return false
        }

        static func name(_ code: String) -> String {
            Locale(identifier: "tr").localizedString(forLanguageCode: code)?.capitalized(with: Locale(identifier: "tr")) ?? code
        }
    }

    struct Result {
        let text: String
        let source: String
        let target: String
    }

    func translate(_ text: String, preferredTarget: String) async -> Swift.Result<Result, Failure> {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let detected = recognizer.dominantLanguage?.rawValue else { return .failure(.unknownLanguage) }
        let source = TranslationDirection.base(detected)
        let target = TranslationDirection.target(source: source, preferred: preferredTarget)
        guard source != target else { return .failure(.sameLanguage) }
        guard #available(macOS 26.0, *) else { return .failure(.needsNewerMacOS) }

        let from = Locale.Language(identifier: source)
        let to = Locale.Language(identifier: target)
        switch await LanguageAvailability().status(from: from, to: to) {
        case .installed: break
        case .supported: return .failure(.notDownloaded(source: source, target: target))
        case .unsupported: return .failure(.unsupported(source: source, target: target))
        @unknown default: return .failure(.unsupported(source: source, target: target))
        }
        do {
            let session = TranslationSession(installedSource: from, target: to)
            let response = try await session.translate(text)
            return .success(Result(text: response.targetText, source: source, target: target))
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    /// The pane where macOS keeps its translation languages.
    static func openLanguageSettings() {
        let candidates = ["x-apple.systempreferences:com.apple.Localization-Settings.extension",
                          "x-apple.systempreferences:com.apple.preference.general"]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }
}
