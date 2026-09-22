import AppKit
import SwiftUI
import Combine
import ApplicationServices
import MacBCore

@main enum MacBMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnostics") {
            print("MacB \(AppVersion.current) (\(AppVersion.build))")
            print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            print("Accessibility: \(AXIsProcessTrusted())")
            print("Screen capture: \(CGPreflightScreenCaptureAccess())")
            print("Input monitoring: \(CGPreflightListenEventAccess())")
            print("Spotify installed: \(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil)")
            print("Displays: \(NSScreen.screens.count)")
            return
        }
        // Prints what the uninstaller would offer for one application and exits.
        // Nothing is recycled here: the point is to read the scan's verdicts
        // against real installs before trusting the review sheet with a Trash
        // operation.
        // Moves one already-listed cache folder to Trash, so the write path can be
        // exercised on a real disk without clicking through the review sheet. It
        // refuses anything the sweep would not have offered in the first place.
        if let index = CommandLine.arguments.firstIndex(of: "--sweep-cache"),
           CommandLine.arguments.count > index + 1 {
            let wanted = URL(fileURLWithPath: CommandLine.arguments[index + 1]).standardizedFileURL.path
            let service = CacheSweepService()
            guard let item = service.scan().first(where: { $0.url.path == wanted }) else {
                print("error: \(wanted) bu taramada yok")
                return
            }
            // Recycling wants a running main run loop, so this pumps it rather
            // than blocking on a semaphore and deadlocking against itself.
            let finished = Flag()
            Task {
                do {
                    try await service.moveToTrash([item])
                    print("\(item.displayPath) Çöp Sepeti'ne taşındı (\(item.sizeText))")
                } catch { print("error: \(error.localizedDescription)") }
                finished.set()
            }
            while !finished.isSet, RunLoop.current.run(mode: .default, before: .distantFuture) {}
            return
        }
        // Reports what the media services can actually see and control, so a
        // transport button that does nothing can be told apart from a missing
        // Automation grant without guessing.
        if CommandLine.arguments.contains("--media-probe") {
            let spotify = SpotifyService()
            let music = AppleMusicService()
            let browser = BrowserMediaService()
            let media = MediaService(spotify: spotify, appleMusic: music, browser: browser)
            media.start()
            media.setPanelVisible(true)
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline, RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2)) {}
            print("source: \(media.source)  playing: \(media.isPlaying)  running: \(media.isRunning)")
            print("title: \(media.title)  artist: \(media.artist)  artwork: \(media.artwork != nil)")
            print("spotify authorized: \(spotify.isAuthorized)  error: \(spotify.errorMessage ?? "—")")
            print("music authorized: \(music.isAuthorized)  error: \(music.errorMessage ?? "—")")
            if CommandLine.arguments.contains("--toggle") {
                media.playPause()
                let until = Date().addingTimeInterval(3)
                while Date() < until, RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2)) {}
                print("after toggle — playing: \(media.isPlaying)  error: \(spotify.errorMessage ?? "—")")
            }
            return
        }
        if CommandLine.arguments.contains("--lid-angle") {
            let sensor = LidAngleSensor()
            print(sensor.diagnostic)
            guard sensor.isAvailable else { return }
            print("6 saniye boyunca okunuyor, kapağı yavaşça oynat:")
            for _ in 0..<60 {
                let reading = sensor.read().map { String(format: "%.0f°", $0) } ?? "—"
                print("  \(reading)")
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            return
        }
        // Drives the screen blur by hand so it can be photographed without a
        // real lid: it runs the whole ramp once, then puts itself away.
        if CommandLine.arguments.contains("--blur-probe") {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            let overlay = LidBlurOverlay.shared
            overlay.prepare()
            let target = CommandLine.arguments.firstIndex(of: "--blur-probe")
                .flatMap { CommandLine.arguments.indices.contains($0 + 1) ? Double(CommandLine.arguments[$0 + 1]) : nil } ?? 1
            print("Blur \(target) seviyesine çıkacak, 4 saniye duracak. " +
                  "Pencere sunucusu: \(LidBlurOverlay.usesRealBlur ? "gerçek bulanıklık" : "malzeme katmanları")")
            // Driven by a timer under the real run loop rather than by hand.
            // A hand-turned `RunLoop.run(mode:before:)` never flushes the window
            // server transaction the blur radius rides on, so the probe used to
            // report success and photograph a perfectly sharp screen.
            var step = 0
            let steps = 40
            Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
                if step <= steps {
                    overlay.apply(progress: target * Double(step) / Double(steps))
                    step += 1
                    return
                }
                timer.invalidate()
                Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
                    overlay.hide()
                    print("Kapatıldı.")
                    application.terminate(nil)
                }
            }
            application.run()
            return
        }
        // Reports, and optionally sets, the macOS login item. Useful because
        // registration can only really be proved against the running system.
        if CommandLine.arguments.contains("--login-item") {
            let service = LoginItemService()
            if CommandLine.arguments.contains("--on") { service.setEnabled(true) }
            if CommandLine.arguments.contains("--off") { service.setEnabled(false) }
            service.refresh()
            print("Açılışta başlat: \(service.isEnabled ? "açık" : "kapalı")")
            if service.needsApproval { print("macOS onay bekliyor (Sistem Ayarları > Giriş Öğeleri)") }
            if let error = service.errorMessage { print(error) }
            return
        }
        if CommandLine.arguments.contains("--top-processes") {
            let monitor = ProcessMonitorService()
            monitor.refresh()
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline, RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2)) {}
            monitor.refresh()
            let second = Date().addingTimeInterval(3)
            while Date() < second, RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2)) {}
            print("— bellek —")
            for item in monitor.byMemory {
                print("  \(ByteCountFormatter.string(fromByteCount: Int64(item.memoryBytes), countStyle: .memory))\t\(item.cpuPercent)%\t\(item.name) (\(item.processCount))")
            }
            print("— işlemci —")
            for item in monitor.byCPU {
                print("  \(item.cpuPercent)%\t\(ByteCountFormatter.string(fromByteCount: Int64(item.memoryBytes), countStyle: .memory))\t\(item.name) (\(item.processCount))")
            }
            return
        }
        // Probes for the ring's text, shelf and window tools, so each can be
        // exercised on a real Mac without a trackpad gesture. They print
        // counts and results, never window titles or selected text beyond
        // what was passed in.
        if let probe = Probe.run(CommandLine.arguments) {
            let finished = Flag()
            Task { @MainActor in
                await probe()
                finished.set()
            }
            while !finished.isSet, RunLoop.current.run(mode: .default, before: .distantFuture) {}
            return
        }
        if CommandLine.arguments.contains("--scan-caches") {
            let items = CacheSweepService().scan()
            let total = items.reduce(Int64(0)) { $0 + $1.size }
            print("\(items.count) klasör · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
            for item in items {
                let busy = item.isInUse ? " [açık]" : ""
                print("  \(item.group.rawValue)\t\(item.sizeText)\t\(item.owner)\t\(item.displayPath)\(busy)")
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--scan-app"),
           CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            do {
                let report = try AppUninstallService().report(for: URL(fileURLWithPath: path))
                print("\(report.identity.name) — \(report.identity.bundleIdentifier)")
                print("team: \(report.identity.teamIdentifier ?? "—")  helpers: \(report.identity.helperIdentifiers.joined(separator: ", "))")
                print("running: \(report.runningProcessCount)")
                for candidate in report.candidates {
                    let admin = candidate.requiresAdministrator ? " [admin]" : ""
                    print("  \(candidate.confidence)\t\(candidate.kind.rawValue)\t\(candidate.sizeText)\t\(candidate.displayPath)\(admin)")
                }
            } catch { print("error: \(error.localizedDescription)") }
            return
        }
        let app = NSApplication.shared
        // Before the run loop, and it has to be: the window server will not
        // blur behind a window that was created after it started. See
        // `LidBlurOverlay.prepare()`.
        LidBlurOverlay.shared.prepare()
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

/// A one-way flag the command line waits on while the run loop turns.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let preferences = Preferences()
    private let permissions = PermissionStore()
    private let windows = WindowService()
    private let previews = PreviewService()
    private let spotify = SpotifyService()
    private let appleMusic = AppleMusicService()
    private let browserMedia = BrowserMediaService()
    private lazy var media = MediaService(spotify: spotify, appleMusic: appleMusic, browser: browserMedia)
    private let shelf = ShelfStore()
    private let favorites = FavoriteWindowStore()
    private let recentFiles = RecentFileStore()
    private let clipboardShelf = ClipboardShelfStore()
    private let fileActivity = FileActivityStore()
    private let tasks = TaskStore()
    private let camera = CameraPreviewService()
    private let biometricAuth = BiometricAuthService()
    private let recentTargets = RecentTargetStore()
    private let hotKey = HotKeyController()
    private let radialMenu = RadialMenuController()
    private let screenshots = ScreenshotWatcher()
    private lazy var windowLayout = WindowLayoutService(preferences: preferences)
    private let aiActivity = AIActivityService()
    private let systemMonitor = SystemMonitorService()
    private let processes = ProcessMonitorService()
    private let lid = LidAngleService()
    private let keyboardCleaning = KeyboardCleaningService()
    private let utilities = UtilityCoordinator()
    private let islandTimer = TimerService()
    private lazy var automation = AutomationService(media: media, timer: islandTimer,
                                                    systemMonitor: systemMonitor, lid: lid)
    private let launcher = AppLauncherStore()
    private let islandBackground = IslandBackgroundStore()
    private let weather = WeatherService()
    private lazy var faceUnlock = FaceUnlockService(biometrics: biometricAuth)
    private let systemEvents = SystemEventService()
    private let widgetLayout = IslandLayoutStore(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacB"))
    private let quickNote = QuickNoteStore()
    private let updates = UpdateService()
    private let loginItem = LoginItemService()
    private let aiKey = AIKeyStore()
    private let aiCost = AICostMeter()
    private lazy var assistant = AIAssistantService(
        keys: aiKey,
        model: { [weak self] provider in self?.preferences.model(for: provider) ?? provider.defaultModel },
        preferredProvider: { [weak self] in self?.preferences.preferredProvider },
        cost: aiCost)
    private let speech = SpeechInputService()
    private let selectedText = SelectedTextService()
    private let translator = OfflineTranslator()
    private let keepAwake = KeepAwakeService.shared
    private let arrangements = WindowArrangementService()
    private let jarvisHotKey = JarvisHotKey()
    private lazy var briefing = BriefingService(preferences: preferences, weather: weather,
                                                monitor: systemMonitor, activity: aiActivity, mail: mail)
    private let jarvisMemory = JarvisMemoryStore()
    private let agentJobs = AgentJobStore()
    private let agentCursor = AgentCursorOverlay()
    private let browserAgent = BrowserAgentService()
    private lazy var agentRunner = AgentJobRunner(
        store: agentJobs,
        engine: FreeVoiceEngine(
            keys: aiKey,
            model: { [weak self] provider in self?.preferences.model(for: provider) ?? provider.defaultModel },
            preferred: { [weak self] in AIProvider(rawValue: self?.preferences.aiProvider ?? "") },
            usesLocal: { [weak self] in self?.preferences.localModelEnabled ?? false }),
        cost: aiCost)
    private lazy var mail: MailService = {
        let service = MailService()
        service.importantSenders = { [weak self] in self?.preferences.importantSenders ?? [] }
        return service
    }()
    private lazy var scenarios = ScenarioStore(keepAwake: keepAwake, arrangements: arrangements,
                                               media: media, timer: islandTimer)
    private lazy var proactive = ProactiveService(
        preferences: preferences, mail: mail, jobs: agentJobs, briefing: briefing, faceUnlock: faceUnlock,
        present: { [weak self] event in self?.notch.showHeadsUp(event) })
    private lazy var watchers = WatchTaskStore(systemMonitor: systemMonitor, processes: processes,
                                               notify: { [weak self] symbol, message in self?.notifyIsland(symbol: symbol, message: message) })
    private lazy var jarvis = JarvisSession(
        keys: aiKey, memory: jarvisMemory, cost: aiCost,
        voice: { [weak self] in JarvisVoice(rawValue: self?.preferences.jarvisVoice ?? "") ?? .marin },
        persona: { [weak self] in JarvisPersona(rawValue: self?.preferences.jarvisPersona ?? "") ?? JarvisPersona.defaultPersona },
        scenarioNames: { [weak self] in self?.scenarios.scenarios.map(\.name) ?? [] },
        engineChoice: { [weak self] in
            JarvisEngineChoice(rawValue: self?.preferences.jarvisEngine ?? "") ?? .automatic
        },
        freeEngine: FreeVoiceEngine(
            keys: aiKey,
            model: { [weak self] provider in self?.preferences.model(for: provider) ?? provider.defaultModel },
            preferred: { [weak self] in AIProvider(rawValue: self?.preferences.aiProvider ?? "") },
            readsScreen: { [weak self] in self?.preferences.freeEngineReadsScreen ?? false },
            usesLocal: { [weak self] in self?.preferences.localModelEnabled ?? false }),
        model: { [weak self] in self?.preferences.jarvisModel ?? JarvisProtocol.defaultModel })
    private lazy var jarvisTools = MacBJarvisToolbox(
        keys: aiKey, searchModel: { [weak self] in self?.preferences.aiModel ?? Preferences.defaultAIModel },
        cost: aiCost,
        media: media, timer: islandTimer, windowLayout: windowLayout, arrangements: arrangements, note: quickNote,
        selection: selectedText, systemMonitor: systemMonitor, weather: weather, aiActivity: aiActivity,
        memory: jarvisMemory, scenarios: scenarios, watchers: watchers, browserAgent: browserAgent, mail: mail, jobs: agentJobs,
        notify: { [weak self] symbol, message in self?.notifyIsland(symbol: symbol, message: message) })
    private lazy var aiPanel = AIPanelController(assistant: assistant, speech: speech,
                                                 selection: selectedText) { [weak self] in
        UserDefaults.standard.set("Araçlar", forKey: "settingsPage")
        self?.showSettings()
    }
    private lazy var dock = DockController(windowService: windows, previewService: previews, preferences: preferences,
                                           favorites: favorites, recentTargets: recentTargets)
    private lazy var notch = NotchController(media: media, shelf: shelf, preferences: preferences,
                                            recentFiles: recentFiles, clipboard: clipboardShelf,
                                            fileActivity: fileActivity, tasks: tasks, camera: camera,
                                            auth: biometricAuth, recentTargets: recentTargets,
                                            aiActivity: aiActivity, systemMonitor: systemMonitor,
                                            processes: processes, watchers: watchers, lid: lid,
                                            keyboardCleaning: keyboardCleaning,
                                            timer: islandTimer, widgets: widgetLayout, launcher: launcher,
                                            background: islandBackground, weather: weather,
                                            note: quickNote,
                                            faceUnlock: faceUnlock,
                                            systemEvents: systemEvents,
                                            assistant: jarvis,
                                            briefing: briefing,
                                            jobs: agentJobs,
                                            approveProposal: { [weak self] proposal, job in
                                                Task { await self?.agentRunner.approve(proposal, in: job) }
                                            },
                                            refuseProposal: { [weak self] proposal, job in
                                                self?.agentRunner.refuse(proposal, in: job)
                                            },
                                            openSettings: { [weak self] in self?.showSettings() })
    private lazy var switcher = SwitcherController(windowService: windows, previewService: previews,
                                                   preferences: preferences, favorites: favorites,
                                                   permissions: permissions)
    private lazy var autoQuit = AutoQuitOnCloseService(preferences: preferences)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var layoutMenuItem: NSMenuItem?
    private var keepAwakeMenu: NSMenu?
    private var arrangementMenu: NSMenu?
    private var scenarioMenu: NSMenu?
    private var updateMenuItem: NSMenuItem?
    private var subscriptions: Set<AnyCancellable> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isSleeping = false
    private var isSessionInactive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let identifier = Bundle.main.bundleIdentifier ?? "dev.hamzababal.MacB"
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        applyActivationPolicy()
        observeBriefing()
        // An older MacB could leave the macOS indicator helper stopped. Undo it
        // once, before anything else, so nobody is left without indicators.
        SystemHUDRepair.resumeIndicatorHelper()
        buildMainMenu()
        buildMenu()
        hotKey.onPress = { [weak self] backwards in
            guard let self, self.preferences.switcherEnabled else { return }
            self.permissions.refresh()
            guard self.permissions.accessibility else { self.showSettings(); return }
            self.switcher.begin(backwards: backwards, shortcut: self.hotKey.activeShortcut ?? self.preferences.shortcut)
        }
        radialMenu.perform = { [weak self] slot in
            switch slot {
            case .action(let action): self?.performRadialAction(action)
            // Exactly what a double-click in Finder would do, and nothing more.
            case .open(let path): NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        }
        radialMenu.hasAccessibility = { [weak self] in self?.permissions.accessibility ?? false }
        jarvis.toolbox = jarvisTools
        // A goodbye, a quiet spell or the hard limit ends the conversation on
        // its own; the island has to follow it back to normal.
        jarvis.onEnded = { [weak self] in self?.notch.assistantFinished() }
        jarvisHotKey.onPress = { [weak self] in self?.toggleJarvis() }
        switcher.onWillOpen = { [weak self] in
            self?.dock.dismiss()
            self?.dock.enabled = false
            self?.notch.closePanel()
        }
        // Dock input is re-enabled after the switcher closes, without polling when idle.
        NotificationCenter.default.addObserver(self, selector: #selector(switcherClosed), name: Notification.Name("MacBSwitcherClosed"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        preferences.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyPreferences() }
        }.store(in: &subscriptions)
        permissions.$accessibility.removeDuplicates().dropFirst().sink { [weak self] granted in
            guard let self else { return }
            if !granted { self.dock.dismiss(); self.switcher.dismiss() }
            else if self.preferences.switcherEnabled { self.hotKey.register(self.preferences.shortcut) }
            self.windowLayout.setEnabled(granted && self.preferences.windowManagementEnabled)
            self.autoQuit.setEnabled(granted && self.preferences.quitAppsWhenLastWindowCloses)
        }.store(in: &subscriptions)
        permissions.$inputMonitoring.removeDuplicates().dropFirst().sink { [weak self] granted in
            guard let self, granted, self.preferences.switcherEnabled,
                  self.preferences.shortcut == .commandTab else { return }
            self.hotKey.register(.commandTab)
        }.store(in: &subscriptions)
        setupWorkspaceObservers()
        media.start()
        aiActivity.start()
        systemMonitor.start()
        processes.start()
        watchers.start()
        // Runs while the screen is locked too: that is when "away" begins.
        proactive.start()
        lid.setOpenAngle(preferences.lidHingeAngle)
        lid.setEnabled(preferences.lidHingeEnabled)
        applyPreferences()
        updates.$state.removeDuplicates().sink { [weak self] state in
            self?.refreshUpdateMenu(for: state)
        }.store(in: &subscriptions)
        updates.checkAutomatically()
        if CommandLine.arguments.contains("--smoke-test") {
            NSLog("MacB smoke: application launched; menu and services initialized")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) }
        } else if CommandLine.arguments.contains("--show-panel") {
            notch.openPanel()
        } else if CommandLine.arguments.contains("--preview-home") {
            notch.showDevelopmentPreview(phase: .expanded, content: .home)
        } else if let index = CommandLine.arguments.firstIndex(of: "--preview-uninstall"),
                  CommandLine.arguments.count > index + 1 {
            UserDefaults.standard.set("Araçlar", forKey: "settingsPage")
            utilities.inspectApplication(at: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            showSettings()
        } else if CommandLine.arguments.contains("--preview-caches") {
            UserDefaults.standard.set("Araçlar", forKey: "settingsPage")
            utilities.scanCaches()
            showSettings()
        } else if CommandLine.arguments.contains("--preview-library") {
            widgetLayout.isEditing = true
            notch.showDevelopmentPreview(phase: .expanded, content: .home)
        } else if CommandLine.arguments.contains("--preview-automation") {
            preferences.automationEnabled = true
            UserDefaults.standard.set("Otomasyon", forKey: "settingsPage")
            showSettings()
        } else if CommandLine.arguments.contains("--preview-lid") {
            UserDefaults.standard.set("Görünüm", forKey: "settingsPage")
            UserDefaults.standard.set(SettingsView.hingeAnchor, forKey: "settingsAnchor")
            showSettings()
        } else if CommandLine.arguments.contains("--preview-processes") {
            UserDefaults.standard.set("Araçlar", forKey: "settingsPage")
            showSettings()
        } else if CommandLine.arguments.contains("--preview-widgets") {
            // Only for this run. Turning widgets on used to go through add(),
            // which writes widgets.json, so every screenshot taken with this
            // flag permanently rearranged the strip the user had set up.
            for kind in [IslandWidgetKind.battery, .storage, .shelf, .notes, .worldClock, .topProcesses] {
                guard let widget = widgetLayout.layout.widgets.first(where: { $0.kind == kind }) else { continue }
                widgetLayout.setEnabledWithoutSaving(id: widget.id, true)
            }
            notch.showDevelopmentPreview(phase: .expanded, content: .home)
        } else if CommandLine.arguments.contains("--preview-active-timer") {
            islandTimer.start()
            notch.showDevelopmentPreview(phase: .expanded, content: .home)
        } else if CommandLine.arguments.contains("--preview-peek") {
            notch.showDevelopmentPreview(phase: .peek)
        } else if CommandLine.arguments.contains("--preview-files") {
            notch.showDevelopmentPreview(phase: .expanded, content: .files)
        } else if CommandLine.arguments.contains("--preview-clipboard") {
            notch.showDevelopmentPreview(phase: .expanded, content: .clipboard)
        } else if CommandLine.arguments.contains("--preview-drop") {
            notch.showDevelopmentPreview(phase: .expanded, content: .files, dropping: true)
        } else if CommandLine.arguments.contains("--preview-assistant") {
            // The island's assistant section without a conversation behind it,
            // so its layout can be looked at without opening a microphone.
            notch.showDevelopmentPreview(phase: .expanded, content: .assistant)
        } else if CommandLine.arguments.contains("--preview-timer") {
            notch.showDevelopmentPreview(phase: .expanded, content: .timer)
        } else if CommandLine.arguments.contains("--preview-apps") {
            notch.showDevelopmentPreview(phase: .expanded, content: .apps)
        } else if CommandLine.arguments.contains("--preview-switcher") {
            switcher.showDevelopmentPreview()
        } else if CommandLine.arguments.contains("--preview-onboarding") {
            showOnboarding()
        } else if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") && !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showOnboarding()
        } else if CommandLine.arguments.contains("--show-settings") {
            showSettings()
        } else if UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
    }

    /// The menu bar MacB never shows, which is the only reason ⌘V works.
    ///
    /// An accessory application has no menu bar on screen, so this was left out
    /// — and text fields stopped taking ⌘C, ⌘V, ⌘X and ⌘A, because those are
    /// not built into the text system. They are key equivalents on the standard
    /// Edit menu, and a responder chain with no main menu has nothing to match
    /// them against. Typing worked; pasting an API key did not, which is the one
    /// field nobody types by hand.
    ///
    /// The items are never seen. They exist to be matched.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ayarlar ve izinler…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Pencereyi gizle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "MacB'den çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Düzen")
        edit.addItem(withTitle: "Geri al", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Sil", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Tümünü seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "MacB")
        item.button?.toolTip = "MacB — Pencereler ve dosya rafı"
        let menu = NSMenu()
        menu.addItem(withTitle: "MacB", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let open = menu.addItem(withTitle: "Paneli aç", action: #selector(openNotch), keyEquivalent: "")
        open.target = self
        let add = menu.addItem(withTitle: "Rafa dosya ekle…", action: #selector(addFiles), keyEquivalent: "")
        add.target = self
        let layouts = NSMenu(title: "Pencere Yerleşimi")
        [("Sol yarı", WindowLayoutAction.leftHalf), ("Sağ yarı", .rightHalf), ("Üst yarı", .topHalf),
         ("Alt yarı", .bottomHalf), ("Büyüt", .maximize), ("Ortala", .center),
         ("Önceki boyut", .restore), ("Sonraki ekran", .nextDisplay)].forEach { title, action in
            let item = layouts.addItem(withTitle: title, action: #selector(performWindowLayout(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = action.rawValue
        }
        let layoutRoot = menu.addItem(withTitle: "Pencere Yerleşimi", action: nil, keyEquivalent: "")
        menu.setSubmenu(layouts, for: layoutRoot)
        layoutMenuItem = layoutRoot
        let arrangementMenu = NSMenu(title: "Pencere düzenleri")
        arrangementMenu.delegate = self
        self.arrangementMenu = arrangementMenu
        menu.setSubmenu(arrangementMenu, for: menu.addItem(withTitle: "Pencere düzenleri", action: nil, keyEquivalent: ""))
        let ask = menu.addItem(withTitle: "Yapay zekâya sor…", action: #selector(openAIPanel), keyEquivalent: "")
        ask.target = self
        let talk = menu.addItem(withTitle: "MacB ile konuş (\(JarvisHotKey.displayKeys))", action: #selector(toggleJarvis), keyEquivalent: "")
        talk.target = self
        let scenarioMenu = NSMenu(title: "Senaryolar")
        scenarioMenu.delegate = self
        self.scenarioMenu = scenarioMenu
        menu.setSubmenu(scenarioMenu, for: menu.addItem(withTitle: "Senaryolar", action: nil, keyEquivalent: ""))
        let brief = menu.addItem(withTitle: "Brifingi göster", action: #selector(showBriefing), keyEquivalent: "")
        brief.target = self
        let awakeMenu = NSMenu(title: "Uyanık tut")
        awakeMenu.delegate = self
        keepAwakeMenu = awakeMenu
        menu.setSubmenu(awakeMenu, for: menu.addItem(withTitle: "Uyanık tut", action: nil, keyEquivalent: ""))
        let sleepItem = menu.addItem(withTitle: "Mac'i uyut", action: #selector(sleepMac), keyEquivalent: "")
        sleepItem.target = self
        let cleanKeyboard = menu.addItem(withTitle: "Klavyeyi 1 dakika kilitle", action: #selector(startKeyboardCleaning), keyEquivalent: "")
        cleanKeyboard.target = self
        let settings = menu.addItem(withTitle: "Ayarlar ve izinler…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let guide = menu.addItem(withTitle: "Başlangıç rehberi…", action: #selector(showOnboarding), keyEquivalent: "")
        guide.target = self
        let updates = menu.addItem(withTitle: "Güncellemeleri denetle…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        updateMenuItem = updates
        menu.addItem(.separator())
        menu.addItem(withTitle: "MacB’den çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// The two submenus whose contents change: rebuilt each time they open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu === keepAwakeMenu {
            if keepAwake.isActive {
                menu.addItem(withTitle: keepAwake.endDate == nil ? "Açık, süresiz" : "Açık · \(keepAwake.remainingText) kaldı",
                             action: nil, keyEquivalent: "")
                let off = menu.addItem(withTitle: "Kapat", action: #selector(stopKeepAwake), keyEquivalent: "")
                off.target = self
                menu.addItem(.separator())
            }
            for minutes in KeepAwakeDuration.choices {
                let item = menu.addItem(withTitle: KeepAwakeDuration.title(minutes: minutes),
                                        action: #selector(startKeepAwake(_:)), keyEquivalent: "")
                item.target = self
                item.tag = minutes
            }
        } else if menu === arrangementMenu {
            let trusted = permissions.accessibility
            for arrangement in arrangements.arrangements.sorted(by: { $0.savedAt > $1.savedAt }) {
                let item = menu.addItem(withTitle: arrangement.name, action: #selector(applyArrangement(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = arrangement.id.uuidString
                item.isEnabled = trusted
            }
            if !arrangements.arrangements.isEmpty { menu.addItem(.separator()) }
            let save = menu.addItem(withTitle: "Şimdiki düzeni kaydet", action: #selector(saveArrangement), keyEquivalent: "")
            save.target = self
            save.isEnabled = trusted
            let manage = menu.addItem(withTitle: "Düzenleri yönet…", action: #selector(showArrangementSettings), keyEquivalent: "")
            manage.target = self
        } else if menu === scenarioMenu {
            for scenario in scenarios.scenarios where scenario.isRunnable {
                let item = menu.addItem(withTitle: scenario.name, action: #selector(runScenario(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = scenario.id.uuidString
            }
            if scenarios.scenarios.contains(where: \.isRunnable) { menu.addItem(.separator()) }
            let manage = menu.addItem(withTitle: "Senaryoları yönet…", action: #selector(showScenarioSettings),
                                      keyEquivalent: "")
            manage.target = self
        }
    }

    @objc private func runScenario(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let scenario = scenarios.scenarios.first(where: { $0.id.uuidString == identifier }) else { return }
        Task { [weak self] in
            guard let self else { return }
            let message = await self.scenarios.run(scenario)
            self.notch.notify(symbol: "wand.and.stars", message: message)
        }
    }

    @objc private func showScenarioSettings() {
        UserDefaults.standard.set("Araçlar", forKey: "settingsPage")
        showSettings()
    }

    @objc private func sleepMac() {
        SystemActions.power(.sleep)
    }

    @objc private func showBriefing() {
        briefing.give()
    }

    @objc private func startKeepAwake(_ sender: NSMenuItem) { startKeepAwake(minutes: sender.tag) }
    @objc private func stopKeepAwake() {
        keepAwake.stop()
        notch.notify(symbol: "moon.zzz", message: "Uyanık tutma kapandı")
    }
    private func startKeepAwake(minutes: Int) {
        guard keepAwake.start(minutes: minutes) else {
            notch.notify(symbol: "exclamationmark.triangle", message: "Uyanık tutulamadı")
            return
        }
        notch.notify(symbol: "cup.and.heat.waves", message: "Uyanık · \(KeepAwakeDuration.title(minutes: minutes).lowercased())")
    }

    @objc private func applyArrangement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw),
              let arrangement = arrangements.arrangements.first(where: { $0.id == id }) else { return }
        arrangements.apply(arrangement)
        if let message = arrangements.lastMessage { notch.notify(symbol: "rectangle.3.group", message: message) }
    }

    @objc private func saveArrangement() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMM HH:mm"
        let name = "\(WindowArrangementService.currentSignature().summary) · \(formatter.string(from: Date()))"
        arrangements.saveCurrent(named: name)
        if let message = arrangements.lastMessage { notch.notify(symbol: "rectangle.3.group", message: message) }
    }

    @objc private func showArrangementSettings() {
        UserDefaults.standard.set("Pencereler", forKey: "settingsPage")
        showSettings()
    }

    /// Reads the selection in the application in front and hands it to `work`,
    /// or says in the AI panel why there is nothing to work on.
    private func withSelection(_ work: @escaping (SelectedTextService.Selection) -> Void) {
        permissions.refresh()
        guard permissions.accessibility else { return showSettings() }
        Task { @MainActor in
            switch await selectedText.read() {
            case .success(let selection): work(selection)
            case .failure(let failure):
                assistant.report(failure.message)
                aiPanel.show(focusQuestion: false)
            }
        }
    }

    /// Summarise or fix. Without a key nothing is read at all — not even the
    /// clipboard fallback — since there would be nowhere to send it.
    private func runOnSelection(_ task: AITextTask) {
        guard assistant.hasKey else {
            assistant.report(AIAssistantService.missingKeyMessage)
            return aiPanel.show(focusQuestion: false)
        }
        withSelection { [weak self] selection in
            self?.assistant.run(task, on: selection)
            self?.aiPanel.show(focusQuestion: false)
        }
    }

    private func translateSelection() {
        withSelection { [weak self] selection in self?.translate(selection) }
    }

    private func translate(_ selection: SelectedTextService.Selection) {
        Task { @MainActor in
            switch await self.translator.translate(selection.text, preferredTarget: self.preferences.translationTarget) {
            case .success(let result):
                let question = "Çeviri, \(OfflineTranslator.Failure.name(result.source)) → "
                    + "\(OfflineTranslator.Failure.name(result.target)): “\(AITextTask.preview(selection.text))”"
                self.assistant.show(localResult: result.text, question: question, selection: selection)
                self.aiPanel.show(focusQuestion: false)
            case .failure(let failure):
                var download: AIAssistantService.LanguageDownload?
                if case .notDownloaded(let source, let target) = failure {
                    download = .init(source: source, target: target) { [weak self] in
                        self?.translate(selection)
                    }
                }
                self.assistant.report(failure.message, download: download)
                self.aiPanel.show(focusQuestion: false)
            }
        }
    }

    private func applyPreferences() {
        guard !isSleeping, !isSessionInactive else { return }
        dock.enabled = preferences.dockEnabled && !switcher.isVisible
        if preferences.dockEnabled { dock.start() } else { dock.stop() }
        notch.enabled = preferences.notchEnabled
        if preferences.notchEnabled { notch.start() } else { notch.stop() }
        if preferences.switcherEnabled { hotKey.register(preferences.shortcut) }
        else { hotKey.unregister(); switcher.dismiss() }
        windowLayout.setEnabled(preferences.windowManagementEnabled)
        autoQuit.setEnabled(permissions.accessibility && preferences.quitAppsWhenLastWindowCloses)
        radialMenu.setLayout(preferences.radialMenuLayout, perApp: preferences.radialMenuAppLayouts)
        radialMenu.setTranslucency(preferences.radialMenuTranslucency)
        radialMenu.setScale(preferences.radialMenuScale)
        radialMenu.setThreeFingerTap(preferences.radialMenuThreeFinger
                                     && preferences.radialMenuEnabled
                                     && permissions.accessibility)
        radialMenu.setEnabled(preferences.radialMenuEnabled && permissions.accessibility)
        jarvisHotKey.setEnabled(preferences.jarvisHotKeyEnabled)
        lid.setOpenAngle(preferences.lidHingeAngle)
        lid.setEnabled(preferences.lidHingeEnabled && preferences.notchEnabled)
        automation.notice = { [weak self] text in self?.notch.showRuleNotice(text) }
        automation.setEnabled(preferences.automationEnabled && preferences.notchEnabled)
        recentFiles.enabled = preferences.recentFilesEnabled
        screenshots.onScreenshot = { [weak self] url in
            guard let self else { return }
            self.shelf.add(urls: [url])
            self.notch.showRuleNotice("Ekran görüntüsü rafta")
        }
        screenshots.setEnabled(preferences.screenshotShelfEnabled)
        clipboardShelf.maximumHistoryCount = preferences.clipboardHistoryLimit
        clipboardShelf.keepsHistory = preferences.clipboardKeepsHistory
        clipboardShelf.enabled = preferences.clipboardShelfEnabled
        fileActivity.enabled = preferences.fileActivityEnabled
        layoutMenuItem?.isEnabled = preferences.windowManagementEnabled && permissions.accessibility
        // Existing hosting view observes preferences; preserve its sidebar selection.
    }

    /// Runs one slice of the ring.
    ///
    /// Everything here is something the menu bar already offers, on purpose: the
    /// ring is a faster way to reach what MacB does, not a second set of
    /// behaviours that only exists on a gesture.
    private func performRadialAction(_ action: RadialAction) {
        switch action {
        case .island: openNotch()
        case .shelf: openIsland(showing: .files)
        case .clipboard: openIsland(showing: .clipboard)
        case .timer: openIsland(showing: .timer)
        case .quickNote: openQuickNote()
        case .switcher:
            permissions.refresh()
            guard permissions.accessibility else { return showSettings() }
            switcher.begin(backwards: false, shortcut: hotKey.activeShortcut ?? preferences.shortcut)
        case .keyboardLock: startKeyboardCleaning()
        case .windowLeft: windowLayout.perform(.leftHalf)
        case .windowRight: windowLayout.perform(.rightHalf)
        case .windowMaximize: windowLayout.perform(.maximize)
        case .windowCenter: windowLayout.perform(.center)
        case .windowNextDisplay: windowLayout.perform(.nextDisplay)
        case .settings: showSettings()
        case .askAI: aiPanel.show()
        case .jarvis: toggleJarvis()
        case .voiceAsk: aiPanel.showListening()
        case .summarizeSelection: runOnSelection(.summarize)
        case .fixSelection: runOnSelection(.fix)
        case .translateSelection: translateSelection()
        case .keepAwake:
            if keepAwake.isActive { stopKeepAwake() } else { startKeepAwake(minutes: preferences.keepAwakeMinutes) }
        case .applyArrangement:
            permissions.refresh()
            guard permissions.accessibility else { return showSettings() }
            notch.notify(symbol: "rectangle.3.group", message: arrangements.applyPreferred())
        }
    }

    /// Opens the island with the cursor already in the note card.
    ///
    /// The card lives on the widget strip, which somebody may have switched off.
    /// Aiming at "Hızlı not" is a clear enough request to turn it back on, and
    /// the island says so rather than doing it quietly.
    private func openQuickNote() {
        openIsland(showing: .home)
        let turnedOn = widgetLayout.enable(kind: .notes)
        if turnedOn { notch.notify(symbol: "square.and.pencil", message: "Not kartı açıldı") }
        // One turn of the run loop, so the card exists to take the cursor.
        DispatchQueue.main.asyncAfter(deadline: .now() + (turnedOn ? 0.35 : 0.12)) {
            NotificationCenter.default.post(name: .macBFocusQuickNote, object: nil)
        }
    }

    /// Opens the island on MacB's voice assistant, or ends the conversation
    /// if one is already running.
    @objc private func toggleJarvis() {
        if notch.isAssistantVisible {
            notch.stopAssistant()
            return
        }
        aiPanel.close()
        if !preferences.notchEnabled { preferences.notchEnabled = true }
        notch.startAssistant()
    }

    private func openIsland(showing content: NotchContent) {
        if !preferences.notchEnabled { preferences.notchEnabled = true }
        notch.start()
        notch.openPanel(showing: content)
    }

    @objc private func switcherClosed() { dock.enabled = preferences.dockEnabled && !isSleeping && !isSessionInactive }
    @objc private func displayChanged() {
        switcher.dismiss()
        dock.dismiss()
        guard permissions.accessibility else { return }
        arrangements.displaysChanged { [weak self] message in
            self?.notch.notify(symbol: "rectangle.3.group", message: message)
        }
    }
    @objc private func openNotch() {
        if !preferences.notchEnabled { preferences.notchEnabled = true }
        notch.start()
        notch.openPanel()
    }
    @objc private func addFiles() { shelf.chooseFiles(); openNotch() }
    @objc private func openAIPanel() { aiPanel.show() }
    @objc private func startKeyboardCleaning() { keyboardCleaning.start(duration: 60) }
    @objc private func checkForUpdates() { updates.check() }
    @objc private func performWindowLayout(_ sender: NSMenuItem) {
        guard preferences.windowManagementEnabled, let raw = sender.representedObject as? String,
              let action = WindowLayoutAction(rawValue: raw) else { return }
        windowLayout.perform(action)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "MacB"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.minSize = NSSize(width: 600, height: 560)
            window.setFrameAutosaveName("MacBSettings")
            window.center()
            settingsWindow = window
        }
        refreshSettingsContent()
        permissions.startObserving()
        shelf.refreshAvailability()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 470),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "MacB’ye Hoş Geldin"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.contentView = NSHostingView(rootView: OnboardingView(preferences: preferences, permissions: permissions) { [weak self, weak window] in
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                UserDefaults.standard.set(true, forKey: "hasLaunched")
                self?.applyPreferences()
                self?.permissions.stopObserving()
                window?.close()
                DispatchQueue.main.async { self?.showSettings() }
            })
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }


    private func notifyIsland(symbol: String, message: String) {
        notch.notify(symbol: symbol, message: message)
    }

    private func refreshSettingsContent() {
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, permissions: permissions,
            spotify: spotify, appleMusic: appleMusic, browserMedia: browserMedia, camera: camera, shelf: shelf, hotKey: hotKey,
            utilities: utilities, aiActivity: aiActivity, systemMonitor: systemMonitor,
            processes: processes, lid: lid, keyboardCleaning: keyboardCleaning,
            updates: updates, widgets: widgetLayout, background: islandBackground, weather: weather,
            faceUnlock: faceUnlock, launcher: launcher, automation: automation,
            loginItem: loginItem, aiKey: aiKey, aiCost: aiCost, mail: mail, briefing: briefing, scenarios: scenarios,
            assistant: assistant,
            arrangements: arrangements, keepAwake: keepAwake, watchers: watchers, agentCursor: agentCursor,
            autoQuit: autoQuit,
            jarvisHotKeyFailed: jarvisHotKey.failed, jarvisMemory: jarvisMemory,
            openPanel: { [weak self] in self?.openNotch() }))
    }

    /// Whether MacB has a Dock icon and shows up in ⌘Tab.
    ///
    /// An accessory application has neither, which is right for something that
    /// lives in the notch — and wrong the moment somebody goes looking for it
    /// in the switcher and cannot find it. So it is a setting, and this is the
    /// one place that applies it.
    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(preferences.showInDock ? .regular : .accessory)
    }

    /// Puts the briefing in the island as soon as it has something to say.
    private func observeBriefing() {
        briefing.$lines
            .receive(on: RunLoop.main)
            .sink { [weak self] lines in
                guard let self else { return }
                if lines.isEmpty { self.notch.dismissBriefing() } else { self.notch.showBriefing() }
            }
            .store(in: &subscriptions)
        preferences.$showInDock
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyActivationPolicy() }
            .store(in: &subscriptions)
        briefing.startObserving()
        observeAgentJobs()
    }

    /// Background jobs: run them, and put what they found in front of the user
    /// when the user is actually there.
    ///
    /// "There" is the screen being unlocked or the session becoming active —
    /// somebody sitting back down. A report that appears while the Mac is
    /// locked is a report nobody sees, and one that appears mid-sentence
    /// interrupts a conversation to talk about something else.
    private func observeAgentJobs() {
        agentRunner.toolbox = jarvisTools
        jarvisTools.startJob = { [weak self] task in
            guard let self, self.agentJobs.add(request: task) != nil else { return false }
            self.agentRunner.pump()
            return true
        }
        agentRunner.onFinished = { [weak self] job in
            guard let self else { return }
            self.notch.notify(symbol: job.state.symbol, message: job.title)
            // Only if somebody is here. Otherwise it waits, which is the whole
            // point of having asked for it before leaving.
            if !self.isSleeping && !self.isSessionInactive { self.deliverAgentReports() }
        }
        agentJobs.$jobs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.agentRunner.pump() }
            .store(in: &subscriptions)
    }

    private func deliverAgentReports() {
        guard !agentJobs.waiting.isEmpty else { return }
        notch.showAgentReport()
    }

    private func refreshUpdateMenu(for state: UpdateService.State) {
        switch state {
        case .checking: updateMenuItem?.title = "Güncellemeler denetleniyor…"
        case .available(let version): updateMenuItem?.title = "MacB \(version) sürümünü indir…"
        case .current: updateMenuItem?.title = "MacB güncel"
        case .failed: updateMenuItem?.title = "Güncelleme denetlenemedi"
        case .idle: updateMenuItem?.title = "Güncellemeleri denetle…"
        }
        updateMenuItem?.action = #selector(updateMenuAction)
    }

    @objc private func updateMenuAction() {
        if case .available = updates.state { updates.openReleases() }
        else { updates.check() }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.settingsWindow?.isVisible != true && self.onboardingWindow?.isVisible != true {
                self.permissions.stopObserving()
            }
        }
    }

    /// Closing Settings or onboarding must not shut MacB down. It owns menu-bar,
    /// island and background services, so the app stays alive until the user
    /// explicitly quits it from the menu.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self as AppDelegate? else { return }
                self.isSleeping = true
                self.suspendServices()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self as AppDelegate? else { return }
                self.isSleeping = false
                self.resumeServicesIfActive()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self as AppDelegate? else { return }
                self.isSessionInactive = true
                self.suspendServices()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self as AppDelegate? else { return }
                self.isSessionInactive = false
                self.resumeServicesIfActive()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.switcher.dismiss()
                self?.dock.dismiss()
                self?.notch.closePanel()
            }
        })
    }

    private func suspendServices() {
        speech.cancel()
        notch.stopAssistant()
        switcher.dismiss()
        dock.stop()
        notch.stop()
        media.stop()
        hotKey.unregister()
        windowLayout.stop()
        aiActivity.stop()
        systemMonitor.stop()
        processes.stop()
        watchers.stop()
        keyboardCleaning.stop()
        recentFiles.stop()
        clipboardShelf.stop()
        fileActivity.stop()
        camera.stop()
        faceUnlock.suspend()
        biometricAuth.reset()
    }

    private func resumeServicesIfActive() {
        guard !isSleeping, !isSessionInactive else { return }
        permissions.refresh()
        shelf.refreshAvailability()
        media.start()
        aiActivity.start()
        systemMonitor.start()
        processes.start()
        watchers.start()
        applyPreferences()
        // Somebody has just sat back down. This is the moment a job that
        // finished while they were gone is worth showing.
        deliverAgentReports()
    }

    func applicationWillTerminate(_ notification: Notification) {
        speech.cancel()
        jarvis.stop()
        keepAwake.stop()
        hotKey.unregister()
        windowLayout.stop()
        switcher.dismiss()
        dock.stop()
        notch.stop()
        media.stop()
        aiActivity.stop()
        systemMonitor.stop()
        processes.stop()
        watchers.stop()
        keyboardCleaning.stop()
        recentFiles.stop()
        clipboardShelf.stop()
        fileActivity.stop()
        camera.stop()
        faceUnlock.suspend()
        biometricAuth.reset()
        permissions.stopObserving()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        NotificationCenter.default.removeObserver(self)
    }
}
