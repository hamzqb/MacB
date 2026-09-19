import AVFoundation
import MacBCore

/// Microphone in, voice out, for a live conversation.
///
/// One engine with Apple's voice processing switched on, so the Mac's own
/// speakers are cancelled out of the microphone — without it Jarvis hears
/// itself and interrupts its own sentences. Captured audio is converted to
/// 24 kHz mono 16-bit PCM and handed on in ~100 ms chunks; nothing is kept or
/// written anywhere. Replies are queued on a player node, and the amount of
/// each reply actually heard is tracked so an interruption can tell the server
/// where the user cut in.
///
/// Callbacks arrive on the audio thread. The state they share is behind a lock.
final class JarvisAudio: @unchecked Sendable {
    /// ~100 ms of captured speech, ready to send.
    var onCapture: (@Sendable (Data) -> Void)?
    /// 0…1 loudness of the microphone, for the orb.
    var onInputLevel: (@Sendable (Double) -> Void)?
    /// 0…1 loudness of the voice being played, for the orb.
    var onOutputLevel: (@Sendable (Double) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: Double(JarvisProtocol.sampleRate),
                                               channels: 1, interleaved: false)!
    private let captureFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                              sampleRate: Double(JarvisProtocol.sampleRate),
                                              channels: 1, interleaved: true)!
    private let lock = NSLock()
    private var pendingCapture = Data()
    private var queuedBuffers = 0
    /// Milliseconds heard of the reply currently playing.
    private var playedMilliseconds: [String: Int] = [:]
    private var currentItem: String?
    /// Bumped on every flush, so callbacks for buffers that were thrown away
    /// do not count as heard.
    private var generation = 0
    private(set) var isRunning = false

    private static let chunkBytes = JarvisProtocol.sampleRate * 2 / 10

    func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        // Echo cancellation. Has to be set before the engine starts, and it
        // applies to the output of the same engine, which is why the voice
        // plays through this engine and not a separate player.
        try input.setVoiceProcessingEnabled(true)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: captureFormat) else {
            throw NSError(domain: "MacB.Jarvis", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Mikrofon biçimi desteklenmiyor."])
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat,
                         block: Self.tapBlock(owner: self, converter: converter, target: captureFormat))
        engine.prepare()
        try engine.start()
        player.play()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        lock.withLock {
            pendingCapture.removeAll()
            queuedBuffers = 0
            generation += 1
            playedMilliseconds.removeAll()
            currentItem = nil
        }
    }

    /// Whether any of a reply is still waiting to be heard.
    var isSpeaking: Bool { lock.withLock { queuedBuffers > 0 } }

    /// Queues part of a reply.
    func play(_ pcm: Data, item: String) {
        guard isRunning else { return }
        let samples = JarvisProtocol.floats(fromPCM16: pcm)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        let duration = JarvisProtocol.milliseconds(ofPCM16Bytes: pcm.count)
        let peak = Double(samples.reduce(0) { max($0, abs($1)) })
        let ticket: Int = lock.withLock {
            queuedBuffers += 1
            if currentItem != item { currentItem = item; playedMilliseconds[item] = 0 }
            return generation
        }
        onOutputLevel?(min(1, peak * 1.4))
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            let finished: Bool = self.lock.withLock {
                guard ticket == self.generation else { return false }
                self.queuedBuffers = max(0, self.queuedBuffers - 1)
                self.playedMilliseconds[item, default: 0] += duration
                return self.queuedBuffers == 0
            }
            if finished { self.onOutputLevel?(0) }
        }
    }

    /// Stops the voice at once and says how much of which reply was heard.
    func interrupt() -> (item: String, milliseconds: Int)? {
        let heard: (String, Int)? = lock.withLock {
            defer {
                generation += 1
                queuedBuffers = 0
                currentItem = nil
            }
            guard let item = currentItem, queuedBuffers > 0 else { return nil }
            return (item, playedMilliseconds[item] ?? 0)
        }
        player.stop()
        player.play()
        onOutputLevel?(0)
        return heard
    }

    // MARK: - Capture

    fileprivate func captured(_ data: Data, level: Double) {
        onInputLevel?(level)
        let chunk: Data? = lock.withLock {
            pendingCapture.append(data)
            guard pendingCapture.count >= Self.chunkBytes else { return nil }
            defer { pendingCapture.removeAll(keepingCapacity: true) }
            return pendingCapture
        }
        if let chunk { onCapture?(chunk) }
    }

    /// Built outside any actor: the engine calls it on its realtime thread.
    private static func tapBlock(owner: JarvisAudio, converter: AVAudioConverter,
                                 target: AVAudioFormat) -> AVAudioNodeTapBlock {
        { [weak owner] buffer, _ in
            guard let owner else { return }
            let ratio = target.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, output.frameLength > 0, let samples = output.int16ChannelData?[0] else { return }
            let count = Int(output.frameLength)
            var peak: Int32 = 0
            for index in 0..<count { peak = max(peak, abs(Int32(samples[index]))) }
            let data = Data(bytes: samples, count: count * 2)
            owner.captured(data, level: min(1, Double(peak) / 12_000))
        }
    }
}
