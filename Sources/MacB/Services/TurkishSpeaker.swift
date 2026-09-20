import AVFoundation
import Foundation

/// macOS reading something out in Turkish.
///
/// The free half of a voice: the Mac has had a speech synthesiser since before
/// any of this, it works with no key and no network, and nothing said through
/// it leaves the machine or costs anything. It is not OpenAI's voice and does
/// not pretend to be — but a sentence spoken badly for nothing is worth more
/// than a sentence spoken beautifully for money nobody meant to spend.
///
/// Shared by the morning briefing and the free voice engine, so there is one
/// answer to "which Turkish voice" and one place that stops it talking.
@MainActor final class TurkishSpeaker: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    /// A rough level while talking, so the island's waveform has something to
    /// move to. The synthesiser reports no meter, so this is the shape of
    /// speech rather than its loudness — honest enough for a five-bar hint.
    @Published private(set) var level: Double = 0

    /// Called when the voice stops, whether it finished or was cut off.
    var onFinish: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var levelTimer: Timer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { onFinish?(); return }
        stop(notify: false)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.turkishVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        isSpeaking = true
        startLevels()
        synthesizer.speak(utterance)
    }

    func stop() { stop(notify: true) }

    private func stop(notify: Bool) {
        levelTimer?.invalidate()
        levelTimer = nil
        level = 0
        let wasSpeaking = isSpeaking || synthesizer.isSpeaking
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
        if notify && wasSpeaking { onFinish?() }
    }

    /// The best Turkish voice installed, preferring the higher-quality ones the
    /// user may have downloaded.
    static func turkishVoice() -> AVSpeechSynthesisVoice? {
        let turkish = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") }
        return turkish.first { $0.quality == .premium }
            ?? turkish.first { $0.quality == .enhanced }
            ?? turkish.first
            ?? AVSpeechSynthesisVoice(language: "tr-TR")
    }

    /// Whether this Mac can speak Turkish at all. Without a voice the free
    /// engine can still answer in writing, and says so rather than going quiet.
    static var hasTurkishVoice: Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix("tr") }
    }

    private func startLevels() {
        levelTimer?.invalidate()
        let started = Date()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1 / 15, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, self.isSpeaking else { timer.invalidate(); return }
                let seconds = Date().timeIntervalSince(started)
                self.level = 0.45 + 0.35 * abs(sin(seconds * 6.2)) * abs(sin(seconds * 2.3))
            }
        }
    }
}

extension TurkishSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    @MainActor private func finished() {
        levelTimer?.invalidate()
        levelTimer = nil
        level = 0
        guard isSpeaking else { return }
        isSpeaking = false
        onFinish?()
    }
}
