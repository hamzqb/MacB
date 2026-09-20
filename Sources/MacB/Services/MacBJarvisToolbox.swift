import AppKit
import EventKit
import MacBCore
import ScreenCaptureKit

/// Jarvis's hands: each tool mapped onto something MacB already does.
///
/// Nothing here deletes, sends, pays or signs in. The screen is captured into
/// memory, scaled down and sent once, only after a yes in the panel; it is
/// never written to disk. Calendar writes also wait for a yes.
@MainActor final class MacBJarvisToolbox: JarvisToolbox {
    private let keys: AIKeyStore
    private let searchModel: () -> String
    private let media: MediaService
    private let timer: TimerService
    private let windowLayout: WindowLayoutService
    private let arrangements: WindowArrangementService
    private let note: QuickNoteStore
    private let selection: SelectedTextService
    private let systemMonitor: SystemMonitorService
    private let weather: WeatherService
    private let cost: AICostMeter?
    private let scenarios: ScenarioStore
    private let aiActivity: AIActivityService
    private let memory: JarvisMemoryStore
    private let notify: (String, String) -> Void
    private let events = EKEventStore()

    init(keys: AIKeyStore, searchModel: @escaping () -> String, cost: AICostMeter? = nil,
         media: MediaService, timer: TimerService,
         windowLayout: WindowLayoutService, arrangements: WindowArrangementService, note: QuickNoteStore,
         selection: SelectedTextService, systemMonitor: SystemMonitorService, weather: WeatherService,
         aiActivity: AIActivityService, memory: JarvisMemoryStore, scenarios: ScenarioStore,
         notify: @escaping (String, String) -> Void) {
        self.scenarios = scenarios
        self.weather = weather
        self.cost = cost
        self.aiActivity = aiActivity
        self.memory = memory
        self.keys = keys
        self.searchModel = searchModel
        self.media = media
        self.timer = timer
        self.windowLayout = windowLayout
        self.arrangements = arrangements
        self.note = note
        self.selection = selection
        self.systemMonitor = systemMonitor
        self.notify = notify
    }

    func confirmationText(for tool: JarvisTool, call: JarvisCall) -> String {
        let arguments = call.argumentObject
        switch tool {
        case .lookAtScreen:
            return "MacB ekranının bir görüntüsünü OpenAI'ye göndermek istiyor."
        case .powerAction:
            switch SystemActions.Power(rawValue: arguments["action"] as? String ?? "") {
            case .displaySleep: return "MacB ekranı kapatmak istiyor."
            case .lock: return "MacB ekranı kilitlemek istiyor."
            default: return "MacB Mac'i uyku moduna almak istiyor."
            }
        case .playMusic:
            return "Okuduğu bir içerikten sonra \u{201C}\(arguments["query"] as? String ?? "")\u{201D} çalmak istiyor."
        case .setAppearance:
            return "Okuduğu bir içerikten sonra görünümü değiştirmek istiyor."
        case .openSettings:
            let pane = SettingsPane(rawValue: arguments["pane"] as? String ?? "")?.title ?? "bir"
            return "Okuduğu bir içerikten sonra Sistem Ayarları'nda \(pane) sayfasını açmak istiyor."
        case .setWiFi:
            return "Okuduğu bir içerikten sonra Wi-Fi'ı \((arguments["enabled"] as? Bool ?? true) ? "açmak" : "kapatmak") istiyor."
        case .readScreenText:
            return "MacB ekrandaki yazıyı okumak istiyor. Görüntü Mac'ten çıkmaz; yalnız bulunan yazı gönderilir."
        case .runScenario:
            return "Okuduğu bir içerikten sonra \u{201C}\(arguments["name"] as? String ?? "")\u{201D} senaryosunu çalıştırmak istiyor."
        case .addReminder:
            let due = (JarvisDates.parse(arguments["due"] as? String)).map { " · " + Self.display($0) } ?? ""
            return "Hatırlatıcı eklensin mi: \u{201C}\(arguments["title"] as? String ?? "")\u{201D}\(due)"
        case .addCalendarEvent:
            let start = (JarvisDates.parse(arguments["start"] as? String)).map { " · " + Self.display($0) } ?? ""
            return "Takvime eklensin mi: \u{201C}\(arguments["title"] as? String ?? "")\u{201D}\(start)"
        case .openWebsite:
            // The host, not the raw text: "bank.com@evil.io" goes to evil.io.
            let raw = arguments["url"] as? String ?? ""
            let host = URL(string: raw.contains("://") ? raw : "https://" + raw)?.host ?? raw
            return "Okuduğu bir içerikten sonra \(host) sitesini açmak istiyor."
        case .webSearch:
            return "Özel bilgilerini gördükten sonra internette şunu aramak istiyor: \u{201C}\(arguments["query"] as? String ?? "")\u{201D}"
        case .calendarEvents:
            return "Okuduğu bir içerikten sonra takvimine bakmak istiyor."
        case .openApplication:
            return "Okuduğu bir içerikten sonra \(arguments["name"] as? String ?? "bir uygulama") açmak istiyor."
        case .copyToClipboard:
            return "Okuduğu bir içerikten sonra panoya metin koymak istiyor."
        case .addNote:
            return "Nota eklensin mi: \u{201C}\(arguments["text"] as? String ?? "")\u{201D}"
        case .remember:
            return "Hafızaya eklensin mi: \u{201C}\(arguments["fact"] as? String ?? "")\u{201D}"
        case .forget:
            return "Hafızadan silinsin mi: \u{201C}\(arguments["about"] as? String ?? "")\u{201D} geçenler"
        default:
            return tool.activity
        }
    }

