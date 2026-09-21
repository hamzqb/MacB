import AVFoundation
import Foundation
import MacBCore

/// Hearing a voice before choosing it, and the Gemini voices themselves.
///
/// A list of voice names tells nobody how any of them sounds. Every picker
/// gets a play button, and what each one costs is plain:
/// - a Mac voice is spoken by the Mac, free and offline;
/// - a Gemini voice is fetched once on the free tier and kept;
/// - an OpenAI voice is fetched once from the speech endpoint — about a tenth
///   of a cent — and kept, so listening again is free.
///
/// Samples are kept in Application Support. They are audio of a fixed
/// sentence, not of anything the user said.
@MainActor final class VoiceStudio: NSObject, ObservableObject {
    static let shared = VoiceStudio()

    /// The voice whose sample is loading or playing, by tag.
    @Published private(set) var active: String?
    @Published private(set) var errorMessage: String?

    private let keys = AIKeyStore()
    private var player: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()
    private var task: Task<Void, Never>?

    /// Who the sample greets: the first name on this Mac's account.
    private var userName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    }

    private var sampleText: String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = name.isEmpty ? "Selam!" : "Selam \(name)!"
        return "\(greeting) Ben MacB. Bugün hava güzel, iki toplantın var; istersen hemen başlayalım."
    }

    // MARK: - Previews

    func previewSystem(identifier: String) {
        stop()
        let utterance = AVSpeechUtterance(string: sampleText)
        utterance.voice = TurkishSpeaker.voice(identifier: identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        active = "system:" + identifier
        synthesizer.speak(utterance)
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if self?.active == "system:" + identifier { self?.active = nil }
        }
    }

    func previewGemini(_ voice: GeminiSpeech.Voice) {
        preview(tag: voice.tag, file: "gemini-\(voice.name)") { [sampleText] in
            await Self.geminiWAV(text: sampleText, voice: voice)
        }
    }

    func previewOpenAI(_ voice: JarvisVoice) {
        preview(tag: "openai:" + voice.rawValue, file: "openai-\(voice.rawValue)") { [sampleText, keys] in
            await Self.openAIWAV(text: sampleText, voice: voice, keys: keys)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        active = nil
    }

    private func preview(tag: String, file: String, fetch: @escaping () async -> Data?) {
        if active == tag { stop(); return }
        stop()
        errorMessage = nil
        active = tag
        // The name is part of the sentence, so it is part of the file name.
        let url = Self.cacheFolder.appendingPathComponent("\(file)-\(Self.stableHash(sampleText)).wav")
        task = Task { [weak self] in
            var data = try? Data(contentsOf: url)
            if data == nil {
                data = await fetch()
                if let data { try? data.write(to: url, options: .atomic) }
            }
            guard let self, !Task.isCancelled, self.active == tag else { return }
            guard let data, self.play(data) else {
                self.errorMessage = "Örnek alınamadı; anahtar ya da bağlantı sorunu olabilir."
                self.active = nil
                return
            }
        }
    }

    @discardableResult
    private func play(_ data: Data) -> Bool {
        guard let player = try? AVAudioPlayer(data: data) else { return false }
        player.delegate = self
        self.player = player
        return player.play()
    }

    // MARK: - Network

    /// Speech from Gemini as WAV, trying the newer model first.
    static func geminiWAV(text: String, voice: GeminiSpeech.Voice) async -> Data? {
        guard let key = AIKeyStore().read(.gemini) else { return nil }
        for model in GeminiSpeech.models {
            var request = URLRequest(url: GeminiSpeech.url(model: model))
            request.httpMethod = "POST"
            // A preview model can stall for twenty seconds; better the next one.
            request.timeoutInterval = 8
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: GeminiSpeech.requestBody(text: text, voice: voice))
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let pcm = GeminiSpeech.audio(inResponse: data) else { continue }
            return GeminiSpeech.wav(fromPCM: pcm)
        }
        return nil
    }

    /// A sample of a live voice, from OpenAI's speech endpoint. The live
    /// conversation uses the same voices, so this is how it will sound.
    private static func openAIWAV(text: String, voice: JarvisVoice, keys: AIKeyStore) async -> Data? {
        guard let key = keys.read(.openAI) else { return nil }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": "gpt-4o-mini-tts", "voice": voice.rawValue, "input": text,
                                   "response_format": "wav",
                                   "instructions": "Samimi, sıcak ve doğal Türkçe konuş."]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        return data
    }

    // MARK: - Files

    private static var cacheFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("MacB/VoicePreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Same text, same name, every launch — `hashValue` is seeded per process.
    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 36)
    }
}

extension VoiceStudio: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.player = nil
            self.active = nil
        }
    }
}
