import AppKit
import CLlama
import Foundation
import IOKit.ps
import MacBCore

/// The local model, running in MacB's own process on the Mac's GPU.
///
/// Nothing leaves the Mac: no server, no helper app, no network once the model
/// file is here. Three things keep it light:
/// - It is loaded only when a conversation needs it, and let go after a few
///   idle minutes (sooner on battery, at once under memory pressure), so a
///   MacB that is not talking holds none of its 3 GB.
/// - The part of a conversation the model has already read — the instructions,
///   the tools, the turns so far — stays in its cache. Only the new sentence
///   is read each turn, which is most of what makes an answer quick.
/// - The KV cache is kept at 8 bits, which halves its memory for no audible
///   difference in the answers.
///
/// All work happens on one serial queue; the model is not thread-safe.
final class LocalLLM: @unchecked Sendable {
    static let shared = LocalLLM()

    enum Failure: LocalizedError {
        case notInstalled
        case loadFailed
        case tooLong(Int)
        case decodeFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Yerel model indirilmemiş. Ayarlar › Asistan › Yerel model."
            case .loadFailed: return "Yerel model açılamadı."
            case .tooLong: return "Konuşma yerel modelin belleğine sığmadı."
            case .decodeFailed(let code): return "Yerel model cevap veremedi (\(code))."
            }
        }
    }

    /// What one answer cost, for the probe and the log.
    struct Stats: Sendable {
        var promptTokens = 0
        var reusedTokens = 0
        var generatedTokens = 0
        var loadSeconds: Double = 0
        var readSeconds: Double = 0
        var writeSeconds: Double = 0

        var tokensPerSecond: Double { writeSeconds > 0 ? Double(generatedTokens) / writeSeconds : 0 }
    }

    static let contextLength: Int32 = 8192
    private static let batchLength: Int32 = 1024

    static var modelsFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacB/Models", isDirectory: true)
    }

    static func url(for file: LocalModel.File = LocalModel.current) -> URL {
        modelsFolder.appendingPathComponent(file.fileName)
    }

    /// Present and whole. The hash was checked when it was downloaded; the
    /// size is checked every time, which is free and catches a file cut short.
    static func isInstalled(_ file: LocalModel.File = LocalModel.current) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: file).path)
        return (attributes?[.size] as? NSNumber)?.int64Value == file.bytes
    }

    private let queue = DispatchQueue(label: "dev.hamzababal.MacB.local-llm", qos: .userInitiated)
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var cached: [llama_token] = []
    private var idleTimer: DispatchSourceTimer?
    private var pressure: DispatchSourceMemoryPressure?

    private init() {
        queue.async { [self] in
            // ggml compiles its GPU kernels from source the first time a model
            // loads: there is no Metal compiler on a Mac without Xcode, but
            // the GPU driver has one.
            if let resources = Bundle.main.resourceURL?.appendingPathComponent("ggml-metal").path {
                setenv("GGML_METAL_PATH_RESOURCES", resources, 1)
            }
            if ProcessInfo.processInfo.environment["MACB_LLM_LOG"] == "1" {
                llama_log_set({ _, text, _ in if let text { fputs(text, stderr) } }, nil)
            } else {
                llama_log_set({ level, text, _ in
                    guard level == GGML_LOG_LEVEL_ERROR, let text else { return }
                    fputs(text, stderr)
                }, nil)
            }
            llama_backend_init()
            let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)
            source.setEventHandler { [weak self] in self?.unloadNow() }
            source.resume()
            pressure = source
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: nil) { [weak self] _ in
            self?.unloadAndWait()
        }
    }

    var isLoaded: Bool { queue.sync { context != nil } }

    // MARK: - Work

    /// Reads `prompt` ahead of time — the instructions and tools, while the
    /// user is still speaking — so the first answer does not wait for them.
    ///
    /// The model's reading of them is kept on disk: the same instructions
    /// and tools next time are loaded in a moment instead of read again —
    /// half a minute on battery. One file, replaced when the instructions
    /// change (a new memory, another persona, a guest).
    func prepare(prompt: String) {
        queue.async { [self] in
            guard (try? loadIfNeeded()) != nil else { return }
            let tokens = tokenize(prompt)
            guard !tokens.isEmpty, tokens.count < Int(Self.contextLength) else { return }
            defer { scheduleUnload() }
            if cached.count >= tokens.count, Array(cached.prefix(tokens.count)) == tokens { return }
            let key = Self.stateKey(tokens)
            if (try? String(contentsOf: Self.stateKeyURL, encoding: .utf8)) == key, loadState(tokens) { return }
            guard (try? read(tokens, needsLogits: false)) != nil else { return }
            saveState(tokens, key: key)
        }
    }

    private static var stateURL: URL { modelsFolder.appendingPathComponent("prefix.state") }
    private static var stateKeyURL: URL { modelsFolder.appendingPathComponent("prefix.key") }

    /// What the saved state must match: the model, the cache settings, and
    /// every token of what was read.
    private static func stateKey(_ tokens: [llama_token]) -> String {
        var hash: UInt64 = 1469598103934665603
        for token in tokens {
            withUnsafeBytes(of: token.littleEndian) { bytes in
                for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
            }
        }
        return "\(LocalModel.current.id)|ctx\(contextLength)|kv-q8|\(tokens.count)|\(String(hash, radix: 36))"
    }

    private func loadState(_ tokens: [llama_token]) -> Bool {
        guard let context else { return false }
        let memory = llama_get_memory(context)
        llama_memory_clear(memory, true)
        cached = []
        var buffer = [llama_token](repeating: 0, count: tokens.count + 16)
        var count = 0
        let bytes = llama_state_seq_load_file(context, Self.stateURL.path, 0, &buffer, buffer.count, &count)
        guard bytes > 0, count == tokens.count, Array(buffer.prefix(count)) == tokens else {
            llama_memory_clear(memory, true)
            return false
        }
        cached = tokens
        return true
    }

    private func saveState(_ tokens: [llama_token], key: String) {
        guard let context else { return }
        // The key goes last: a state file cut short by a crash is never
        // taken for a good one.
        try? "".write(to: Self.stateKeyURL, atomically: true, encoding: .utf8)
        guard llama_state_seq_save_file(context, Self.stateURL.path, 0, tokens, tokens.count) > 0 else { return }
        try? key.write(to: Self.stateKeyURL, atomically: true, encoding: .utf8)
    }

    /// The model's answer to `prompt`, which should end with the assistant
    /// turn opened.
    /// `onText` gets everything written so far, each time a token completes
    /// a character, on this object's queue.
    func generate(prompt: String, maximumTokens: Int,
                  onText: (@Sendable (String) -> Void)? = nil) async throws -> (text: String, stats: Stats) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    continuation.resume(returning: try generateNow(prompt: prompt, maximumTokens: maximumTokens,
                                                                   onText: onText))
                } catch {
                    continuation.resume(throwing: error)
                }
                scheduleUnload()
            }
        }
    }

    func unload() { queue.async { [self] in unloadNow() } }

    /// Lets go of the model before returning. ggml checks at exit that every
    /// GPU buffer was released, and aborts if one was not — so this runs
    /// when MacB quits.
    func unloadAndWait() { queue.sync { unloadNow() } }

    private func generateNow(prompt: String, maximumTokens: Int,
                             onText: (@Sendable (String) -> Void)?) throws -> (text: String, stats: Stats) {
        var stats = Stats()
        let loadStart = Date()
        try loadIfNeeded()
        stats.loadSeconds = Date().timeIntervalSince(loadStart)
        guard let context, let model else { throw Failure.loadFailed }
        let vocab = llama_model_get_vocab(model)

        let tokens = tokenize(prompt)
        stats.promptTokens = tokens.count
        guard tokens.count + maximumTokens < Int(Self.contextLength) else { throw Failure.tooLong(tokens.count) }

        let readStart = Date()
        stats.reusedTokens = try read(tokens, needsLogits: true)
        stats.readSeconds = Date().timeIntervalSince(readStart)

        let sampler = Self.makeSampler()
        defer { llama_sampler_free(sampler) }
        var bytes: [UInt8] = []
        var position = Int32(cached.count)
        let writeStart = Date()
        var batch = llama_batch_init(1, 0, 1)
        defer { llama_batch_free(batch) }
        for _ in 0..<maximumTokens {
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            bytes += piece(token, vocab: vocab)
            stats.generatedTokens += 1
            // Only whole characters: a Turkish letter split across two
            // tokens waits for its second half.
            if let onText, let text = String(bytes: bytes, encoding: .utf8) { onText(text) }
            batch.n_tokens = 1
            batch.token[0] = token
            batch.pos[0] = position
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            let code = llama_decode(context, batch)
            guard code == 0 else { throw Failure.decodeFailed(code) }
            cached.append(token)
            position += 1
        }
        stats.writeSeconds = Date().timeIntervalSince(writeStart)
        return (String(decoding: bytes, as: UTF8.self), stats)
    }

    /// Brings the cache in line with `tokens`: keeps the longest prefix it
    /// already holds, drops the rest, and reads what is new. Returns how many
    /// tokens were reused.
    private func read(_ tokens: [llama_token], needsLogits: Bool) throws -> Int {
        guard let context else { throw Failure.loadFailed }
        var common = zip(cached, tokens).prefix { $0 == $1 }.count
        // The last token is always read again: its logits are the answer's
        // first word, and they are not kept.
        if needsLogits, common == tokens.count { common -= 1 }
        let memory = llama_get_memory(context)
        if !llama_memory_seq_rm(memory, 0, Int32(common), -1) {
            llama_memory_clear(memory, true)
            common = 0
        }
        cached = Array(cached.prefix(common))

        var batch = llama_batch_init(Self.batchLength, 0, 1)
        defer { llama_batch_free(batch) }
        var start = common
        while start < tokens.count {
            let end = min(start + Int(Self.batchLength), tokens.count)
            batch.n_tokens = Int32(end - start)
            for index in start..<end {
                let slot = index - start
                batch.token[slot] = tokens[index]
                batch.pos[slot] = Int32(index)
                batch.n_seq_id[slot] = 1
                batch.seq_id[slot]![0] = 0
                batch.logits[slot] = (needsLogits && index == tokens.count - 1) ? 1 : 0
            }
            let code = llama_decode(context, batch)
            guard code == 0 else {
                llama_memory_clear(memory, true)
                cached = []
                throw Failure.decodeFailed(code)
            }
            cached += tokens[start..<end]
            start = end
        }
        return common
    }

    private func loadIfNeeded() throws {
        if context != nil { return }
        let path = Self.url().path
        guard Self.isInstalled() else { throw Failure.notInstalled }
        var modelParameters = llama_model_default_params()
        modelParameters.n_gpu_layers = 999
        guard let model = llama_model_load_from_file(path, modelParameters) else { throw Failure.loadFailed }
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = UInt32(Self.contextLength)
        contextParameters.n_batch = UInt32(Self.batchLength)
        contextParameters.n_ubatch = 512
        // The GPU does the work; a few CPU threads for what is left keep the
        // efficiency cores free for everything else.
        contextParameters.n_threads = 4
        contextParameters.n_threads_batch = 4
        contextParameters.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED
        contextParameters.type_k = GGML_TYPE_Q8_0
        contextParameters.type_v = GGML_TYPE_Q8_0
        contextParameters.no_perf = true
        guard let context = llama_init_from_model(model, contextParameters) else {
            llama_model_free(model)
            throw Failure.loadFailed
        }
        self.model = model
        self.context = context
        cached = []
    }

    private func unloadNow() {
        idleTimer?.cancel()
        idleTimer = nil
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        cached = []
    }

    private func scheduleUnload() {
        idleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + LocalModel.idleUnload(onBattery: Self.isOnBattery))
        timer.setEventHandler { [weak self] in self?.unloadNow() }
        timer.resume()
        idleTimer = timer
    }

    static var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    // MARK: - Tokens

    private func tokenize(_ text: String) -> [llama_token] {
        guard let model else { return [] }
        let vocab = llama_model_get_vocab(model)
        let utf8 = Array(text.utf8CString)
        let length = Int32(utf8.count - 1)
        var tokens = [llama_token](repeating: 0, count: Int(length) + 16)
        var count = llama_tokenize(vocab, utf8, length, &tokens, Int32(tokens.count), false, true)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, utf8, length, &tokens, Int32(tokens.count), false, true)
        }
        return count > 0 ? Array(tokens.prefix(Int(count))) : []
    }

    /// A token's bytes. Turkish letters are two bytes and a token can end
    /// between them, so bytes are collected and decoded only at the end.
    private func piece(_ token: llama_token, vocab: OpaquePointer?) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(max(0, Int(count))).map { UInt8(bitPattern: $0) }
    }

    private static func makeSampler() -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(LocalModel.topK))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(LocalModel.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(LocalModel.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max - 1)))
        return chain
    }
}