    func run(_ tool: JarvisTool, call: JarvisCall) async -> JarvisToolOutcome {
        let arguments = call.argumentObject
        switch tool {
        case .webSearch:
            return .result(await webSearch(arguments["query"] as? String ?? ""))
        case .lookAtScreen:
            switch await Self.screenshot() {
            case .success(let jpeg): return .image(jpeg: jpeg, question: arguments["question"] as? String)
            case .failure(let error): return fail(error.localizedDescription)
            }
        case .playMusic:
            let query = (arguments["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let service = MusicSearch.Service(rawValue: arguments["service"] as? String ?? "") ?? .youtube
            let outcome = await MusicSearch.play(query, on: service)
            guard outcome.opened else { return fail(outcome.message) }
            return ok(["message": outcome.message, "playing": outcome.isPlaying, "service": service.rawValue])
        case .powerAction:
            guard let action = SystemActions.Power(rawValue: arguments["action"] as? String ?? "") else {
                return fail("Bilinmeyen işlem.")
            }
            // The answer is written before the Mac goes, because afterwards
            // there is nobody listening.
            let message = SystemActions.message(for: action)
            guard SystemActions.power(action) else { return fail("Yapılamadı.") }
            return ok(["message": message])
        case .openSettings:
            guard let pane = SettingsPane(rawValue: arguments["pane"] as? String ?? "") else {
                return fail("Böyle bir ayar sayfası yok.")
            }
            guard SystemActions.openSettings(pane) else { return fail("Sayfa açılamadı.") }
            return ok(["opened": pane.title,
                       "note": "Opened the page; the user makes the change themselves."])
        case .setWiFi:
            let enabled = arguments["enabled"] as? Bool ?? true
            guard SystemActions.setWiFi(enabled) else { return fail("Wi-Fi değiştirilemedi.") }
            return ok(["wifi": enabled ? "açık" : "kapalı"])
        case .setAppearance:
            guard let mode = SystemActions.Appearance(rawValue: arguments["mode"] as? String ?? "") else {
                return fail("Bilinmeyen görünüm.")
            }
            guard SystemActions.appearance(mode) else {
                return fail("Görünüm değiştirilemedi; Sistem Ayarları › Gizlilik › Otomasyon'dan MacB'ye izin ver.")
            }
            return ok(["mode": mode.rawValue])
        case .runScenario:
            let name = (arguments["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return fail("Senaryo adı boş.") }
            let message = await scenarios.run(named: name)
            return ok(["message": message, "available": scenarios.scenarios.map(\.name)])
        case .readScreenText:
            do {
                let reading = try await ScreenTextReader.read()
                return ok(["text": reading.text, "lines": reading.lineCount,
                           "truncated": reading.isTruncated,
                           "note": "Recognised on the user's Mac; no image was sent."])
            } catch {
                return fail(error.localizedDescription)
            }
        case .readSelection:
            switch await selection.read() {
            case .success(let found):
                let (text, truncated) = AITextTask.clip(found.text)
                return ok(["app": found.appName, "text": text, "truncated": truncated])
            case .failure(let failure):
                return fail(failure.message)
            }
        case .openApplication:
            return openApplication(arguments["name"] as? String ?? "")
        case .openWebsite:
            return openWebsite(arguments["url"] as? String ?? "")
        case .media:
            return mediaControl(arguments["action"] as? String ?? "toggle")
        case .setVolume:
            let percent = max(0, min(100, (arguments["percent"] as? NSNumber)?.intValue ?? 50))
            var error: NSDictionary?
            NSAppleScript(source: "set volume output volume \(percent)")?.executeAndReturnError(&error)
            return error == nil ? ok(["volume": percent]) : fail("Ses ayarlanamadı.")
        case .startTimer:
            let minutes = max(0.1, min(600, (arguments["minutes"] as? NSNumber)?.doubleValue ?? 5))
            timer.start(minutes: minutes)
            notify("timer", "Zamanlayıcı · \(TimerService.format(minutes * 60))")
            return ok(["minutes": minutes])
        case .keepAwake:
            let service = KeepAwakeService.shared
            if arguments["off"] as? Bool == true {
                service.stop()
                return ok(["awake": false])
            }
            let minutes = max(0, min(1440, (arguments["minutes"] as? NSNumber)?.intValue ?? 60))
            guard service.start(minutes: minutes) else { return fail("Uyanık tutulamadı.") }
            notify("cup.and.heat.waves", "Uyanık · \(KeepAwakeDuration.title(minutes: minutes).lowercased())")
            return ok(["awake": true, "minutes": minutes])
        case .arrangeWindow:
            let actions: [String: WindowLayoutAction] = ["left": .leftHalf, "right": .rightHalf, "maximize": .maximize,
                                                         "center": .center, "next_display": .nextDisplay]
            guard let action = actions[arguments["position"] as? String ?? ""] else { return fail("Bilinmeyen konum.") }
            guard AXIsProcessTrusted() else { return fail("Erişilebilirlik izni yok.") }
            windowLayout.perform(action)
            return windowLayout.registrationError.map(fail) ?? ok(["moved": true])
        case .applyWindowArrangement:
            guard AXIsProcessTrusted() else { return fail("Erişilebilirlik izni yok.") }
            if let name = arguments["name"] as? String, !name.isEmpty,
               let match = arrangements.arrangements.first(where: {
                   $0.name.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0.name)
               }) {
                let moved = arrangements.apply(match)
                return ok(["arrangement": match.name, "moved": moved])
            }
            let message = arrangements.applyPreferred()
            return ok(["result": message, "saved": arrangements.arrangements.map(\.name)])
        case .calendarEvents:
            return await calendar(days: max(1, min(14, (arguments["days"] as? NSNumber)?.intValue ?? 2)))
        case .addReminder:
            return await addReminder(title: arguments["title"] as? String ?? "",
                                     due: JarvisDates.parse(arguments["due"] as? String))
        case .addCalendarEvent:
            return await addEvent(title: arguments["title"] as? String ?? "",
                                  start: JarvisDates.parse(arguments["start"] as? String),
                                  end: JarvisDates.parse(arguments["end"] as? String))
        case .addNote:
            let text = (arguments["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return fail("Boş not.") }
            note.text = note.text.isEmpty ? text : note.text + "\n" + text
            notify("square.and.pencil", "Nota eklendi")
            return ok(["added": true])
        case .copyToClipboard:
            let text = arguments["text"] as? String ?? ""
            guard !text.isEmpty else { return fail("Boş metin.") }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            notify("doc.on.clipboard", "Panoya kopyalandı")
            return ok(["copied": true])
        case .systemStatus:
            let snapshot = systemMonitor.snapshot
            var fields: [String: Any] = [
                "now": ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                                   formatOptions: [.withInternetDateTime]),
                "cpu_percent": Int(snapshot.cpuUsage),
                "memory_used_gb": Double(snapshot.usedMemory) / 1_073_741_824,
                "memory_total_gb": Double(snapshot.totalMemory) / 1_073_741_824,
                "disk_free_gb": Double(snapshot.availableDisk) / 1_000_000_000,
                "charging": snapshot.isCharging
            ]
            if let battery = snapshot.batteryPercent { fields["battery_percent"] = Int(battery) }
            return ok(fields)
        case .weather:
            if weather.snapshot == nil {
                weather.refresh(force: true)
                for _ in 0..<25 where weather.snapshot == nil && weather.errorMessage == nil {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            guard let now = weather.snapshot else {
                return fail(weather.errorMessage ?? "Hava durumu alınamadı; Ayarlar'da şehir seçili mi?")
            }
            return ok(["place": now.place, "temperature_c": now.temperature, "feels_like_c": now.feelsLike,
                       "condition": now.condition, "daytime": now.isDay])
        case .codingAgents:
            let statuses = aiActivity.statuses.map { status -> [String: Any] in
                var item: [String: Any] = ["assistant": status.kind.rawValue, "running": status.isRunning]
                if let source = status.source { item["where"] = source }
                if let left = status.usage?.remainingPercent { item["allowance_left_percent"] = Int(left) }
                return item
            }
            let sessions = aiActivity.activities.map { ["assistant": $0.kind.rawValue, "where": $0.source,
                                                        "running_for": $0.elapsedText] as [String: Any] }
            return ok(["assistants": statuses, "sessions": sessions])
        case .remember:
            let fact = (arguments["fact"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fact.isEmpty else { return fail("Boş bilgi.") }
            let added = memory.remember(fact)
            return ok(["remembered": added, "already_known": !added])
        case .forget:
            let removed = memory.forget(about: arguments["about"] as? String ?? "")
            return ok(["forgotten": removed])
        case .endConversation:
            return .end
        }
    }

    // MARK: - Web

    /// A short, sourced answer from the Responses API with web search: the
    /// same route the AI panel uses, asked to write for the ear.
    private func webSearch(_ query: String) async -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return JarvisProtocol.result(["ok": false, "error": "empty query"]) }
        guard let key = keys.read(.openAI) else { return JarvisProtocol.result(["ok": false, "error": "no key"]) }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        let body: [String: Any] = [
            "model": searchModel(),
            "store": false,
            "tools": [["type": "web_search", "search_context_size": "medium"]],
            "instructions": "Research the question on the web and answer in a few plain sentences that will be read aloud. "
                + "Lead with the answer; include key numbers and dates. No Markdown, no URLs in the text.",
            "input": trimmed
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                let message = (object["error"] as? [String: Any])?["message"] as? String ?? "search failed"
                return JarvisProtocol.result(["ok": false, "error": message])
            }
            cost?.record(provider: .openAI, model: searchModel(),
                         usage: AITokenUsage(responsesAPI: object["usage"]))
            let sources = AIResponseStream.citations(inResponse: object).prefix(4).map { $0.url.host ?? $0.displayTitle }
            return JarvisProtocol.result(["ok": true, "answer": AIResponseStream.outputText(inResponse: object),
                                          "sources": Array(sources)])
        } catch {
            return JarvisProtocol.result(["ok": false, "error": error.localizedDescription])
        }
    }

    private func openWebsite(_ raw: String) -> JarvisToolOutcome {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return fail("Geçersiz adres.") }
        NSWorkspace.shared.open(url)
        return ok(["opened": url.host ?? text])
    }

    // MARK: - Apps and media

    private func openApplication(_ name: String) -> JarvisToolOutcome {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return fail("Uygulama adı yok.") }
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.activationPolicy == .regular && $0.localizedName?.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            running.activate()
            return ok(["opened": running.localizedName ?? wanted])
        }
        guard let url = Self.findApplication(named: wanted) else { return fail("\(wanted) bulunamadı.") }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return ok(["opened": url.deletingPathExtension().lastPathComponent])
    }

    /// Looks through the usual application folders, exact name first, then
    /// the closest one that contains what was said.
    private static func findApplication(named name: String) -> URL? {
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var candidates: [URL] = []
        for folder in folders {
            let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder),
                                                                     includingPropertiesForKeys: nil)) ?? []
            candidates += urls.filter { $0.pathExtension == "app" }
        }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        func appName(_ url: URL) -> String {
            FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        if let exact = candidates.first(where: {
            appName($0).compare(name, options: options) == .orderedSame
                || $0.deletingPathExtension().lastPathComponent.compare(name, options: options) == .orderedSame
        }) { return exact }
        return candidates.filter { appName($0).range(of: name, options: options) != nil }
            .min { appName($0).count < appName($1).count }
    }

