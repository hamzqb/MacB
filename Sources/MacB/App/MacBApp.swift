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
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
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
    private let keyboardCleaning = KeyboardCleaningService()
    private let utilities = UtilityCoordinator()
    private let updates = UpdateService()
    private lazy var dock = DockController(windowService: windows, previewService: previews, preferences: preferences,
                                           favorites: favorites, recentTargets: recentTargets)
    private lazy var notch = NotchController(media: media, shelf: shelf, preferences: preferences,
                                            recentFiles: recentFiles, clipboard: clipboardShelf,
                                            fileActivity: fileActivity, tasks: tasks, camera: camera,
                                            auth: biometricAuth, recentTargets: recentTargets,
                                            aiActivity: aiActivity, systemMonitor: systemMonitor,
                                            keyboardCleaning: keyboardCleaning,
                                            openSettings: { [weak self] in self?.showSettings() })
    private lazy var switcher = SwitcherController(windowService: windows, previewService: previews,
                                                   preferences: preferences, favorites: favorites)
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
        } else if CommandLine.arguments.contains("--preview-glance") {
            notch.showDevelopmentPreview(phase: .glance)
        } else if CommandLine.arguments.contains("--preview-files") {
            notch.showDevelopmentPreview(phase: .expanded, content: .files)
        } else if CommandLine.arguments.contains("--preview-clipboard") {
            notch.showDevelopmentPreview(phase: .expanded, content: .clipboard)
        } else if CommandLine.arguments.contains("--preview-tools") {
            notch.showDevelopmentPreview(phase: .expanded, content: .tools)
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
            utilities: utilities, aiActivity: aiActivity, systemMonitor: systemMonitor, keyboardCleaning: keyboardCleaning,
            updates: updates,
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
        keyboardCleaning.stop()
        recentFiles.stop()
        clipboardShelf.stop()
        fileActivity.stop()
        camera.stop()
        biometricAuth.reset()
    }

    private func resumeServicesIfActive() {
        guard !isSleeping, !isSessionInactive else { return }
        permissions.refresh()
        shelf.refreshAvailability()
        media.start()
        aiActivity.start()
        systemMonitor.start()
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
        keyboardCleaning.stop()
        recentFiles.stop()
        clipboardShelf.stop()
        fileActivity.stop()
        camera.stop()
        biometricAuth.reset()
        permissions.stopObserving()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        NotificationCenter.default.removeObserver(self)
    }
}
