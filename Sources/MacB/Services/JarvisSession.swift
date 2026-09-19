import AVFoundation
import Combine
import Foundation
import MacBCore

/// What a tool produced for the conversation.
enum JarvisToolOutcome {
    /// A small JSON object the model reads.
    case result(String)
    /// A picture the model should look at, with what the user asked about it.
    case image(jpeg: Data, question: String?)
    /// The user is done talking.
    case end
}

/// Runs Jarvis's tools. Implemented by the app, which owns the services.
@MainActor protocol JarvisToolbox: AnyObject {
    func run(_ tool: JarvisTool, call: JarvisCall) async -> JarvisToolOutcome
    /// One line saying what a tool that needs a yes is about to do.
    func confirmationText(for tool: JarvisTool, call: JarvisCall) -> String
}

/// A live voice conversation with the Realtime API.
///
/// While a session is open the microphone streams to OpenAI — that is what a
/// live, interruptible voice needs, and it is why this is a separate thing from
/// "Sesle sor", which stays on the Mac. It is open only while the Jarvis panel
/// is, it closes itself after a quiet spell or at a hard limit, and macOS shows
/// its microphone indicator the whole time. Nothing is recorded or stored:
/// audio is streamed and played, the transcript lives in memory until the
/// panel closes.
@MainActor final class JarvisSession: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case listening
        case thinking
        case speaking
        case failed(String)
    }

    struct Line: Identifiable, Equatable {
        enum Speaker { case user, jarvis }
        let id = UUID()
        let speaker: Speaker
        var text: String
    }

    struct Confirmation: Identifiable {
        let id = UUID()
        let tool: JarvisTool
        let text: String
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lines: [Line] = []
    @Published private(set) var activity: String?
    @Published private(set) var confirmation: Confirmation?
    @Published private(set) var inputLevel: Double = 0
    @Published private(set) var outputLevel: Double = 0

    weak var toolbox: JarvisToolbox?
    /// Called when the conversation ends by itself (goodbye, quiet, limit).
    var onEnded: (() -> Void)?

    private let keys: AIKeyStore
    private let memory: JarvisMemoryStore
    private let voice: () -> JarvisVoice
    private let model: () -> String
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var audio: JarvisAudio?
    private var audioObserver: NSObjectProtocol?
    private var confirmationReply: CheckedContinuation<Bool, Never>?
    private var idleTimer: Timer?
    private var limitTimer: Timer?
    private var connectTimer: Timer?

    /// Which conversation this is. Anything that awaits — a tool, a timer —
    /// checks it afterwards, so work begun in one conversation can never
    /// touch the next.
    private var generation = 0
    private var toolsRunning = 0
    /// The server is producing a response right now.
    private var responseActive = false
    /// A new response began; the next words start a new line.
    private var startNewLine = true
    /// Replies the user talked over. Audio for them still in flight is dropped.
    private var cutItems: Set<String> = []
    /// Set once text written by someone else — a page, the screen, a
    /// selection, an invitation — has entered the conversation.
    private var hasReadOutsideContent = false
    /// Set once the user's own private material has.
    private var hasReadPrivateContent = false

    /// A conversation nobody speaks in closes after this long.
    private static let quietLimit: TimeInterval = 90
    /// No conversation stays open longer than this, whatever happens.
    private static let hardLimit: TimeInterval = 20 * 60
    private static let connectLimit: TimeInterval = 15
    private static let maxLines = 12

    init(keys: AIKeyStore, memory: JarvisMemoryStore, voice: @escaping () -> JarvisVoice,
         model: @escaping () -> String) {
        self.keys = keys
        self.memory = memory
        self.voice = voice
        self.model = model
    }

    var isActive: Bool {
        switch state {
        case .idle, .failed: return false
        default: return true
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isActive else { return }
        generation += 1
        let current = generation
        lines = []
        activity = nil
        hasReadOutsideContent = false
        hasReadPrivateContent = false
        cutItems = []
        responseActive = false
        startNewLine = true
        memory.reload()
        guard let key = keys.read() else { return fail(AIAssistantService.missingKeyMessage) }
        guard let url = JarvisProtocol.url(model: model()) else { return fail("Model adı geçersiz.") }
        state = .connecting
        connectTimer = Timer.scheduledTimer(withTimeInterval: Self.connectLimit, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == current, self.state == .connecting else { return }
                self.fail("Bağlantı kurulamadı. Model adını ve anahtarı kontrol et.")
            }
        }
        limitTimer = Timer.scheduledTimer(withTimeInterval: Self.hardLimit, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.end()
            }
        }
        Task { [weak self] in
            guard let self else { return }
            guard await Self.microphoneAllowed() else {
                guard self.generation == current else { return }
                return self.fail("Mikrofon izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Mikrofon'dan MacB'yi aç.")
            }
            guard self.generation == current, self.state == .connecting else { return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 20
            let socket = URLSession.shared.webSocketTask(with: request)
            socket.maximumMessageSize = 16 * 1024 * 1024
            self.socket = socket
            socket.resume()
            self.send(JarvisProtocol.sessionUpdate(voice: self.voice(), now: Date(),
                                                   userName: NSFullUserName().split(separator: " ").first.map(String.init),
                                                   memory: self.memory.facts))
            self.receiver = Task { [weak self] in await self?.receive(from: socket, generation: current) }
        }
    }

    /// Ends the conversation. Everything said is forgotten when the panel goes.
    func stop() {
        generation += 1
        confirmationReply?.resume(returning: false)
        confirmationReply = nil
        confirmation = nil
        for timer in [idleTimer, limitTimer, connectTimer] { timer?.invalidate() }
        idleTimer = nil; limitTimer = nil; connectTimer = nil
        receiver?.cancel(); receiver = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        stopAudio()
        inputLevel = 0; outputLevel = 0
        activity = nil
        toolsRunning = 0
        responseActive = false
        if isActive { state = .idle }
    }

    /// Something typed instead of said.
    func say(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, socket != nil, isActive else { return }
        interruptPlayback()
        cancelActiveResponse()
        append(.user, trimmed)
        send(JarvisProtocol.text(trimmed))
        send(JarvisProtocol.createResponse)
        state = .thinking
        touch()
    }

    func answerConfirmation(_ allowed: Bool) {
        confirmation = nil
        confirmationReply?.resume(returning: allowed)
        confirmationReply = nil
    }

    // MARK: - Socket

    private func send(_ object: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    private func receive(from socket: URLSessionWebSocketTask, generation current: Int) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                guard generation == current else { return }
                let text: String
                switch message {
                case .string(let string): text = string
                case .data(let data): text = String(decoding: data, as: UTF8.self)
                @unknown default: continue
                }
                handle(JarvisProtocol.event(from: text))
            } catch {
                guard !Task.isCancelled, generation == current else { return }
                let code = (socket.response as? HTTPURLResponse)?.statusCode
                switch code {
                case 401: fail("OpenAI anahtarı reddetti.")
                case 403, 404: fail("Bu anahtarla \(model()) modeline erişilemiyor.")
                case 429: fail("Kota ya da hız sınırı doldu.")
                default: fail("Bağlantı koptu: \(error.localizedDescription)")
                }
                return
            }
        }
    }

    private func handle(_ event: JarvisEvent) {
        switch event {
        case .sessionReady:
            guard state == .connecting else { return }
            connectTimer?.invalidate(); connectTimer = nil
            startAudio()
        case .responseStarted:
            responseActive = true
            startNewLine = true
        case .audio(let item, let pcm):
            guard !cutItems.contains(item) else { return }
            if state != .speaking { state = .speaking }
            audio?.play(pcm, item: item)
        case .transcript(let delta):
            if !startNewLine, let last = lines.last, last.speaker == .jarvis {
                lines[lines.count - 1].text += delta
            } else {
                append(.jarvis, delta)
                startNewLine = false
            }
        case .heard(let text):
            append(.user, text)
            startNewLine = true
        case .userStartedSpeaking:
            interruptPlayback()
            if toolsRunning == 0 { state = .listening }
            touch()
        case .responseDone(let calls):
            responseActive = false
            if calls.isEmpty {
                settleAfterSpeaking()
            } else {
                let current = generation
                Task { await self.run(calls, generation: current) }
            }
        case .failed(let message):
            // A rejected event or failed response is shown; the conversation
            // carries on, and goes back to listening rather than hang.
            responseActive = false
            activity = message
            settleAfterSpeaking()
        case .ignored:
            break
        }
    }

    // MARK: - Audio

    private func startAudio() {
        let audio = JarvisAudio()
        audio.onCapture = { [weak self] chunk in
            Task { @MainActor in self?.send(JarvisProtocol.appendAudio(chunk)) }
        }
        audio.onInputLevel = { [weak self] level in
            Task { @MainActor in self?.inputLevel = level }
        }
        audio.onOutputLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.outputLevel = level
                if level == 0 { self.settleAfterSpeaking() }
            }
        }
        do {
            try audio.start()
        } catch {
            return fail("Mikrofon açılamadı: \(error.localizedDescription)")
        }
        self.audio = audio
        // Headphones plugged in or out stop the engine without a word. Start
        // it again on the new device rather than sit there "listening" to
        // nothing.
        audioObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restartAudio() }
        }
        if state == .connecting { state = .listening }
        touch()
    }

    private func restartAudio() {
        guard isActive, audio != nil else { return }
        stopAudio()
        startAudio()
    }

    private func stopAudio() {
        if let audioObserver { NotificationCenter.default.removeObserver(audioObserver) }
        audioObserver = nil
        audio?.stop()
        audio = nil
    }

    /// Back to listening once the voice has actually finished playing, not
    /// when the server finished sending it.
    private func settleAfterSpeaking() {
        guard isActive, state != .connecting, toolsRunning == 0, confirmation == nil, !responseActive else { return }
        if audio?.isSpeaking == true { return }
        if state == .speaking || state == .thinking { state = .listening }
        touch()
    }

    private func interruptPlayback() {
        guard let heard = audio?.interrupt() else { return }
        cutItems.insert(heard.item)
        send(JarvisProtocol.truncate(itemID: heard.item, playedMilliseconds: heard.milliseconds))
    }

    private func cancelActiveResponse() {
        guard responseActive else { return }
        send(JarvisProtocol.cancelResponse)
        responseActive = false
    }

    // MARK: - Tools

    private func run(_ calls: [JarvisCall], generation current: Int) async {
        toolsRunning += 1
        state = .thinking
        defer {
            if generation == current {
                toolsRunning = max(0, toolsRunning - 1)
                activity = nil
            }
        }
        var images: [(Data, String?)] = []
        var ending = false
        for call in calls {
            guard generation == current, isActive else { return }
            guard let tool = call.tool, let toolbox else {
                send(JarvisProtocol.functionOutput(callID: call.callID,
                                                   output: JarvisProtocol.result(["ok": false, "error": "unknown tool"])))
                continue
            }
            if tool.needsConfirmation(afterReadingOutsideContent: hasReadOutsideContent,
                                      privateContent: hasReadPrivateContent) {
                let allowed = await ask(tool, text: toolbox.confirmationText(for: tool, call: call))
                guard generation == current else { return }
                guard allowed else {
                    send(JarvisProtocol.functionOutput(callID: call.callID, output: JarvisProtocol.result(
                        ["ok": false, "declined": true, "note": "The user declined. Do not retry unless they ask."])))
                    continue
                }
            }
            activity = tool.activity
            // Marked before the tool runs: whatever it brings back is already
            // someone else's text by the time anything could act on it.
            if tool.readsOutsideContent { hasReadOutsideContent = true }
            if tool.readsPrivateContent { hasReadPrivateContent = true }
            let outcome = await toolbox.run(tool, call: call)
            guard generation == current else { return }
            switch outcome {
            case .result(let output):
                send(JarvisProtocol.functionOutput(callID: call.callID, output: output))
            case .image(let jpeg, let question):
                send(JarvisProtocol.functionOutput(callID: call.callID, output: JarvisProtocol.result(
                    ["ok": true, "note": "The screenshot follows as the next message."])))
                images.append((jpeg, question))
            case .end:
                send(JarvisProtocol.functionOutput(callID: call.callID, output: JarvisProtocol.result(["ok": true])))
                ending = true
            }
        }
        guard generation == current, isActive else { return }
        // The user may have spoken while the tools ran, and the server may
        // already be answering that; this answer replaces it.
        cancelActiveResponse()
        if ending {
            send(JarvisProtocol.createResponse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self, self.generation == current else { return }
                self.end()
            }
            return
        }
        for (jpeg, question) in images { send(JarvisProtocol.image(jpeg: jpeg, question: question)) }
        send(JarvisProtocol.createResponse)
        touch()
    }

    /// Asks in the panel. One question at a time: a second one waits for the
    /// first rather than silently answering it no.
    private func ask(_ tool: JarvisTool, text: String) async -> Bool {
        let current = generation
        while confirmation != nil {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard generation == current else { return false }
        }
        let pending = Confirmation(tool: tool, text: text)
        confirmation = pending
        return await withCheckedContinuation { continuation in
            confirmationReply = continuation
            // Unanswered is no.
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                guard let self, self.confirmation?.id == pending.id else { return }
                self.answerConfirmation(false)
            }
        }
    }

    // MARK: - Helpers

    private func append(_ speaker: Line.Speaker, _ text: String) {
        lines.append(Line(speaker: speaker, text: text))
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
    }

    /// Something happened; the quiet clock starts again. It only hangs up on
    /// a conversation that is quietly listening; otherwise it looks again
    /// later, and the hard limit catches anything that never settles.
    private func touch() {
        idleTimer?.invalidate()
        let current = generation
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.quietLimit, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == current, self.isActive else { return }
                if self.state == .listening, self.confirmation == nil { self.end() } else { self.touch() }
            }
        }
    }

    private func end() {
        stop()
        onEnded?()
    }

    private func fail(_ message: String) {
        stop()
        state = .failed(message)
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
