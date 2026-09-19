import AVFoundation
import AppKit
import MacBCore

/// Command-line probes for features that otherwise need a gesture to reach.
@MainActor enum Probe {
    static func run(_ arguments: [String]) -> (@MainActor () async -> Void)? {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        func values(after flag: String) -> [String] {
            guard let index = arguments.firstIndex(of: flag) else { return [] }
            return Array(arguments[(index + 1)...].prefix { !$0.hasPrefix("--") })
        }

        if let text = value(after: "--translate") {
            let target = value(after: "--to") ?? "tr"
            return {
                switch await OfflineTranslator().translate(text, preferredTarget: target) {
                case .success(let result): print("\(result.source) → \(result.target): \(result.text)")
                case .failure(let failure): print("error: \(failure.message)")
                }
            }
        }
        if let path = value(after: "--convert") {
            return {
                let url = URL(fileURLWithPath: path)
                do {
                    if ShelfConversion.canConvertToJPEG(url) {
                        print("jpeg: \(try await ShelfConverter.jpegCopy(of: url).path)")
                    }
                    print("reduced: \(try await ShelfConverter.reducedCopy(of: url).path)")
                } catch { print("error: \(error.localizedDescription)") }
            }
        }
        let pdfs = values(after: "--merge")
        if !pdfs.isEmpty {
            return {
                do { print("merged: \(try await ShelfConverter.merge(pdfs.map { URL(fileURLWithPath: $0) }).path)") }
                catch { print("error: \(error.localizedDescription)") }
            }
        }
        if arguments.contains("--keep-awake-probe") {
            return {
                let service = KeepAwakeService.shared
                print("started: \(service.start(minutes: 1))  remaining: \(service.remainingText)")
                print(shell("/usr/bin/pmset", ["-g", "assertions"]).split(separator: "\n")
                    .filter { $0.contains("MacB") }.joined(separator: "\n"))
                service.stop()
                let after = shell("/usr/bin/pmset", ["-g", "assertions"]).contains("MacB: Uyanık tut")
                print("released: \(!after)")
            }
        }
        if arguments.contains("--selection-probe") {
            return {
                let delay = Double(value(after: "--selection-probe") ?? "") ?? 0
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                let service = SelectedTextService()
                switch await service.read() {
                case .success(let selection):
                    print("app: \(selection.appName)  chars: \(selection.text.count)  via: \(selection.element == nil ? "⌘C" : "AX")  replaceable: \(selection.canReplace)")
                    if let replacement = value(after: "--replace-with") {
                        print("replaced: \(service.replace(selection, with: replacement))")
                    }
                case .failure(let failure): print("error: \(failure.message)")
                }
            }
        }
        // Opens a Realtime session with the stored key and the real session
        // settings, waits for the server to accept them, and closes. No audio
        // is sent; with --say it asks one short text question, answered as text.
        if arguments.contains("--jarvis-probe") {
            return {
                guard let key = AIKeyStore().read() else { print("error: no key"); return }
                let model = value(after: "--model") ?? JarvisProtocol.defaultModel
                guard let url = JarvisProtocol.url(model: model) else { print("error: bad model"); return }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                let socket = URLSession.shared.webSocketTask(with: request)
                socket.resume()
                func send(_ object: [String: Any]) async throws {
                    let data = try JSONSerialization.data(withJSONObject: object)
                    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
                }
                do {
                    try await send(JarvisProtocol.sessionUpdate(voice: .cedar, now: Date()))
                    var said = false
                    let deadline = Date().addingTimeInterval(25)
                    while Date() < deadline {
                        let message = try await socket.receive()
                        guard case .string(let text) = message,
                              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                              let type = object["type"] as? String else { continue }
                        let event = JarvisProtocol.event(from: text)
                        switch event {
                        case .audio(_, let pcm): print("\(type) \(pcm.count) bytes")
                        default: print(type, event == .ignored ? "" : "→ \(event)")
                        }
                        if type == "error" { print(text.prefix(400)) }
                        if case .sessionReady = event {
                            guard let question = value(after: "--say"), !said else { break }
                            said = true
                            try await send(JarvisProtocol.text(question))
                            try await send(["type": "response.create", "response": ["output_modalities": ["text"]]])
                        }
                        if case .responseDone(let calls) = event {
                            print("calls: \(calls.map(\.name))")
                            break
                        }
                        if type == "response.output_text.delta", let delta = object["delta"] as? String { print("  " + delta) }
                    }
                } catch { print("error: \(error.localizedDescription)  status: \((socket.response as? HTTPURLResponse)?.statusCode ?? 0)") }
                socket.cancel(with: .normalClosure, reason: nil)
            }
        }
        // Opens the microphone locally for two seconds in each audio setup
        // Jarvis can use and reports which ones start. Nothing is sent.
        if arguments.contains("--audio-probe") {
            return {
                let engine = AVAudioEngine()
                print("input format:", engine.inputNode.outputFormat(forBus: 0))
                print("output format:", engine.outputNode.outputFormat(forBus: 0))
                for echo in [true, false] {
                    let audio = JarvisAudio()
                    var chunks = 0
                    let lock = NSLock()
                    audio.onCapture = { _ in lock.withLock { chunks += 1 } }
                    do {
                        try audio.start(echoCancellation: echo)
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        // A quiet half-second tone through the same path the
                        // voice uses, to prove playback and the heard-so-far
                        // counter work.
                        let tone = JarvisProtocol.pcm16(from: (0..<12_000).map {
                            Float(sin(Double($0) * 2 * Double.pi * 440 / 24_000) * 0.12)
                        })
                        let began = Date()
                        audio.play(tone, item: "probe")
                        let immediately = audio.isSpeaking
                        print("  after play: \(audio.diagnostic)")
                        var finishedAfter: Double?
                        for _ in 0..<40 {
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            if !audio.isSpeaking { finishedAfter = Date().timeIntervalSince(began); break }
                        }
                        audio.stop()
                        print("echoCancellation=\(echo): started, \(lock.withLock { chunks }) chunks, " +
                              "queued=\(immediately), tone played in " +
                              String(format: "%.2fs", finishedAfter ?? -1) + " (expected ~0.50s)")
                    } catch {
                        print("echoCancellation=\(echo): failed \((error as NSError).code) \(error.localizedDescription)")
                    }
                }
            }
        }
        if arguments.contains("--arrangement-probe") {
            return {
                let service = WindowArrangementService(directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("macb-arrangement-probe-\(UUID().uuidString)"))
                print("displays: \(WindowArrangementService.currentSignature().summary)")
                guard let saved = service.saveCurrent(named: "probe") else {
                    print("error: \(service.lastMessage ?? "—")"); return
                }
                let apps = Set(saved.windows.map(\.bundleIdentifier)).count
                print("windows: \(saved.windows.count) in \(apps) apps")
                if arguments.contains("--apply") {
                    print("moved back in place: \(service.apply(saved))  \(service.lastMessage ?? "")")
                }
            }
        }
        return nil
    }

    private static func shell(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
