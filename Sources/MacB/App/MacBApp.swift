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
            let overlay = LidBlurOverlay()
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

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
    private lazy var dock = DockController(windowService: windows, previewService: previews, preferences: preferences,
                                           favorites: favorites, recentTargets: recentTargets)
    private lazy var notch = NotchController(media: media, shelf: shelf, preferences: preferences,
                                            recentFiles: recentFiles, clipboard: clipboardShelf,
                                            fileActivity: fileActivity, tasks: tasks, camera: camera,
                                            auth: biometricAuth, recentTargets: recentTargets,
                                            aiActivity: aiActivity, systemMonitor: systemMonitor,
                                            processes: processes, lid: lid,
                                            keyboardCleaning: keyboardCleaning,
                                            timer: islandTimer, widgets: widgetLayout, launcher: launcher,
                                            background: islandBackground, weather: weather,
                                            note: quickNote,
                                            faceUnlock: faceUnlock,
                                            systemEvents: systemEvents,
                                            openSettings: { [weak self] in self?.showSettings() })
    private lazy var switcher = SwitcherController(windowService: windows, previewService: previews,
                                                   preferences: preferences, favorites: favorites,
                                                   permissions: permissions)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var layoutMenuItem: NSMenuItem?
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
        NSApp.setActivationPolicy(.accessory)
        // An older MacB could leave the macOS indicator helper stopped. Undo it
        // once, before anything else, so nobody is left without indicators.
        SystemHUDRepair.resumeIndicatorHelper()
        buildMenu()
        hotKey.onPress = { [weak self] backwards in
            guard let self, self.preferences.switcherEnabled else { return }
            self.permissions.refresh()
            guard self.permissions.accessibility else { self.showSettings(); return }
            self.switcher.begin(backwards: backwards, shortcut: self.hotKey.activeShortcut ?? self.preferences.shortcut)
        }
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

    private func applyPreferences() {
        guard !isSleeping, !isSessionInactive else { return }
        dock.enabled = preferences.dockEnabled && !switcher.isVisible
        if preferences.dockEnabled { dock.start() } else { dock.stop() }
        notch.enabled = preferences.notchEnabled
        if preferences.notchEnabled { notch.start() } else { notch.stop() }
        if preferences.switcherEnabled { hotKey.register(preferences.shortcut) }
        else { hotKey.unregister(); switcher.dismiss() }
        windowLayout.setEnabled(preferences.windowManagementEnabled)
        lid.setOpenAngle(preferences.lidHingeAngle)
        lid.setEnabled(preferences.lidHingeEnabled && preferences.notchEnabled)
        automation.notice = { [weak self] text in self?.notch.showRuleNotice(text) }
        automation.setEnabled(preferences.automationEnabled && preferences.notchEnabled)
        recentFiles.enabled = preferences.recentFilesEnabled
        clipboardShelf.enabled = preferences.clipboardShelfEnabled
        fileActivity.enabled = preferences.fileActivityEnabled
        layoutMenuItem?.isEnabled = preferences.windowManagementEnabled && permissions.accessibility
        // Existing hosting view observes preferences; preserve its sidebar selection.
    }

    @objc private func switcherClosed() { dock.enabled = preferences.dockEnabled && !isSleeping && !isSessionInactive }
    @objc private func displayChanged() { switcher.dismiss(); dock.dismiss() }
    @objc private func openNotch() {
        if !preferences.notchEnabled { preferences.notchEnabled = true }
        notch.start()
        notch.openPanel()
    }
    @objc private func addFiles() { shelf.chooseFiles(); openNotch() }
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

    private func refreshSettingsContent() {
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, permissions: permissions,
            spotify: spotify, appleMusic: appleMusic, browserMedia: browserMedia, camera: camera, shelf: shelf, hotKey: hotKey,
            utilities: utilities, aiActivity: aiActivity, systemMonitor: systemMonitor,
            processes: processes, lid: lid, keyboardCleaning: keyboardCleaning,
            updates: updates, widgets: widgetLayout, background: islandBackground, weather: weather,
            faceUnlock: faceUnlock, launcher: launcher, automation: automation,
            loginItem: loginItem,
            openPanel: { [weak self] in self?.openNotch() }))
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
        switcher.dismiss()
        dock.stop()
        notch.stop()
        media.stop()
        hotKey.unregister()
        windowLayout.stop()
        aiActivity.stop()
        systemMonitor.stop()
        processes.stop()
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
        applyPreferences()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        windowLayout.stop()
        switcher.dismiss()
        dock.stop()
        notch.stop()
        media.stop()
        aiActivity.stop()
        systemMonitor.stop()
        processes.stop()
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
