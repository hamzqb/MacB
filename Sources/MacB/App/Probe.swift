import AVFoundation
import AppKit
import SwiftUI
import MacBCore
import Security

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

        if let path = value(after: "--import-keys") {
            // A one-off: reads `provider=key` lines from a file and puts each in
            // the Keychain, so keys that arrived on paper or in a message do not
            // have to be typed into a window one at a time. Nothing is echoed
            // back but the provider names, and whoever runs this is expected to
            // shred the file afterwards — MacB does not touch it.
            return {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
                    return print("error: dosya okunamadı")
                }
                var keys: [AIProvider: String] = [:]
                var weatherKey: String?
                for line in text.split(whereSeparator: \.isNewline) {
                    let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { continue }
                    let name = parts[0].trimmingCharacters(in: .whitespaces)
                    let secret = parts[1].trimmingCharacters(in: .whitespaces)
                    if name == WeatherFallback.account { weatherKey = secret; continue }
                    guard let provider = AIProvider(rawValue: name) else { continue }
                    keys[provider] = secret
                }
                if let weather = weatherKey {
                    print("openweather: \(WeatherFallback.save(weather) ? "kaydedildi" : "reddedildi")")
                }
                guard !keys.isEmpty else { return print("error: tanınan AI satırı yok") }
                let outcome = AIKeyStore().importKeys(keys)
                for provider in AIProvider.allCases where outcome[provider] != nil {
                    print("\(provider.rawValue): \(outcome[provider] == true ? "kaydedildi" : "reddedildi")")
                }
            }
        }
        if arguments.contains("--ocr-probe") {
            // Checks the recogniser against a picture MacB draws itself. The
            // user's own screen is never captured for a test.
            return {
                let expected = ["MacB ekran okuma testi", "Şu an saat 09:41", "Ücretsiz deneme"]
                let size = NSSize(width: 900, height: 300)
                let image = NSImage(size: size)
                image.lockFocus()
                NSColor.white.setFill()
                NSRect(origin: .zero, size: size).fill()
                for (index, line) in expected.enumerated() {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 40),
                        .foregroundColor: NSColor.black
                    ]
                    line.draw(at: NSPoint(x: 30, y: size.height - 70 - CGFloat(index) * 70),
                              withAttributes: attributes)
                }
                image.unlockFocus()
                guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    return print("error: görüntü hazırlanamadı")
                }
                do {
                    let reading = try ScreenTextReader.read(image: cgImage)
                    print("lines: \(reading.lineCount), chars: \(reading.text.count)")
                    for line in reading.text.split(separator: "\n") { print("read: \(line)") }
                    for line in expected {
                        print("\(reading.text.contains(line) ? "ok" : "MISS"): \(line)")
                    }
                } catch { print("error: \(error.localizedDescription)") }
            }
        }
        if let question = value(after: "--ask") {
            // One real question through whichever provider is chosen, to prove
            // the whole path end to end: key, address, request and stream.
            return {
                let keys = AIKeyStore()
                let preferences = Preferences()
                let service = AIAssistantService(
                    keys: keys,
                    model: { preferences.model(for: $0) },
                    preferredProvider: { preferences.preferredProvider })
                guard let provider = service.provider else { return print("error: kayıtlı anahtar yok") }
                print("provider: \(provider.title) · model: \(preferences.model(for: provider))")
                service.ask(question)
                for _ in 0..<300 where service.isAnswering {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                if let error = service.errorMessage { return print("error: \(error)") }
                let answer = service.turns.last?.answer ?? ""
                print("answer (\(answer.count) chars): \(answer.prefix(300))")
            }
        }
        if let name = value(after: "--list-models") {
            // What a provider actually offers today. Their lists change under
            // MacB, and a model name that no longer exists fails with a 404
            // that says nothing useful.
            return {
                guard let provider = AIProvider(rawValue: name) else { return print("error: bilinmeyen sağlayıcı") }
                guard let key = AIKeyStore().read(provider) else { return print("error: anahtar yok") }
                var request = URLRequest(url: provider.modelsURL)
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 20
                guard let (data, _) = try? await URLSession.shared.data(for: request),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = object["data"] as? [[String: Any]] else {
                    return print("error: liste alınamadı")
                }
                for model in models.compactMap({ $0["id"] as? String }).sorted() { print(model) }
            }
        }
        if let query = value(after: "--youtube-probe") {
            // Only prints the identifier; nothing is opened and nothing from
            // the page is shown.
            return {
                let identifier = await MusicSearch.firstYouTubeVideo(matching: query)
                print("videoId: \(identifier ?? "bulunamadı")")
            }
        }
        if arguments.contains("--measure-assistant") {
            // The island reserves a height for the assistant; this checks the
            // view actually fits in it, rather than trusting the number.
            return {
                let session = JarvisSession(keys: AIKeyStore(), memory: JarvisMemoryStore(),
                                            voice: { .marin }, model: { JarvisProtocol.defaultModel })
                let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
                var notch: CGFloat = 0
                if let screen, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                    notch = max(0, right.minX - left.maxX)
                }
                let camera = screen?.safeAreaInsets.top ?? 0
                let width = IslandGeometry.assistantWidth(hasConfirmation: false, notchWidth: notch)
                let ear = IslandGeometry.assistantEarContentWidth(panelWidth: width, notchWidth: notch)
                print("notch: \(Int(notch)) camera strip: \(Int(camera)) panel: \(Int(width)) ear: \(Int(ear))")
                // The longest words the status line says, drawn in its own font.
                for status in ["dinliyorum", "düşünüyor…", "internette arıyor…", "bağlanamadı"] {
                    let text = NSHostingView(rootView: Text(status)
                        .font(.system(size: MacBDesign.TypeScale.caption, weight: .medium)).fixedSize())
                    let needed = text.fittingSize.width
                    print("status \"\(status)\": \(Int(needed.rounded()))pt \(needed <= ear ? "ok" : "MISS: kesilir")")
                }
                // The orb plus all three hover buttons on the left side.
                let presence = NSHostingView(rootView: IslandAssistantPresence(
                    session: session, captions: .constant(false), hovering: true, close: {}).fixedSize())
                let left = presence.fittingSize
                print("left side hovered: \(Int(left.width.rounded()))x\(Int(left.height.rounded())) "
                      + (left.width <= ear && left.height <= camera ? "ok" : "MISS: taşıyor"))
                // The ears are in the camera strip, the camera and settings
                // buttons in the navigation row under it: different rows.
                print("ears y: 0-\(Int(camera))  controls y: \(Int(camera + IslandGeometry.topPadding))-"
                      + "\(Int(camera + IslandGeometry.topPadding + IslandGeometry.navigationHeight))")
                let input = NSHostingView(rootView: IslandAssistantInput(session: session, openSettings: {},
                                                                         isInteractive: false))
                input.frame = NSRect(x: 0, y: 0, width: width - IslandGeometry.horizontalPadding * 2, height: 200)
                input.layoutSubtreeIfNeeded()
                let inputHeight = input.fittingSize.height
                print("input: \(Int(inputHeight.rounded())) nav row: \(Int(IslandGeometry.navigationHeight)) "
                      + (inputHeight <= IslandGeometry.navigationHeight ? "ok" : "MISS: taşıyor"))
                let body = NSHostingView(rootView: IslandAssistantView(session: session, captions: .constant(false),
                                                                       showsPresence: notch == 0, close: {}))
                body.frame = NSRect(x: 0, y: 0, width: width, height: 400)
                body.layoutSubtreeIfNeeded()
                let reserved = IslandGeometry.assistantHeight(hasEars: notch > 0, showsDetail: false,
                                                              hasConfirmation: false)
                print("body: \(Int(body.fittingSize.height.rounded())) reserved: \(Int(reserved)) "
                      + (body.fittingSize.height <= reserved + 0.5 ? "ok" : "MISS: taşıyor"))
                print("with captions: \(Int(IslandGeometry.assistantHeight(hasEars: notch > 0, showsDetail: true, hasConfirmation: false)))")
                print("with confirmation: \(Int(IslandGeometry.assistantHeight(hasEars: notch > 0, showsDetail: true, hasConfirmation: true)))")
            }
        }
        if arguments.contains("--measure-briefing") {
            // Same check for the briefing card: the island reserves a height
            // for it, and this draws the real view to see whether it fits.
            return {
                let preferences = Preferences()
                let briefing = BriefingService(preferences: preferences, weather: WeatherService(),
                                               monitor: SystemMonitorService(), activity: AIActivityService())
                let chips = [Briefing.Chip(symbol: "cloud.fill", text: "25° kapalı"),
                             Briefing.Chip(symbol: "calendar", text: "09:30 toplantı +2"),
                             Briefing.Chip(symbol: "battery.25", text: "%9", isUrgent: true)]
                briefing.preview(greeting: "İyi günler Hamza.", chips: chips,
                                 lines: ["İyi günler Hamza.", "Yalova 25 derece, kapalı."])
                let view = IslandBriefingView(briefing: briefing, close: {}, talk: {})
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: IslandGeometry.briefingWidth, height: 400)
                host.layoutSubtreeIfNeeded()
                let fitting = host.fittingSize
                let reserved = IslandGeometry.briefingHeight(chipCount: chips.count)
                print("width: \(IslandGeometry.briefingWidth) needs: \(Int(fitting.width.rounded()))")
                print("fits: \(Int(fitting.height.rounded())) reserved: \(Int(reserved.rounded()))")
                print(fitting.height <= reserved ? "ok: sığıyor" : "MISS: taşıyor")
                print(fitting.width <= IslandGeometry.briefingWidth ? "ok: genişlik yeter" : "MISS: dar")
                print("without chips: \(Int(IslandGeometry.briefingHeight(chipCount: 0)))")
            }
        }
        if arguments.contains("--measure-agent") {
            return {
                let store = AgentJobStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("macb-probe-jobs.json"))
                var job = AgentJob(request: "önemsiz maillere bak ve bana listele")
                job.state = .done
                job.report = "Otuz iki okunmamış mailin var, hiçbiri önemli görünmüyor. İkisi bülten, birini arşivlemeyi önerdim."
                job.proposals = [
                    AgentProposal(tool: "add_note", arguments: "{}", text: "Nota eklensin mi: bülten listesi"),
                    AgentProposal(tool: "open_application", arguments: "{}", text: "Mail açılsın mı?")
                ]
                store.update(job.id) { _ in }
                if store.add(request: job.request) != nil, let first = store.jobs.first {
                    store.update(first.id) { existing in
                        existing.state = job.state
                        existing.report = job.report
                        existing.proposals = job.proposals
                    }
                }
                let view = IslandAgentView(jobs: store, approve: { _, _ in }, refuse: { _, _ in },
                                           dismiss: { _ in })
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: IslandGeometry.agentWidth, height: 500)
                host.layoutSubtreeIfNeeded()
                let fitting = host.fittingSize
                let reserved = IslandGeometry.agentHeight(reportLines: 2, proposals: 2)
                print("width: \(IslandGeometry.agentWidth) needs: \(Int(fitting.width.rounded()))")
                print("fits: \(Int(fitting.height.rounded())) reserved: \(Int(reserved.rounded()))")
                print(fitting.height <= reserved ? "ok: sığıyor" : "MISS: taşıyor")
                store.clearDelivered()
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("macb-probe-jobs.json"))
            }
        }
        if let index = arguments.firstIndex(of: "--job-probe"), arguments.count > index + 1 {
            // Runs one real background job end to end: the free provider, the
            // tool declarations, the policy and the report. No toolbox, so the
            // reading tools answer "no toolbox" — what is being proved here is
            // the loop and that nothing acts.
            let task = arguments[index + 1]
            return {
                let keys = AIKeyStore()
                let store = AgentJobStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("macb-probe-run.json"))
                let engine = FreeVoiceEngine(keys: keys, model: { $0.defaultModel })
                guard let provider = engine.provider else { return print("ücretsiz sağlayıcı anahtarı yok") }
                print("provider: \(provider.title) \(provider.defaultModel)")
                let runner = AgentJobRunner(store: store, engine: engine)
                guard store.add(request: task) != nil else { return print("iş eklenemedi") }
                runner.pump()
                for _ in 0..<120 where !store.running.isEmpty {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                for job in store.jobs {
                    print("state: \(job.state.title) rounds: \(job.rounds)")
                    print("report: \(job.report)")
                    for proposal in job.proposals { print("waiting: \(proposal.tool) — \(proposal.text)") }
                }
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("macb-probe-run.json"))
            }
        }
        if let index = arguments.firstIndex(of: "--chat-probe"), arguments.count > index + 2 {
            // One small chat request, with the status and the first of the
            // body, for working out why a provider says no. The key is read
            // inside the application and never printed.
            let providerName = arguments[index + 1]
            let model = arguments[index + 2]
            return {
                guard let provider = AIProvider(rawValue: providerName) else { return print("bilinmeyen sağlayıcı") }
                let store = AIKeyStore()
                guard let key = store.read(provider) else { return print("anahtar yok") }
                var request = URLRequest(url: provider.chatURL)
                request.httpMethod = "POST"
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body = AIChatStream.toolRequestBody(
                    messages: [["role": "user", "content": "tek kelimeyle merhaba de"]],
                    model: model, tools: [JarvisTool.weather.chatDeclaration], maximumTokens: 60)
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    print("model: \(model) status: \(code)")
                    print(String(data: data.prefix(400), encoding: .utf8) ?? "-")
                } catch {
                    print("hata: \(error.localizedDescription)")
                }
            }
        }
        if arguments.contains("--mail-probe") {
            return {
                let summary = await MailService().refresh(force: true)
                print(await MailService.probe())
                print("parsed_unread=\(summary.unread)")
                print("parsed_headers=\(summary.headers.count)")
                print("date_fallbacks=not_printed")
                if let note = summary.note { print("note=\(note)") }
            }
        }
        if arguments.contains("--verify-keys") {
            // Asks each provider whether its stored key works. Runs inside the
            // application, which owns the Keychain items, so nothing is
            // prompted for and no key is printed.
            return {
                let store = AIKeyStore()
                for provider in AIProvider.allCases where store.has(provider) {
                    await store.verify(provider)
                    switch store.status(of: provider) {
                    case .valid(let text): print("\(provider.rawValue): \(text)")
                    case .invalid(let text): print("\(provider.rawValue): \(text)")
                    default: print("\(provider.rawValue): cevap yok")
                    }
                }
                if WeatherFallback.hasKey() {
                    let place = UserDefaults.standard.string(forKey: "weatherPlace") ?? "Istanbul"
                    let snapshot = await WeatherFallback.current(place: place, session: .shared)
                    print("openweather: " + (snapshot.map { "\($0.place) \($0.temperature)°" } ?? "cevap yok"))
                }
            }
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
                        if case .responseDone(let calls, _) = event {
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
