import Foundation

/// Gemini's speech models: lively, natural Turkish, on the free tier of the
/// key the user already gave MacB.
///
/// The Mac's own Turkish voices are free and private but flat; OpenAI's are
/// lively but billed. These sit between: free, and far more alive than a
/// system voice. The price is privacy — the text goes to Google, which may
/// use free-tier input for training — so they are only used when the user
/// picks one, and the settings say so where the choice is made.
public enum GeminiSpeech {
    /// A prebuilt voice, with the manner Google describes it by.
    public struct Voice: Identifiable, Equatable, Sendable {
        public let name: String
        public let manner: String
        public var id: String { name }
        /// How it is stored in the briefing-voice preference, next to system
        /// voice identifiers.
        public var tag: String { GeminiSpeech.tagPrefix + name }
        public var title: String { "\(name) — \(manner) (Gemini, ücretsiz)" }
    }

    public static let tagPrefix = "gemini:"

    /// A handful with clearly different characters; thirty in a menu is a
    /// list nobody reads.
    public static let voices: [Voice] = [
        Voice(name: "Sadachbia", manner: "canlı"),
        Voice(name: "Puck", manner: "neşeli"),
        Voice(name: "Achird", manner: "samimi"),
        Voice(name: "Sulafat", manner: "sıcak"),
        Voice(name: "Aoede", manner: "ferah"),
        Voice(name: "Kore", manner: "net"),
        Voice(name: "Leda", manner: "genç"),
        Voice(name: "Charon", manner: "bilgilendirici")
    ]

    public static func voice(forTag tag: String) -> Voice? {
        guard tag.hasPrefix(tagPrefix) else { return nil }
        let name = String(tag.dropFirst(tagPrefix.count))
        return voices.first { $0.name == name }
    }

    /// Newest first; the next is tried when one is gone or refuses.
    public static let models = ["gemini-3.1-flash-tts-preview", "gemini-2.5-flash-preview-tts"]

    /// What comes back: 16-bit mono PCM at 24 kHz.
    public static let sampleRate = 24_000

    public static func url(model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    }

    /// The style is asked for in words, as the speech models expect; they
    /// follow the direction rather than read it out.
    public static func requestBody(text: String, voice: Voice) -> [String: Any] {
        let direction = "Samimi, sıcak ve enerjik bir tonla, akıcı ve doğal Türkçe konuş: "
        return [
            "contents": [["parts": [["text": direction + text]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice.name]]]
            ]
        ]
    }

    /// The PCM in a response, or nil.
    public static func audio(inResponse data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = object["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return nil }
        for part in parts {
            if let inline = part["inlineData"] as? [String: Any], let base64 = inline["data"] as? String,
               let pcm = Data(base64Encoded: base64), !pcm.isEmpty {
                return pcm
            }
        }
        return nil
    }

    /// Raw PCM wrapped as a WAV file, which every player on the Mac can open.
    public static func wav(fromPCM pcm: Data, sampleRate: Int = sampleRate) -> Data {
        func little<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        var data = Data("RIFF".utf8)
        data += little(UInt32(36 + pcm.count))
        data += Data("WAVEfmt ".utf8)
        data += little(UInt32(16)) + little(UInt16(1)) + little(UInt16(1))
        data += little(UInt32(sampleRate)) + little(UInt32(sampleRate * 2))
        data += little(UInt16(2)) + little(UInt16(16))
        data += Data("data".utf8) + little(UInt32(pcm.count))
        return data + pcm
    }
}
