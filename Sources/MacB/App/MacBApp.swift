import AppKit
import SwiftUI
import Combine
import ApplicationServices

@main enum MacBMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnostics") {
            print("MacB 0.1.0")
            print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            print("Accessibility: \(AXIsProcessTrusted())")
            print("Screen capture: \(CGPreflightScreenCaptureAccess())")
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
    private lazy var media = MediaService(spotify: spotify, appleMusic: appleMusic)
    private let shelf = ShelfStore()
    private let favorites = FavoriteWindowStore()
    private let recentFiles = RecentFileStore()
    private let clipboardShelf = ClipboardShelfStore()
    private let fileActivity = FileActivityStore()
    private let quickCommands = QuickCommandService()
    private let hotKey = HotKeyController()
    private lazy var dock = DockController(windowService: windows, previewService: previews, preferences: preferences, favorites: favorites)
    private lazy var notch = NotchController(media: media, shelf: shelf, preferences: preferences,
                                            recentFiles: recentFiles, clipboard: clipboardShelf,
                                            fileActivity: fileActivity, quickCommands: quickCommands)
    private lazy var switcher = SwitcherController(windowService: windows, previewService: previews,
                                                   preferences: preferences, favorites: favorites)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isSleeping = false

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
            self.switcher.begin(backwards: backwards, shortcut: self.preferences.shortcut)
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
        }.store(in: &subscriptions)
        setupWorkspaceObservers()
        media.start()
        applyPreferences()
        if CommandLine.arguments.contains("--smoke-test") {
            NSLog("MacB smoke: application launched; menu and services initialized")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) }
        } else if CommandLine.arguments.contains("--show-panel") {
            notch.openPanel()
        } else if CommandLine.arguments.contains("--preview-glance") {
            notch.showDevelopmentPreview(phase: .glance)
        } else if CommandLine.arguments.contains("--preview-files") {
            notch.showDevelopmentPreview(phase: .expanded, content: .files)
        } else if CommandLine.arguments.contains("--show-settings") || !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
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
        let settings = menu.addItem(withTitle: "Ayarlar ve izinler…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "MacB’den çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func applyPreferences() {
        guard !isSleeping else { return }
        dock.enabled = preferences.dockEnabled && !switcher.isVisible
        if preferences.dockEnabled { dock.start() } else { dock.stop() }
        notch.enabled = preferences.notchEnabled
        if preferences.notchEnabled { notch.start() } else { notch.stop() }
        if preferences.switcherEnabled { hotKey.register(preferences.shortcut) }
        else { hotKey.unregister(); switcher.dismiss() }
        recentFiles.enabled = preferences.recentFilesEnabled
        clipboardShelf.enabled = preferences.clipboardShelfEnabled
        fileActivity.enabled = preferences.fileActivityEnabled
        // Existing hosting view observes preferences; preserve its sidebar selection.
    }

    @objc private func switcherClosed() { dock.enabled = preferences.dockEnabled && !isSleeping }
    @objc private func displayChanged() { switcher.dismiss(); dock.dismiss() }
    @objc private func openNotch() {
        if !preferences.notchEnabled { preferences.notchEnabled = true }
        notch.start()
        notch.openPanel()
    }
    @objc private func addFiles() { shelf.chooseFiles(); openNotch() }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "MacB"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 600, height: 560)
            window.setFrameAutosaveName("MacBSettings")
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        refreshSettingsContent()
        permissions.startObserving()
        shelf.refreshAvailability()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func refreshSettingsContent() {
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, permissions: permissions,
            spotify: spotify, appleMusic: appleMusic, shelf: shelf, shortcutError: hotKey.registrationError,
            openPanel: { [weak self] in self?.openNotch() }))
    }

    func windowWillClose(_ notification: Notification) { permissions.stopObserving() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self as AppDelegate? else { return }
                self.isSleeping = true
                self.switcher.dismiss()
                self.dock.stop()
                self.notch.stop()
                self.media.stop()
                self.hotKey.unregister()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self as AppDelegate? else { return }
                self.isSleeping = false
                self.permissions.refresh()
                self.shelf.refreshAvailability()
                self.media.start()
                self.applyPreferences()
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

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        switcher.dismiss()
        dock.stop()
        notch.stop()
        media.stop()
        recentFiles.stop()
        clipboardShelf.stop()
        fileActivity.stop()
        permissions.stopObserving()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        NotificationCenter.default.removeObserver(self)
    }
}
