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
    /// Which engine this conversation is actually running on, and why. The
    /// island shows the free one differently: it is free, not broken.
    @Published private(set) var isFreeEngine = false

    weak var toolbox: JarvisToolbox?
    /// Called when the conversation ends by itself (goodbye, quiet, limit).
    var onEnded: (() -> Void)?

    private let keys: AIKeyStore
    private let memory: JarvisMemoryStore
    private let voice: () -> JarvisVoice
    private let model: () -> String
    private let persona: () -> JarvisPersona
    private let scenarioNames: () -> [String]
    private let cost: AICostMeter?
    private let engineChoice: () -> JarvisEngineChoice
    /// The free half: the Mac's own ear, a free provider's answer, and the
    /// Mac's own voice. Nil only in the probes that never speak.
    private let freeEngine: FreeVoiceEngine?
    private let listener = SpeechInputService()
    private let speaker = TurkishSpeaker()
    /// The free conversation so far, in the provider's own message shape. Kept
    /// in memory for the length of one conversation and never written down.
    private var freeMessages: [[String: Any]] = []
    private var freeObservers: Set<AnyCancellable> = []
    /// The free conversation said goodbye; end it once the voice has finished.
    private var freeIsEnding = false
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
    /// Read-only tools the user has already allowed in this conversation.
    /// This stops “mail again?” loops without letting outside text perform
    /// actions: writing tools never enter this set and the set dies with stop().
    private var allowedReadTools: Set<JarvisTool> = []

    /// A conversation nobody speaks in closes after this long.
    ///
    /// Every second of that silence is billed: an open Realtime session keeps
    /// sending the microphone, and input audio is charged whether or not
    /// anybody said anything. Ninety seconds of nothing cost more than the
    /// question that preceded it, so the wait is short enough to be cheap and
    /// long enough to finish a sentence in.
    private static let quietLimit: TimeInterval = 30
    /// No conversation stays open longer than this, whatever happens.
    ///
    /// Realtime resends the whole conversation on every turn, so a long one
    /// does not cost linearly — it costs by the square. Twenty minutes was a
    /// bill nobody asked for.
    private static let hardLimit: TimeInterval = 6 * 60
    private static let connectLimit: TimeInterval = 15
    private static let maxLines = 12

    init(keys: AIKeyStore, memory: JarvisMemoryStore, cost: AICostMeter? = nil,
         voice: @escaping () -> JarvisVoice,
         persona: @escaping () -> JarvisPersona = { JarvisPersona.defaultPersona },
         scenarioNames: @escaping () -> [String] = { [] },
         engineChoice: @escaping () -> JarvisEngineChoice = { .automatic },
         freeEngine: FreeVoiceEngine? = nil,
         model: @escaping () -> String) {
        self.scenarioNames = scenarioNames
        self.keys = keys
        self.memory = memory
        self.cost = cost
        self.voice = voice
        self.persona = persona
        self.model = model
        self.engineChoice = engineChoice
        self.freeEngine = freeEngine
        listener.onFinish = { [weak self] heard in self?.heardFree(heard) }
        speaker.onFinish = { [weak self] in self?.finishedSpeakingFree() }
    }

    /// Whether the island is showing the line to type into. Off until the user
    /// taps the badge: this is a conversation, and a keyboard sitting there
    /// says otherwise.
    @Published var showsInput = false

    /// Audio captured before the session was ready, so the microphone can be
    /// opened while the socket is still shaking hands instead of after.
    private var pendingAudio: [Data] = []
    private var isSessionReady = false
    private var startedAt: Date?

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
        showsInput = false
        hasReadOutsideContent = false
        hasReadPrivateContent = false
        cutItems = []
        responseActive = false
        startNewLine = true
        memory.reload()
        pendingAudio = []
        isSessionReady = false
        freeIsEnding = false
        startedAt = Date()
        // Which voice this conversation gets. A conversation never fails to
        // start because of money: when the good engine is not available the
        // free one takes over and says so.
        let resolved = JarvisEngineChoice.resolve(choice: engineChoice(),
                                                  hasPaidKey: keys.has(.openAI),
                                                  isOverBudget: cost?.isOverDailyLimit ?? false,
                                                  hasFreeKey: freeEngine?.isAvailable ?? false)
        isFreeEngine = resolved.isFree
        if resolved.isBlocked { return fail(resolved.note ?? Self.missingVoiceKeyMessage) }
        if resolved.isFree { return startFree(generation: current, note: resolved.note) }
        guard let key = keys.read(.openAI) else { return fail(Self.missingVoiceKeyMessage) }
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
        // The socket opens first and the microphone is asked for alongside it.
        // Done one after the other — permission, then handshake, then audio
        // engine — the wait before MacB can hear anything was the sum of all
        // three; now it is the longest of them.
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.maximumMessageSize = 16 * 1024 * 1024
        self.socket = socket
        socket.resume()
        send(JarvisProtocol.sessionUpdate(voice: voice(), now: Date(),
                                          userName: NSFullUserName().split(separator: " ").first.map(String.init),
                                          memory: memory.facts, persona: persona(),
                                          scenarios: scenarioNames()))
        receiver = Task { [weak self] in await self?.receive(from: socket, generation: current) }
        Task { [weak self] in
            guard let self else { return }
            guard await Self.microphoneAllowed() else {
                guard self.generation == current else { return }
                return self.fail("Mikrofon izni yok. Sistem Ayarları › Gizlilik ve Güvenlik › Mikrofon'dan MacB'yi aç.")
            }
            guard self.generation == current, self.isActive else { return }
            self.startAudio()
        }
    }

    static let missingVoiceKeyMessage =
        "Sesli asistan için OpenAI anahtarı gerekiyor. Ayarlar → Araçlar'dan gir."


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
        listener.cancel()
        speaker.stop()
        freeMessages = []
        freeObservers.removeAll()
        allowedReadTools.removeAll()
        hasReadOutsideContent = false
        hasReadPrivateContent = false
        freeIsEnding = false
        stopAudio()
        pendingAudio = []
        isSessionReady = false
        inputLevel = 0; outputLevel = 0
        activity = nil
        toolsRunning = 0
        responseActive = false
        if isActive { state = .idle }
    }

    /// Something typed instead of said.
    func say(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isActive else { return }
        if isFreeEngine {
            listener.cancel()
            speaker.stop()
            append(.user, trimmed)
            askFree(trimmed, generation: generation)
            return
        }
        guard socket != nil else { return }
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
            connectTimer?.invalidate(); connectTimer = nil
            isSessionReady = true
            // Whatever the microphone heard while the handshake was finishing.
            for chunk in pendingAudio { send(JarvisProtocol.appendAudio(chunk)) }
            pendingAudio = []
            if state == .connecting, audio != nil { state = .listening }
            touch()
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
        case .responseDone(let calls, let usage):
            responseActive = false
            cost?.record(provider: .openAI, model: model(), usage: usage,
                         voiceSeconds: startedAt.map { Date().timeIntervalSince($0) } ?? 0)
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
            Task { @MainActor in self?.sendAudio(chunk) }
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
            try audio.startBestAvailable()
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
        if state == .connecting, isSessionReady { state = .listening }
        touch()
    }

    /// Microphone audio, held back until the session exists.
    ///
    /// Capped: if the handshake never finishes, this must not grow into a
    /// recording of the room. Two seconds is enough to keep the start of a
    /// sentence and short enough to be nothing else.
    private func sendAudio(_ chunk: Data) {
        guard isSessionReady else {
            pendingAudio.append(chunk)
            var bytes = pendingAudio.reduce(0) { $0 + $1.count }
            let limit = JarvisProtocol.sampleRate * 2 * 2
            while bytes > limit, !pendingAudio.isEmpty {
                bytes -= pendingAudio.removeFirst().count
            }
            return
        }
        send(JarvisProtocol.appendAudio(chunk))
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

    // MARK: - The free engine

    /// A conversation held entirely without a bill.
    ///
    /// macOS hears, a free provider answers, macOS speaks. It takes turns
    /// rather than sharing one — there is no interrupting a synthesiser
    /// mid-word — and everything that is not the provider's answer happens on
    /// this Mac. The microphone never leaves it: `SpeechInputService` forces
    /// on-device recognition, so what goes out is the sentence, not the sound.
    private func startFree(generation current: Int, note: String?) {
        guard freeEngine?.isAvailable == true else {
            return fail("Ücretsiz mod için ücretsiz bir sağlayıcı anahtarı gerekiyor. Ayarlar \u{203A} Araçlar.")
        }
        state = .connecting
        observeFreeLevels()
        freeMessages = [[
            "role": "system",
            "content": JarvisProtocol.instructions(
                now: Date(),
                userName: NSFullUserName().split(separator: " ").first.map(String.init),
                memory: memory.facts, persona: persona(), scenarios: scenarioNames())
                + Self.freeEngineNote
        ]]
        if let note { append(.jarvis, note) }
        limitTimer = Timer.scheduledTimer(withTimeInterval: Self.hardLimit, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.end()
            }
        }
        listenFree()
    }

    /// What the free engine is told that the live one is not: it is answering
    /// by text and being read aloud, so anything that only works on a screen is
    /// worse than useless here.
    private static let freeEngineNote = """


        You are running in the free mode: what you write is read aloud by the         Mac's own synthesiser. Write one or two spoken sentences, never         Markdown, never a list, never an address or a path. You cannot see the         screen in this mode — say so if asked. You cannot be interrupted, so do         not ask a question and keep talking.
        """

    /// How many times round the tool loop before giving up. A small model that
    /// has called four tools and still not answered is not about to.
    private static let freeToolRounds = 4
    /// The free engine listens on this Mac and costs nothing to leave open, so
    /// it waits longer for somebody to say something than the billed one does.
    private static let freeQuietLimit: TimeInterval = 75

    private func observeFreeLevels() {
        freeObservers.removeAll()
        listener.$level.sink { [weak self] level in
            guard let self, self.isFreeEngine, self.state == .listening else { return }
            self.inputLevel = level
        }.store(in: &freeObservers)
        speaker.$level.sink { [weak self] level in
            guard let self, self.isFreeEngine else { return }
            self.outputLevel = level
        }.store(in: &freeObservers)
        listener.$state.sink { [weak self] state in
            guard let self, self.isFreeEngine, self.isActive else { return }
            if case .failed(let message) = state { self.fail(message) }
        }.store(in: &freeObservers)
    }

    private func listenFree() {
        guard isActive, isFreeEngine else { return }
        state = .listening
        inputLevel = 0
        listener.start(localeIdentifier: "tr-TR")
        touch()
    }

    private func heardFree(_ text: String) {
        guard isActive, isFreeEngine else { return }
        append(.user, text)
        askFree(text, generation: generation)
    }

    private func askFree(_ text: String, generation current: Int) {
        freeMessages.append(["role": "user", "content": text])
        state = .thinking
        inputLevel = 0
        Task { [weak self] in await self?.answerFree(generation: current) }
    }

    private func answerFree(generation current: Int) async {
        guard let engine = freeEngine else { return }
        for _ in 0..<Self.freeToolRounds {
            guard generation == current, isActive else { return }
            do {
                let reply = try await engine.answer(messages: freeMessages)
                guard generation == current, isActive else { return }
                if let provider = engine.provider {
                    cost?.record(provider: provider, model: "", usage: reply.usage)
                }
                if reply.calls.isEmpty {
                    freeMessages.append(["role": "assistant", "content": reply.text])
                    speakFree(JarvisProtocol.plainSpoken(reply.text))
                    return
                }
                freeMessages.append(reply.historyMessage)
                let ending = await runFreeTools(reply.calls, generation: current)
                guard generation == current, isActive else { return }
                if ending {
                    speakFree(JarvisProtocol.plainSpoken(reply.text.isEmpty ? "Görüşürüz." : reply.text))
                    freeIsEnding = true
                    return
                }
                // Trim the tail so a long tool conversation cannot grow without
                // bound; the system message always stays.
                if freeMessages.count > 24 {
                    freeMessages = [freeMessages[0]] + freeMessages.suffix(20)
                }
            } catch {
                guard generation == current, isActive else { return }
                return fail(error.localizedDescription)
            }
        }
        guard generation == current, isActive else { return }
        speakFree("Bunu beceremedim.")
    }

    private func runFreeTools(_ calls: [JarvisCall], generation current: Int) async -> Bool {
        var ending = false
        toolsRunning += 1
        defer {
            if generation == current {
                toolsRunning = max(0, toolsRunning - 1)
                activity = nil
            }
        }
        for call in calls {
            guard generation == current, isActive else { return false }
            guard let tool = call.tool, let toolbox else {
                freeMessages.append(AIChatStream.toolResultMessage(
                    callID: call.callID,
                    output: JarvisProtocol.result(["ok": false, "error": "unknown tool"])))
                continue
            }
            // The same gate as the live engine, and for the same reason: a free
            // model is not a more trusted one.
            if needsUserApproval(for: tool, call: call) {
                let allowed = await ask(tool, text: toolbox.confirmationText(for: tool, call: call))
                guard generation == current else { return false }
                guard allowed else {
                    freeMessages.append(AIChatStream.toolResultMessage(
                        callID: call.callID,
                        output: JarvisProtocol.result(["ok": false, "declined": true,
                                                       "note": "The user declined. Do not retry unless they ask."])))
                    continue
                }
                rememberApprovalIfReadOnly(tool)
            }
            activity = tool.activity
            if tool.readsOutsideContent { hasReadOutsideContent = true }
            if tool.readsPrivateContent { hasReadPrivateContent = true }
            let outcome = await toolbox.run(tool, call: call)
            guard generation == current else { return false }
            switch outcome {
            case .result(let output):
                freeMessages.append(AIChatStream.toolResultMessage(callID: call.callID, output: output))
            case .image:
                // The free engine is not offered the tools that produce a
                // picture, and could not read one if it were.
                freeMessages.append(AIChatStream.toolResultMessage(
                    callID: call.callID,
                    output: JarvisProtocol.result(["ok": false, "note": "Ücretsiz modda ekrana bakılamaz."])))
            case .end:
                freeMessages.append(AIChatStream.toolResultMessage(
                    callID: call.callID, output: JarvisProtocol.result(["ok": true])))
                ending = true
            }
        }
        return ending
    }

    private func speakFree(_ text: String) {
        guard isActive, isFreeEngine else { return }
        append(.jarvis, text)
        guard TurkishSpeaker.hasTurkishVoice else {
            // No Turkish voice installed: the answer is on screen rather than
            // in the air, and the conversation carries on by ear anyway.
            return listenFree()
        }
        state = .speaking
        speaker.speak(text)
    }

    private func finishedSpeakingFree() {
        guard isActive, isFreeEngine else { return }
        outputLevel = 0
        if freeIsEnding { return end() }
        listenFree()
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
            if needsUserApproval(for: tool, call: call) {
                let allowed = await ask(tool, text: toolbox.confirmationText(for: tool, call: call))
                guard generation == current else { return }
                guard allowed else {
                    send(JarvisProtocol.functionOutput(callID: call.callID, output: JarvisProtocol.result(
                        ["ok": false, "declined": true, "note": "The user declined. Do not retry unless they ask."])))
                    continue
                }
                rememberApprovalIfReadOnly(tool)
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


    private func needsUserApproval(for tool: JarvisTool, call: JarvisCall) -> Bool {
        if allowedReadTools.contains(tool) { return false }
        return tool.needsConfirmation(call: call,
                                      afterReadingOutsideContent: hasReadOutsideContent,
                                      privateContent: hasReadPrivateContent)
    }

    private func rememberApprovalIfReadOnly(_ tool: JarvisTool) {
        switch tool {
        case .readMail, .calendarEvents:
            allowedReadTools.insert(tool)
        default:
            break
        }
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
        let quiet = isFreeEngine ? Self.freeQuietLimit : Self.quietLimit
        idleTimer = Timer.scheduledTimer(withTimeInterval: quiet, repeats: false) { [weak self] _ in
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