    private func mediaControl(_ action: String) -> JarvisToolOutcome {
        switch action {
        case "play": if !media.isPlaying { media.playPause() }
        case "pause": if media.isPlaying { media.playPause() }
        case "next": media.nextTrack()
        case "previous": media.previousTrack()
        default: media.playPause()
        }
        if let error = media.errorMessage { return fail(error) }
        return ok(["action": action, "source": "\(media.source)", "title": media.title, "artist": media.artist])
    }

    // MARK: - Calendar

    private func calendar(days: Int) async -> JarvisToolOutcome {
        guard await access(to: .event) else { return fail("Takvim izni yok. Sistem Ayarları › Gizlilik › Takvimler.") }
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: start)) ?? start
        let predicate = events.predicateForEvents(withStart: start, end: end, calendars: nil)
        let items = events.events(matching: predicate).sorted { $0.startDate < $1.startDate }.prefix(25).map { event in
            ["title": event.title ?? "", "start": Self.display(event.startDate), "end": Self.display(event.endDate),
             "all_day": event.isAllDay, "location": event.location ?? ""] as [String: Any]
        }
        var result: [String: Any] = ["events": Array(items)]
        if await access(to: .reminder) {
            let reminders = await incompleteReminders()
            result["reminders"] = reminders
        }
        return ok(result)
    }

    private func incompleteReminders() async -> [[String: Any]] {
        let predicate = events.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let found: [(String, Date?)] = await withCheckedContinuation { continuation in
            events.fetchReminders(matching: predicate) { reminders in
                let values = (reminders ?? []).prefix(20).map { ($0.title ?? "", $0.dueDateComponents?.date) }
                continuation.resume(returning: Array(values))
            }
        }
        return found.map { title, due in
            var item: [String: Any] = ["title": title]
            if let due { item["due"] = Self.display(due) }
            return item
        }
    }

    private func addReminder(title: String, due: Date?) async -> JarvisToolOutcome {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fail("Başlık yok.") }
        guard await access(to: .reminder) else { return fail("Anımsatıcılar izni yok.") }
        guard let list = events.defaultCalendarForNewReminders() else { return fail("Anımsatıcı listesi yok.") }
        let reminder = EKReminder(eventStore: events)
        reminder.title = trimmed
        reminder.calendar = list
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try events.save(reminder, commit: true)
            notify("checklist", "Hatırlatıcı eklendi")
            return ok(["added": trimmed, "due": due.map(Self.display) ?? ""])
        } catch { return fail(error.localizedDescription) }
    }

    private func addEvent(title: String, start: Date?, end: Date?) async -> JarvisToolOutcome {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let start else { return fail("Başlık ya da başlangıç yok.") }
        guard await access(to: .event) else { return fail("Takvim izni yok.") }
        guard let calendar = events.defaultCalendarForNewEvents else { return fail("Takvim yok.") }
        let event = EKEvent(eventStore: events)
        event.title = trimmed
        event.calendar = calendar
        event.startDate = start
        event.endDate = end.flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(3600)
        do {
            try events.save(event, span: .thisEvent, commit: true)
            notify("calendar.badge.plus", "Takvime eklendi")
            return ok(["added": trimmed, "start": Self.display(start), "end": Self.display(event.endDate)])
        } catch { return fail(error.localizedDescription) }
    }

    private func access(to type: EKEntityType) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: type)
        if status == .fullAccess { return true }
        guard status == .notDetermined else { return false }
        NSApp.activate(ignoringOtherApps: true)
        do {
            return type == .event ? try await events.requestFullAccessToEvents()
                                  : try await events.requestFullAccessToReminders()
        } catch { return false }
    }

    // MARK: - Screen

    /// The display under the pointer, without MacB's own windows, scaled to at
    /// most 1600 pixels wide and JPEG-encoded in memory.
    private static func screenshot() async -> Result<Data, Error> {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            let screenID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            guard let display = content.displays.first(where: { $0.displayID == screenID }) ?? content.displays.first else {
                throw NSError(domain: "MacB.Jarvis", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ekran bulunamadı."])
            }
            let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            let scale = min(1, 1600 / Double(display.width))
            configuration.width = Int(Double(display.width) * scale)
            configuration.height = Int(Double(display.height) * scale)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else {
                throw NSError(domain: "MacB.Jarvis", code: 3, userInfo: [NSLocalizedDescriptionKey: "Görüntü hazırlanamadı."])
            }
            return .success(jpeg)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Helpers

    private func ok(_ fields: [String: Any]) -> JarvisToolOutcome {
        var all = fields
        all["ok"] = true
        return .result(JarvisProtocol.result(all))
    }

    private func fail(_ message: String) -> JarvisToolOutcome {
        .result(JarvisProtocol.result(["ok": false, "error": message]))
    }

    private static func display(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM EEEE HH:mm"
        return formatter.string(from: date)
    }
}
