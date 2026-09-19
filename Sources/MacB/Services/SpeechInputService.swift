import AVFoundation
import Combine
import Speech

/// Turns speech into text, on the Mac only.
///
/// Recognition is forced on-device: if macOS has no local model for the
/// language, this refuses rather than quietly streaming the microphone to a
/// server. Audio goes from the microphone into the recogniser and nowhere
/// else — it is never written to disk and never sent anywhere. What comes out
/// is text, and only the text is handed on.
@MainActor final class SpeechInputService: ObservableObject {
    enum State: Equatable {
        case idle
        /// Asking for permission or opening the microphone.
        case preparing
        case listening
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    /// 0…1, how loud the microphone is right now. Drives the pulsing mark.
    @Published private(set) var level: Double = 0

    /// Called once, with the final text, when listening ends on its own or is
    /// finished by hand. Not called when it is cancelled or hears nothing.
    var onFinish: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var limitTimer: Timer?
    private var configurationObserver: NSObjectProtocol?

    /// How long a pause ends the question.
    private static let silence: TimeInterval = 1.6
    /// A dictation nobody ends still ends.
    private static let longest: TimeInterval = 45

    var isListening: Bool { state == .listening }
    /// Listening, or about to be.
    var isBusy: Bool { state == .listening || state == .preparing }

    func start(localeIdentifier: String = Locale.current.identifier) {
        guard !isBusy else { return }
        transcript = ""
        state = .preparing
        Task { await begin(localeIdentifier: localeIdentifier) }
    }

    /// Ends listening and hands on what was heard.
    func finish() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        teardown()
        state = .idle
        if !text.isEmpty { onFinish?(text) }
    }

    /// Clears a failure that has been shown, so it does not follow the user
    /// into the next, typed, question.
    func dismissError() {
        if case .failed = state { state = .idle }
    }

    /// Ends listening and forgets what was heard.
    func cancel() {
        teardown()
        transcript = ""
        state = .idle
    }

    private func begin(localeIdentifier: String) async {
        guard await Self.speechAuthorized() else {
            state = .failed("Konuşma tanıma izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Konuşma Tanıma'dan MacB'yi aç.")
            return
        }
        guard await Self.microphoneAuthorized() else {
            state = .failed("Mikrofon izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Mikrofon'dan MacB'yi aç.")
            return
        }
        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            state = .failed("Konuşma tanıma şu an kullanılamıyor.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            state = .failed("Bu dil için cihaz üstü tanıma yok. Sistem Ayarları › Klavye › Dikte'den dili ekleyip indir.")
            return
        }
        // Cancelled while a permission prompt was up.
        guard state == .preparing else { return }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            state = .failed("Mikrofon bulunamadı.")
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format,
                         block: Self.tapBlock(request: request) { [weak self] level in self?.level = level })
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            state = .failed("Mikrofon açılamadı: \(error.localizedDescription)")
            return
        }
        state = .listening
        // Headphones plugged in or unplugged stop the engine without a word;
        // end the question there rather than listen to nothing until the limit.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
        limitTimer = Timer.scheduledTimer(withTimeInterval: Self.longest, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, isFinal, failed in
            self?.handle(text: text, isFinal: isFinal, failed: failed)
        })
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard isListening else { return }
        if let text, !text.isEmpty {
            transcript = text
            silenceTimer?.invalidate()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: Self.silence, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.finish() }
            }
        }
        if isFinal { finish() }
        else if failed {
            if transcript.isEmpty { teardown(); state = .idle } else { finish() }
        }
    }

    private func teardown() {
        // Nothing was ever started: touching `inputNode` now would bring up
        // the audio hardware just to take a tap off it.
        guard request != nil || task != nil || engine.isRunning else { level = 0; return }
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        silenceTimer?.invalidate(); silenceTimer = nil
        limitTimer?.invalidate(); limitTimer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        level = 0
    }

    private nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        // Speech sits around -40…-10 dBFS; map that onto 0…1.
        let decibels = 20 * log10(max(rms, 0.000_01))
        return Double(min(1, max(0, (decibels + 50) / 40)))
    }

    /// Built outside the main actor on purpose: the audio engine calls this on
    /// its own realtime thread, and a closure that inherited main-actor
    /// isolation would trap there.
    private nonisolated static func tapBlock(request: SFSpeechAudioBufferRecognitionRequest,
                                             level report: @escaping @MainActor (Double) -> Void) -> AVAudioNodeTapBlock {
        { [weak request] buffer, _ in
            request?.append(buffer)
            let value = level(of: buffer)
            Task { @MainActor in report(value) }
        }
    }

    /// Same reason: the recogniser answers on a queue of its own.
    private nonisolated static func resultHandler(
        _ report: @escaping @MainActor (String?, Bool, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in report(text, isFinal, failed) }
        }
    }

    private nonisolated static func speechAuthorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    private nonisolated static func microphoneAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
