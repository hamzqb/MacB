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

    /// The voice the user picked, by identifier. Empty means "the best one
    /// installed", which is what somebody who has never opened the picker
    /// means.
    var preferredVoiceIdentifier: () -> String = { "" }

    func speak(_ text: String) {
        speak(lines: [text])
    }

    /// Several lines, with a breath between them.
    ///
    /// The briefing used to be joined with spaces and handed over as one
    /// string, and a synthesiser given one string reads it as one sentence —
    /// no pause between the greeting and the weather, no pause before the
    /// battery, everything at one pitch. That flat run-on is most of what makes
    /// a built-in voice sound like a machine. One utterance per line, with a
    /// short delay before each, costs nothing and is most of the fix.
    func speak(lines: [String]) {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { onFinish?(); return }
        stop(notify: false)
        let voice = Self.voice(identifier: preferredVoiceIdentifier())
        isSpeaking = true
        startLevels()
        for (index, line) in cleaned.enumerated() {
            let utterance = AVSpeechUtterance(string: line)
            utterance.voice = voice
            // Slightly under the default: the Turkish voices run fast enough
            // that the ends of words run together at full rate.
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
            utterance.pitchMultiplier = 1.02
            utterance.preUtteranceDelay = index == 0 ? 0 : 0.28
            utterance.postUtteranceDelay = 0.08
            synthesizer.speak(utterance)
        }
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
        let turkish = installedTurkishVoices()
        return turkish.first { $0.quality == .premium }
            ?? turkish.first { $0.quality == .enhanced }
            ?? turkish.first
            ?? AVSpeechSynthesisVoice(language: "tr-TR")
    }

    /// A particular voice by identifier, falling back to the best one when the
    /// chosen one has been removed — a voice can be deleted in System Settings
    /// long after it was picked here.
    static func voice(identifier: String) -> AVSpeechSynthesisVoice? {
        guard !identifier.isEmpty,
              let chosen = installedTurkishVoices().first(where: { $0.identifier == identifier })
        else { return turkishVoice() }
        return chosen
    }

    /// Every Turkish voice on this Mac, best first, so a picker reads as a
    /// ranking rather than an alphabet.
    static func installedTurkishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("tr") }
            .sorted { rank($0) > rank($1) }
    }

    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }

    /// A name somebody recognises, with the quality spelled out: "Cem —
    /// gelişmiş" says more about how it will sound than "Cem (Enhanced)".
    static func title(for voice: AVSpeechSynthesisVoice) -> String {
        let name = voice.name
            .replacingOccurrences(of: " (Enhanced)", with: "")
            .replacingOccurrences(of: " (Premium)", with: "")
        switch voice.quality {
        case .premium: return name + " — en iyi"
        case .enhanced: return name + " — gelişmiş"
        default: return name + " — basit"
        }
    }

    /// Whether this Mac has only the compact voices, which are the ones that
    /// sound like a machine. There is a better one to download and it is free.
    static var hasOnlyBasicVoices: Bool {
        let turkish = installedTurkishVoices()
        return !turkish.isEmpty && !turkish.contains { $0.quality != .default }
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
