import AppKit
import Combine
import MacBCore
import SwiftUI

struct NotchLayout: Equatable {
    var phase: NotchPhase = .collapsed
    var content: NotchContent = .default
    var width: CGFloat = 180
    var height: CGFloat = 32
    var radius: CGFloat = 12
}

struct IslandToast: Equatable {
    let symbol: String
    let message: String
}

@MainActor final class NotchPresentation: ObservableObject {
    @Published var layout = NotchLayout()
    @Published var previousLayout = NotchLayout()
    @Published var width: CGFloat = 180
    @Published var height: CGFloat = 32
    @Published var radius: CGFloat = 12
    @Published var transition: Double = 1
    /// Set for a moment before the panel starts shrinking, so the cards have
    /// somewhere to leave from. Nothing is animated after the panel has gone.
    @Published var isLeaving = false
    @Published var cameraHeight: CGFloat = 0
    @Published var cameraWidth: CGFloat = 0
    @Published var isDropTarget = false
    @Published var pendingDropURLs: [URL] = []
    @Published var indicators = true
    @Published var toast: IslandToast?
    @Published var cameraPreviewVisible = false
    /// A system change the island is announcing for a moment.
    @Published var event: IslandEvent?
}

@MainActor final class NotchController: NSObject, NSWindowDelegate {
    private let media: MediaService
    private let shelf: ShelfStore
    private let preferences: Preferences
    private let recentFiles: RecentFileStore
    private let clipboard: ClipboardShelfStore
    private let fileActivity: FileActivityStore
    private let tasks: TaskStore
    private let camera: CameraPreviewService
    private let auth: BiometricAuthService
    private let recentTargets: RecentTargetStore
    private let aiActivity: AIActivityService
    private let systemMonitor: SystemMonitorService
    private let processes: ProcessMonitorService
    private let watchers: WatchTaskStore
    private let lid: LidAngleService
    private let keyboardCleaning: KeyboardCleaningService
    private let timer: TimerService
    private let widgets: IslandLayoutStore
    private let launcher: AppLauncherStore
    private let background: IslandBackgroundStore
    private let weather: WeatherService
    private let note: QuickNoteStore
    private let systemEvents: SystemEventService
    private let faceUnlock: FaceUnlockService
    private let assistant: JarvisSession
    private let briefing: BriefingService
    private var briefingIsVisible = false
    private let jobs: AgentJobStore
    private let approveProposal: (AgentProposal, UUID) -> Void
    private let refuseProposal: (AgentProposal, UUID) -> Void
    private var agentIsVisible = false
    private let openSettings: () -> Void
    /// True while a voice conversation is running. The island stays open and
    /// ignores its own close timers for as long as it is.
    private var assistantIsActive = false
    private let presentation = NotchPresentation()
    private var state = PanelState()
    private var panel: NotchPanel?
    /// The sheet of real glass under the panel. See `updateBackdrop(phase:)`.
    private var islandBackdrop: ShapedVisualEffectView?
    private var islandSaturation: IslandSaturationView?
    /// The fold the island was last drawn at, so repeated identical readings
    /// feed the blur's watchdog without redrawing the panel for nothing.
    private var lastRenderedFold: Double = 0
    private var animationTimer: Timer?
    private var deadlineTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var monitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var pointerInside = false
    private var suppressHoverUntilExit = false
    private var sourceDragActive = false
    private var incomingDragActive = false
    private var dragHandedOff = false
    private var developmentPreviewLocked = false
    private var display: NSScreen?
    private var toastTask: Task<Void, Never>?
    private var cameraWindow: NSWindow?
    private let lidBlur = LidBlurOverlay.shared
    private let glow = IslandGlowOverlay()
    var enabled = true {
        didSet { if enabled { start() } else { stop() } }
    }

    init(media: MediaService, shelf: ShelfStore, preferences: Preferences,
         recentFiles: RecentFileStore, clipboard: ClipboardShelfStore,
         fileActivity: FileActivityStore, tasks: TaskStore,
         camera: CameraPreviewService, auth: BiometricAuthService,
         recentTargets: RecentTargetStore, aiActivity: AIActivityService,
         systemMonitor: SystemMonitorService, processes: ProcessMonitorService,
         watchers: WatchTaskStore,
         lid: LidAngleService, keyboardCleaning: KeyboardCleaningService,
         timer: TimerService, widgets: IslandLayoutStore, launcher: AppLauncherStore,
         background: IslandBackgroundStore, weather: WeatherService, note: QuickNoteStore,
         faceUnlock: FaceUnlockService,
         systemEvents: SystemEventService,
         assistant: JarvisSession,
         briefing: BriefingService,
         jobs: AgentJobStore,
         approveProposal: @escaping (AgentProposal, UUID) -> Void = { _, _ in },
         refuseProposal: @escaping (AgentProposal, UUID) -> Void = { _, _ in },
         openSettings: @escaping () -> Void) {
        self.assistant = assistant
        self.briefing = briefing
        self.jobs = jobs
        self.approveProposal = approveProposal
        self.refuseProposal = refuseProposal
        self.media = media; self.shelf = shelf; self.preferences = preferences
        self.recentFiles = recentFiles; self.clipboard = clipboard
        self.fileActivity = fileActivity
        self.tasks = tasks; self.camera = camera; self.auth = auth
        self.recentTargets = recentTargets; self.openSettings = openSettings
        self.aiActivity = aiActivity; self.systemMonitor = systemMonitor
        self.processes = processes; self.watchers = watchers; self.lid = lid; self.keyboardCleaning = keyboardCleaning
        self.timer = timer; self.widgets = widgets; self.launcher = launcher; self.background = background; self.weather = weather; self.note = note
        self.faceUnlock = faceUnlock
        self.systemEvents = systemEvents
        super.init()
    }

    func start() {
        guard enabled, panel == nil else { return }
        let window = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false; window.isMovable = false; window.acceptsMouseMovedEvents = true; window.delegate = self
        window.onEscape = { [weak self] in self?.closePanel() }
        let view = NotchView(presentation: presentation, media: media, shelf: shelf,
            preferences: preferences, recentFiles: recentFiles, clipboard: clipboard,
            fileActivity: fileActivity, tasks: tasks, camera: camera, auth: auth,
            recentTargets: recentTargets, aiActivity: aiActivity, systemMonitor: systemMonitor,
            processes: processes, watchers: watchers, lid: lid,
            keyboardCleaning: keyboardCleaning, timer: timer, widgets: widgets, launcher: launcher, background: background, weather: weather, note: note,
            faceUnlock: faceUnlock, assistant: assistant, briefing: briefing, jobs: jobs,
            closeAssistant: { [weak self] in self?.stopAssistant() },
            closeBriefing: { [weak self] in self?.dismissBriefing() },
            approveProposal: { [weak self] proposal, job in self?.approveProposal(proposal, job) },
            refuseProposal: { [weak self] proposal, job in self?.refuseProposal(proposal, job) },
            dismissAgent: { [weak self] _ in self?.dismissAgentReport() },
            startAssistant: { [weak self] in self?.startAssistant() },
            open: { [weak self] in self?.openPanel() }, close: { [weak self] in self?.closePanel() },
            select: { [weak self] content in self?.select(content) },
            openSettings: { [weak self] in self?.openSettings() },
            cameraAction: { [weak self] in self?.handleCameraAction() },
            notify: { [weak self] symbol, message in self?.showToast(symbol: symbol, message: message) })
        let host = NotchHostingView(rootView: view)
        host.onPointerChanged = { [weak self] inside in
            self?.pointerBoundaryChanged(inside: inside)
        }
        host.onDragChanged = { [weak self] active in self?.setDrag(active, incoming: true) }
        host.onDragURLsChanged = { [weak self] urls in self?.presentation.pendingDropURLs = urls }
        host.onFilesDropped = { [weak self] urls in
            self?.shelf.add(urls: urls)
            self?.showToast(symbol: "checkmark", message: "\(urls.count) öğe eklendi")
        }
        // The glass lives in the window, under the SwiftUI view, rather than
        // inside it.
        //
        // A `.behindWindow` material is the only thing on macOS that samples the
        // screen behind a window, and it cannot do that from inside a SwiftUI
        // hierarchy: the island clips itself to its own outline and folds with
        // the lid, and a subtree SwiftUI has to rasterise has nothing behind it
        // to sample. Hosted there it drew a flat dark sheet and the "glass" was
        // paint. Here it is a sibling of the hosting view, composited by AppKit,
        // and the desktop genuinely comes through.
        let container = NSView(frame: .zero)
        container.autoresizingMask = [.width, .height]
        let backdrop = ShapedVisualEffectView()
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.appearance = NSAppearance(named: .darkAqua)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.isHidden = true
        host.autoresizingMask = [.width, .height]
        // Above the material, below the content: the material's own blur has
        // already been composited by the time this layer's filter runs, so the
        // saturation lands on the blurred desktop and not on the widgets.
        let saturation = IslandSaturationView(frame: .zero)
        saturation.autoresizingMask = [.width, .height]
        saturation.isHidden = true
        container.addSubview(backdrop)
        container.addSubview(saturation, positioned: .above, relativeTo: backdrop)
        container.addSubview(host, positioned: .above, relativeTo: saturation)
        window.contentView = container
        backdrop.frame = container.bounds
        saturation.frame = container.bounds
        host.frame = container.bounds
        islandBackdrop = backdrop
        islandSaturation = saturation
        panel = window
        updateDisplay(); window.orderFrontRegardless()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.pointerChanged(event) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.pointerChanged(event); return event
        }) { monitors.append(monitor) }
        observe(NSApplication.didChangeScreenParametersNotification) { [weak self] in self?.updateDisplay() }
        observe(Notification.Name("MacBShelfDragBegan")) { [weak self] in self?.setDrag(true, incoming: false) }
        observe(Notification.Name("MacBShelfDragEnded")) { [weak self] in self?.setDrag(false, incoming: false) }
        observe(Notification.Name("MacBDropTargetActivated")) { [weak self] in
            self?.dragHandedOff = true; self?.closePanel(immediate: true)
        }
        preferences.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                // Switching the surface changes nothing about the panel's size,
                // so it would never reach the glass through a re-render alone.
                self.updateBackdrop(phase: self.presentation.layout.phase)
                self.render()
            }
        }.store(in: &subscriptions)
        // The glass cannot fold, so it steps aside for the hinge and comes back
        // when the lid is open again.
        lid.$foldProgress.map { $0 > 0.001 }.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateBackdrop(phase: self.presentation.layout.phase)
            }
        }.store(in: &subscriptions)
        // Opening the library and adding a widget both change how much room home
        // needs, and the panel resizes from here rather than from the view.
        widgets.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        media.$isPlaying.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        shelf.$items.map(\.count).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        recentFiles.$items.map(\.count).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        clipboard.$items.map(\.count).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        fileActivity.$activeCount.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        tasks.$items.map(\.count).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        camera.$isRunning.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        aiActivity.$activities.map(\.count).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        launcher.$items.map(\.count).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        systemEvents.$event.removeDuplicates().sink { [weak self] event in
            DispatchQueue.main.async { self?.systemEventChanged(event) }
        }.store(in: &subscriptions)
        // A new track is worth one short announcement, so the title is what is
        // watched rather than the playing flag, which also flips on pause.
        media.$title.removeDuplicates().sink { [weak self] title in
            DispatchQueue.main.async { self?.trackChanged(to: title) }
        }.store(in: &subscriptions)
        lid.didOpen.sink { [weak self] in
            self?.greetAfterLidOpen()
        }.store(in: &subscriptions)
        lid.willFold.sink { [weak self] in
            self?.showFarewellBeforeLidCloses()
        }.store(in: &subscriptions)
        // The fold is a continuous transform on the island, so the view has to
        // be redrawn as the hinge turns rather than only when a phase changes.
        //
        // Deliberately not deduplicated. The screen blur treats every reading as
        // a sign of life from the hinge, and a lid being held still reports the
        // same angle over and over: with the duplicates dropped here, holding
        // the lid halfway looked exactly like a sensor that had died, and the
        // blur took itself off the screen mid-close. The redraw is still
        // deduplicated, one level down.
        lid.$foldProgress.sink { [weak self] progress in
            self?.foldProgressChanged(progress)
        }.store(in: &subscriptions)
        // Switching either setting off has to clear the screen at once. Waiting
        // for the next hinge reading would leave the desktop blurred behind a
        // settings window that says the blur is off.
        preferences.$lidScreenBlur.removeDuplicates().sink { [weak self] enabled in
            if !enabled { self?.lidBlur.hide() }
        }.store(in: &subscriptions)
        preferences.$lidHingeEnabled.removeDuplicates().sink { [weak self] enabled in
            if !enabled { self?.lidBlur.hide() }
        }.store(in: &subscriptions)
        systemEvents.start()
    }

    /// The hinge moved. Redraw the island and take the screen blur with it.
    ///
    /// The blur is switched off rather than merely faded when the fold is at
    /// zero, so a lid that is simply open never leaves windows lying about.
    private func foldProgressChanged(_ progress: Double) {
        if progress != lastRenderedFold {
            lastRenderedFold = progress
            render()
        }
        guard preferences.lidHingeEnabled, preferences.lidScreenBlur else {
            if lidBlur.isVisible { lidBlur.hide() }
            return
        }
        lidBlur.apply(progress: progress)
    }

    /// Shows a line one of the user's rules asked for.
    ///
    /// Goes through the same queue as every other island line, so a rule cannot
    /// interrupt something the user is reading or shout over an open panel.
    func showRuleNotice(_ text: String) {
        guard state.phase != .expanded, !incomingDragActive, !developmentPreviewLocked else { return }
        systemEvents.present(.notice(text))
    }

    /// The lid has come back up. One line, read in the time it takes to sit down.
    private func greetAfterLidOpen() {
        lidBlur.hide()
        guard preferences.lidHingeEnabled, preferences.islandEventsEnabled else { return }
        guard state.phase != .expanded, !incomingDragActive, !developmentPreviewLocked else { return }
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "HH:mm"
        let battery = systemMonitor.snapshot.batteryPercent.map { Int($0.rounded()) }
        // No line written, no line shown. See `IslandEvent.welcome`.
        guard let event = IslandEvent.welcome(hour: Calendar.current.component(.hour, from: now),
                                              time: formatter.string(from: now),
                                              batteryPercent: battery,
                                              custom: preferences.lidWelcomeText) else { return }
        systemEvents.present(event)
    }

    /// The lid is going down. Put something on screen for the hinge to fold.
    ///
    /// Without this the fold has nothing to work on: the island is collapsed to
    /// nothing whenever it is idle, and rotating an empty rectangle is not an
    /// animation. An open panel is left alone, because the user put it there.
    private func showFarewellBeforeLidCloses() {
        guard preferences.lidHingeEnabled, preferences.islandEventsEnabled else { return }
        guard state.phase != .expanded, !incomingDragActive, !developmentPreviewLocked else { return }
        let battery = systemMonitor.snapshot.batteryPercent.map { Int($0.rounded()) }
        // No line written, no line shown. The blur still runs; there is simply
        // nothing on screen for the hinge to fold.
        guard let event = IslandEvent.farewell(hour: Calendar.current.component(.hour, from: Date()),
                                               batteryPercent: battery,
                                               custom: preferences.lidFarewellText) else { return }
        systemEvents.present(event)
    }

    /// Shows an event, or takes the island back down once it has passed.
    ///
    /// An open panel is never interrupted: the user put it there, and a passing
    /// notice is not a reason to replace what they are reading.
    private func systemEventChanged(_ event: IslandEvent?) {
        guard preferences.islandEventsEnabled else {
            if presentation.event != nil { presentation.event = nil; render() }
            return
        }
        guard state.phase != .expanded, !incomingDragActive, !developmentPreviewLocked else { return }
        presentation.event = event
        if event != nil {
            deadlineTask?.cancel()
            state.peek()
        } else if !pointerInside {
            state.close()
            scheduleDeadline()
        }
        render()
    }

    private func trackChanged(to title: String) {
        guard preferences.islandEventsEnabled, media.isPlaying, !title.isEmpty else { return }
        systemEvents.present(.nowPlaying(title: title, artist: media.artist))
    }

    func stop() {
        animationTimer?.invalidate(); animationTimer = nil
        systemEvents.stop()
        toastTask?.cancel(); toastTask = nil
        deadlineTask?.cancel(); deadlineTask = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll(); subscriptions.removeAll()
        panel?.orderOut(nil); panel?.delegate = nil; panel = nil
        state.close(); sourceDragActive = false; incomingDragActive = false; dragHandedOff = false
        developmentPreviewLocked = false
        pointerInside = false; media.setPanelVisible(false)
        presentation.cameraPreviewVisible = false
        camera.stop()
        cameraWindow?.orderOut(nil); cameraWindow = nil
        lidBlur.hide()
        glow.hide()
    }

    func openPanel() {
        guard enabled else { return }
        if panel == nil { start() }
        developmentPreviewLocked = false
        deadlineTask?.cancel()
        if preferences.smartNotchEnabled && !media.isPlaying && aiActivity.isActive {
            state.select(.home)
        } else if preferences.smartNotchEnabled && (shelf.items.isEmpty == false || fileActivity.activeCount > 0) {
            state.select(.files)
        } else {
            state.open()
        }
        shelf.refreshAvailability(); render(); panel?.makeKey()
    }

    /// Opens the island straight onto one section.
    ///
    /// `openPanel()` decides for itself what is most worth showing, which is
    /// right when the island is opened by hovering the notch and wrong when
    /// somebody has just aimed at "Pano" on the ring and meant it.
    func openPanel(showing content: NotchContent) {
        openPanel()
        select(content)
    }

    /// Uses the real view and services so design states can be checked without moving the pointer.
    func showDevelopmentPreview(phase: NotchPhase, content: NotchContent = .default, dropping: Bool = false) {
        guard enabled else { return }
        if panel == nil { start() }
        developmentPreviewLocked = true
        deadlineTask?.cancel()
        state.close()
        switch phase {
        case .collapsed:
            break
        case .peek:
            state.peek()
        case .expanded:
            state.select(content)
        }
        if content == .files { shelf.refreshAvailability() }
        if dropping {
            incomingDragActive = true
            presentation.isDropTarget = true
            presentation.pendingDropURLs = [URL(fileURLWithPath: NSHomeDirectory())]
        }
        render(immediate: true)
    }
    /// Which private area a section belongs to, if any.
    private func protectedArea(for content: NotchContent) -> ProtectedArea? {
        switch content {
        case .clipboard: return .clipboard
        case .files: return .shelf
        case .assistant, .briefing, .agent: return nil
        case .home, .apps, .timer: return nil
        }
    }

    /// A section is locked when face unlock guards it, or when the older
    /// "protect private tools" preference is on and Touch ID has not run yet.
    func isLocked(_ area: ProtectedArea) -> Bool {
        if faceUnlock.settings.guards(area) { return !faceUnlock.isUnlocked(area) }
        if preferences.protectPrivateTools, area == .clipboard { return !auth.isAuthenticated }
        return false
    }

    /// Face first, then whatever LocalAuthentication offers. MacB itself never
    /// handles the password behind that second prompt.
    private func requestAccess(_ area: ProtectedArea) {
        if faceUnlock.settings.guards(area) {
            Task { [weak self] in
                guard let self else { return }
                let granted = await self.faceUnlock.requestAccess(to: area)
                self.showToast(symbol: granted ? "lock.open.fill" : "lock.fill",
                               message: granted ? "\(area.title) açıldı" : "Kilitli")
                self.render()
            }
        } else {
            auth.authenticate { [weak self] success in
                guard let self else { return }
                self.showToast(symbol: success ? "lock.open.fill" : "lock.fill",
                               message: success ? "\(area.title) açıldı" : "Kilitli")
                self.render()
            }
        }
    }

    private func select(_ content: NotchContent) {
        state.select(content)
        if content == .home { systemMonitor.refresh() }
        if content == .files { shelf.refreshAvailability() }
        if let area = protectedArea(for: content), isLocked(area) { requestAccess(area) }
        render()
    }
    func closePanel() { closePanel(immediate: false) }
    private func closePanel(immediate: Bool) {
        developmentPreviewLocked = false
        deadlineTask?.cancel(); state.close(); presentation.isDropTarget = false
        suppressHoverUntilExit = true; panel?.resignKey(); render(immediate: immediate)
        if cameraWindow == nil { presentation.cameraPreviewVisible = false; camera.stop() }
        auth.reset()
    }
    func windowDidBecomeKey(_ notification: Notification) {
        guard let source = notification.object as? NSWindow, source === panel else { return }
        guard state.isOpen else { return }
        guard !developmentPreviewLocked else { return }
        state.setKeyboardFocus(true); render()
    }
    func windowDidResignKey(_ notification: Notification) {
        guard let source = notification.object as? NSWindow, source === panel else { return }
        state.setKeyboardFocus(false)
        if !pointerInside && !developmentPreviewLocked { state.pointerExited(at: ProcessInfo.processInfo.systemUptime); scheduleDeadline() }
    }
    private func observe(_ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in action() }
        })
    }
    /// Keeps the window's glass in step with the panel it sits under.
    ///
    /// Hidden rather than faded when it is not wanted: an appearance with no
    /// material, Reduce Transparency, a collapsed island with nothing to be
    /// glass, and the fold, where the panel is a rotated picture and a flat
    /// sheet of glass behind it would not rotate with it.
    private func updateBackdrop(phase: NotchPhase) {
        guard let backdrop = islandBackdrop else { return }
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let wanted = preferences.islandAppearance.usesMaterial
            && !reduceTransparency
            && phase != .collapsed
            && lid.foldProgress <= 0.001
        backdrop.isHidden = !wanted
        islandSaturation?.isHidden = !wanted
        guard wanted else { return }
        // `.hudWindow` is the one that carries the most of what is behind it —
        // it is what Spotlight is made of. `.fullScreenUI` was tried first and
        // is nearly opaque: it looked exactly like the flat black panel it was
        // meant to replace, which cost an evening to notice.
        backdrop.material = preferences.islandAppearance == .blackGlass ? .fullScreenUI : .hudWindow
        backdrop.topRadius = presentation.cameraHeight > 0 ? 0 : presentation.radius
        backdrop.bottomRadius = presentation.radius
        // The material has one fixed density, so the only way to go further is
        // to thin the frost itself and let some of the screen past unblurred.
        // Floored well short of nothing: a panel you can read a sentence through
        // is a hole in the screen, not a surface.
        let translucency = min(1, max(0, preferences.islandTranslucency))
        backdrop.alphaValue = 1 - 0.42 * translucency
        // Colour comes back as the frost thins, which is the whole trick: what
        // is behind the sheet has to look more alive through it than beside it,
        // or the panel reads as a grey slab no matter how much of the desktop
        // is technically getting through.
        if let saturation = islandSaturation {
            saturation.topRadius = backdrop.topRadius
            saturation.bottomRadius = backdrop.bottomRadius
            saturation.saturation = 1 + 0.7 * translucency
        }
    }

    private func updateDisplay() {
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let notchedScreen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        display = notchedScreen ?? mouseScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = display else { return }
        presentation.cameraHeight = screen.safeAreaInsets.top
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            presentation.cameraWidth = max(0, right.minX - left.maxX)
        } else { presentation.cameraWidth = 0 }
        render(immediate: true)
    }
    private func setDrag(_ active: Bool, incoming: Bool) {
        if incoming { incomingDragActive = active } else { sourceDragActive = active }
        if dragHandedOff {
            if !sourceDragActive && !incomingDragActive { dragHandedOff = false }
            return
        }
        state.setDragging(sourceDragActive || incomingDragActive)
        if incoming {
            // A tap the moment the island becomes a target, while the eyes are
            // still on the file being dragged rather than on the notch.
            if active, !presentation.isDropTarget { Haptics.targetEntered() }
            presentation.isDropTarget = active
            if !active { presentation.pendingDropURLs = [] }
        }
        if !sourceDragActive && !incomingDragActive {
            pointerInside = panel?.frame.contains(NSEvent.mouseLocation) == true
            if pointerInside { state.pointerEntered(); deadlineTask?.cancel() }
            else { state.pointerExited(at: ProcessInfo.processInfo.systemUptime); scheduleDeadline() }
        }
        render()
    }
    private func pointerChanged(_ event: NSEvent) {
        guard !developmentPreviewLocked else { return }
        guard let panel else { return }
        let inside = panel.frame.contains(NSEvent.mouseLocation)
        updatePointer(inside: inside, event: event)
    }
    private func pointerBoundaryChanged(inside: Bool) {
        guard !developmentPreviewLocked else { return }
        updatePointer(inside: inside, event: nil)
    }
    private func updatePointer(inside: Bool, event: NSEvent?) {
        guard let panel else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if inside {
            // After an explicit close, require one real exit before a new hover can begin.
            // Keeping pointerInside false prevents a suppressed event from swallowing the next entry deadline.
            if suppressHoverUntilExit { pointerInside = false; return }
            if !pointerInside, !suppressHoverUntilExit { state.pointerEntered(at: now); scheduleDeadline() }
            else if pointerInside { state.pointerEntered() }
        } else {
            if pointerInside { state.pointerExited(at: now); scheduleDeadline() }
            suppressHoverUntilExit = false
            if event?.type == .leftMouseDown, state.hasKeyboardFocus { panel.resignKey() }
        }
        pointerInside = inside
    }
    /// Opens the island on the assistant and keeps it there while it talks.
    func startAssistant() {
        assistantIsActive = true
        enabled = true
        start()
        openPanel(showing: .assistant)
        assistant.start()
        render()
    }

    /// Ends the conversation and lets the island go back to normal.
    func stopAssistant() {
        assistant.stop()
        assistantFinished()
    }

    /// Called when the conversation ends, by hand or by itself.
    func assistantFinished() {
        guard assistantIsActive else { return }
        assistantIsActive = false
        if state.content == .assistant { select(.default) }
        closePanel()
    }

    var isAssistantVisible: Bool { assistantIsActive }

    /// Puts the morning briefing in the island. It stays until it is closed or
    /// until something else takes the island over, and never while a
    /// conversation is running — being greeted in the middle of a sentence is
    /// worse than not being greeted.
    func showBriefing() {
        guard !assistantIsActive, briefing.isVisible else { return }
        briefingIsVisible = true
        enabled = true
        start()
        openPanel(showing: .briefing)
        render()
    }

    func dismissBriefing() {
        guard briefingIsVisible else { return }
        briefingIsVisible = false
        briefing.dismiss()
        if state.content == .briefing { select(.default) }
        closePanel()
    }

    var isBriefingVisible: Bool { briefingIsVisible }

    /// Puts what a background job found in the island.
    ///
    /// Never over a conversation or a briefing: somebody who is talking to
    /// MacB, or being greeted by it, is already being spoken to.
    func showAgentReport() {
        guard !assistantIsActive, !briefingIsVisible, !jobs.waiting.isEmpty else { return }
        agentIsVisible = true
        enabled = true
        start()
        openPanel(showing: .agent)
        render()
    }

    func dismissAgentReport() {
        guard agentIsVisible else { return }
        agentIsVisible = false
        for job in jobs.waiting { jobs.markDelivered(job.id) }
        if state.content == .agent { select(.default) }
        closePanel()
    }

    var isAgentVisible: Bool { agentIsVisible }

    private func scheduleDeadline() {
        guard !assistantIsActive, !briefingIsVisible, !agentIsVisible else { deadlineTask?.cancel(); return }
        deadlineTask?.cancel()
        let deadlines = [state.hoverDeadline, state.closeDeadline].compactMap { $0 }
        guard let deadline = deadlines.min() else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.state.tick(at: ProcessInfo.processInfo.systemUptime)
            self.render()
        }
    }
    private func targetLayout() -> NotchLayout {
        let camera = presentation.cameraHeight
        let screenWidth = display?.frame.width ?? 1512
        let maxWidth = screenWidth - IslandGeometry.displayMargin
        switch state.phase {
        case .collapsed:
            let indicators = collapsedIndicatorWidth()
            let width = IslandGeometry.collapsedWidth(notchWidth: hardwareNotchWidth(), indicatorWidth: indicators)
            return NotchLayout(phase: .collapsed, content: state.content,
                width: min(maxWidth, width),
                height: camera > 0 ? camera : (indicators > 0 ? 32 : 10), radius: 0)
        case .peek:
            let width: CGFloat
            if let event = presentation.event {
                width = IslandGeometry.eventWidth(title: event.title, detail: event.detail,
                                                  hasProgress: event.progress != nil)
            } else {
                width = PeekModel.width(for: PeekModel.chips(peekInput()))
            }
            return NotchLayout(phase: .peek, content: .default,
                width: min(width, maxWidth),
                height: camera + IslandGeometry.peekHeight, radius: 20)
        case .expanded:
            let width = incomingDragActive
                ? IslandGeometry.dropWidth(screenWidth: screenWidth)
                : min(maxWidth, expandedContentWidth(screenWidth: screenWidth))
            let body = expandedBodyHeight(width: width)
            let cameraExtra: CGFloat = presentation.cameraPreviewVisible ? 136 : 0
            return NotchLayout(phase: .expanded, content: state.content,
                width: width,
                height: camera + IslandGeometry.expandedHeight(bodyHeight: body) + cameraExtra,
                radius: MacBDesign.Island.cornerRadius)
        }
    }

    /// Every section asks only for the space its current content can use. The
    /// display fraction remains a ceiling instead of becoming permanent empty area.
    private func expandedContentWidth(screenWidth: CGFloat) -> CGFloat {
        if presentation.cameraPreviewVisible {
            return IslandGeometry.sectionWidth(720, screenWidth: screenWidth)
        }
        switch state.content {
        case .home:
            return IslandGeometry.homeWidth(unitCount: widgets.enabledUnitCount,
                                           isEditing: widgets.isEditing, screenWidth: screenWidth)
        case .apps:
            return IslandGeometry.launcherWidth(itemCount: launcher.items.count, screenWidth: screenWidth)
        case .files:
            let count = shelf.items.count + (preferences.recentFilesEnabled ? recentFiles.items.count : 0)
            return IslandGeometry.sectionWidth(count == 0 ? 440 : 600, screenWidth: screenWidth)
        case .clipboard:
            return IslandGeometry.clipboardWidth(itemCount: clipboard.items.count, screenWidth: screenWidth)
        case .timer:
            return IslandGeometry.sectionWidth(620, screenWidth: screenWidth)
        case .assistant:
            return IslandGeometry.sectionWidth(
                IslandGeometry.assistantWidth(hasConfirmation: assistant.confirmation != nil),
                screenWidth: screenWidth)
        case .briefing:
            return IslandGeometry.sectionWidth(IslandGeometry.briefingWidth, screenWidth: screenWidth)
        case .agent:
            return IslandGeometry.sectionWidth(IslandGeometry.agentWidth, screenWidth: screenWidth)
        }
    }

    /// Body height per section. An empty section contributes nothing, so the panel shrinks to its navigation.
    private func expandedBodyHeight(width: CGFloat) -> CGFloat {
        if incomingDragActive { return IslandGeometry.dropTargetHeight }
        if let area = protectedArea(for: state.content), isLocked(area) {
            return IslandGeometry.lockedSectionHeight
        }
        switch state.content {
        case .home:
            let columns = IslandGeometry.columns(forWidth: width)
            return IslandGeometry.homeHeight(rows: widgets.rows(columns: columns),
                                             isEditing: widgets.isEditing)
        case .apps:
            return IslandGeometry.launcherHeight()
        case .files:
            let visible = shelf.items.count + (preferences.recentFilesEnabled ? recentFiles.items.count : 0)
            return IslandGeometry.fileStripHeight(rows: visible)
        case .clipboard:
            return IslandGeometry.clipboardHeight(isEmpty: clipboard.items.isEmpty)
        case .timer:
            return IslandGeometry.timerHeight
        case .assistant:
            return IslandGeometry.assistantHeight(
                showsInput: assistant.showsInput,
                showsCaptions: preferences.assistantCaptions
                    && !(assistant.lines.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                hasConfirmation: assistant.confirmation != nil)
        case .briefing:
            return IslandGeometry.briefingHeight(chipCount: briefing.chips.count)
        case .agent:
            let job = jobs.waiting.first ?? jobs.running.first
            return IslandGeometry.agentHeight(
                reportLines: max(1, (job?.report.count ?? 0) / 58 + 1),
                proposals: job?.proposals.filter(\.isPending).count ?? 0)
        }
    }

    /// Width the collapsed indicators need. Zero means nothing is happening and the island stays inert.
    /// The live values behind the hover strip. Nothing here starts a poll:
    /// every field is already being tracked for another part of the island.
    private func peekInput() -> PeekModel.Input {
        PeekModel.input(media: media, timer: timer, weather: weather, shelf: shelf,
                        aiActivity: aiActivity, systemMonitor: systemMonitor)
    }

    private func collapsedIndicatorWidth() -> CGFloat {
        guard preferences.compactIndicators else { return 0 }
        var slots = 0
        if media.isPlaying { slots += 1 }
        if timer.isActive { slots += 1 }
        if !shelf.items.isEmpty { slots += 1 }
        guard slots > 0 else { return 0 }
        return CGFloat(slots) * 58 + (hardwareNotchWidth() ?? 190)
    }

    private func hardwareNotchWidth() -> CGFloat? {
        guard let display else { return nil }
        let inset = display.safeAreaInsets
        guard inset.top > 0 else { return nil }
        let left = display.auxiliaryTopLeftArea?.width ?? 0
        let right = display.auxiliaryTopRightArea?.width ?? 0
        guard left > 0, right > 0 else { return nil }
        return max(120, display.frame.width - left - right)
    }

    /// A short line inside the open panel, for something that has just happened
    /// to the panel itself.
    func notify(symbol: String, message: String) { showToast(symbol: symbol, message: message) }

    private func showToast(symbol: String, message: String) {
        toastTask?.cancel()
        withAnimation(MacBDesign.Motion.quick) { presentation.toast = IslandToast(symbol: symbol, message: message) }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            withAnimation(MacBDesign.Motion.quick) { self.presentation.toast = nil }
        }
    }

    private func handleCameraAction() {
        if presentation.cameraPreviewVisible && camera.isRunning {
            showLargeCamera()
            return
        }
        let start = { [weak self] in
            guard let self else { return }
            self.presentation.cameraPreviewVisible = true
            self.state.open()
            self.camera.start()
            self.showToast(symbol: "camera.fill", message: "Kamera açılıyor")
            self.render()
        }
        if faceUnlock.settings.guards(.camera) && !faceUnlock.isUnlocked(.camera) {
            Task { [weak self] in
                guard let self, await self.faceUnlock.requestAccess(to: .camera) else { return }
                start()
            }
        } else if preferences.protectPrivateTools && !auth.isAuthenticated {
            auth.authenticate { success in if success { start() } }
        } else { start() }
    }

    private func showLargeCamera() {
        if let cameraWindow { cameraWindow.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MacB Kamera"
        window.minSize = NSSize(width: 420, height: 280)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: CameraPreviewView(service: camera)
            .background(.black).clipShape(RoundedRectangle(cornerRadius: 14)).padding(MacBDesign.Space.comfortable).background(.black))
        window.center()
        cameraWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        showToast(symbol: "arrow.up.left.and.arrow.down.right", message: "Büyük önizleme açıldı")
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === cameraWindow else { return }
        cameraWindow = nil
        if !state.isOpen {
            presentation.cameraPreviewVisible = false
            camera.stop()
            render()
        }
    }
    /// Puts a shadow under the island, and optionally some of its own light.
    ///
    /// A collapsed island casts nothing: it is flush against the bezel, there is
    /// no object standing off the screen to throw a shadow, and a permanent
    /// smudge under the notch would be a defect rather than a flourish. The
    /// shadow is not optional where the island is open; the light is.
    private func updateGlow(frame: NSRect, on screen: NSScreen, phase: NotchPhase) {
        guard phase != .collapsed else { return glow.hide() }
        let tint = (media.isPlaying ? media.tint : nil) ?? MacBDesign.IslandToken.accent
        glow.update(frame: frame, on: screen, radius: presentation.radius, tint: tint,
                    shadow: 1,
                    glow: preferences.islandGlow ? (phase == .expanded ? 1 : 0.55) : 0)
    }

    private func render(immediate: Bool = false) {
        guard let panel, let screen = display else { return }
        presentation.indicators = preferences.compactIndicators
        let target = targetLayout()
        // A collapsed island with nothing to report must not sit over the desktop as a hit target.
        panel.ignoresMouseEvents = target.phase == .collapsed && collapsedIndicatorWidth() == 0
            && presentation.cameraHeight == 0
        media.setPanelVisible(state.isOpen && (state.content == .home || state.phase == .peek))
        let homePanelVisible = state.isOpen && state.content == .home
        systemMonitor.setFastSampling(homePanelVisible)
        processes.setFastSampling(homePanelVisible && widgets.isActive(.topProcesses))
        weather.setPanelVisible(homePanelVisible && widgets.isActive(.weather))
        guard target != presentation.layout || immediate else { return }
        let reducedMotion = !preferences.animationsEnabled
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Let the cards leave before the panel does. Closing used to take the
        // whole strip away in one frame while opening dealt the cards out one
        // by one, so the island arrived like an object and left like a bug.
        // The wait is short enough that closing still feels immediate.
        if !immediate, !reducedMotion, !presentation.isLeaving,
           target.phase == .collapsed, presentation.layout.phase == .expanded {
            presentation.isLeaving = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 130_000_000)
                self?.render()
            }
            return
        }
        presentation.isLeaving = false
        animationTimer?.invalidate(); animationTimer = nil
        let previousLayout = presentation.layout
        let crossfadesContent = previousLayout.phase != target.phase || previousLayout.content != target.content
        presentation.previousLayout = previousLayout
        presentation.layout = target
        let startWidth = presentation.width, startHeight = presentation.height, startRadius = presentation.radius
        let reduced = reducedMotion
        func apply(_ amount: Double, fade: Double) {
            let t = CGFloat(amount)
            presentation.width = startWidth + (target.width - startWidth) * t
            presentation.height = startHeight + (target.height - startHeight) * t
            presentation.radius = startRadius + (target.radius - startRadius) * t
            presentation.transition = crossfadesContent ? fade : 1
            let box = NSRect(x: screen.frame.midX - presentation.width / 2,
                             y: screen.frame.maxY - presentation.height,
                             width: presentation.width, height: presentation.height)
            panel.setFrame(box, display: true)
            updateBackdrop(phase: target.phase)
            updateGlow(frame: box, on: screen, phase: target.phase)
        }
        if immediate { apply(1, fade: 1); return }
        let duration = reduced ? 0.10 : (target.phase == .collapsed ? MacBDesign.closeDuration : MacBDesign.openDuration)
        let startTime = ProcessInfo.processInfo.systemUptime
        apply(reduced ? 1 : 0, fade: crossfadesContent ? 0 : 1)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let fraction = min(1, (ProcessInfo.processInfo.systemUptime - startTime) / duration)
                let shaped = reduced ? 1 : MorphTiming.progress(fraction)
                let fade = crossfadesContent ? max(0, min(1, (fraction - 0.18) / 0.62)) : 1
                apply(shaped, fade: MorphTiming.progress(fade))
                if fraction >= 1 { timer.invalidate(); self.animationTimer = nil }
            }
        }
        animationTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
}

final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onDragChanged: ((Bool) -> Void)?
    var onDragURLsChanged: (([URL]) -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
    var onPointerChanged: ((Bool) -> Void)?
    private var pointerTrackingArea: NSTrackingArea?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let tracking = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(tracking)
        pointerTrackingArea = tracking
    }

    override func mouseEntered(with event: NSEvent) { onPointerChanged?(true) }
    override func mouseExited(with event: NSEvent) { onPointerChanged?(false) }
    override func mouseMoved(with event: NSEvent) { onPointerChanged?(true) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        onDragURLsChanged?(urls)
        onDragChanged?(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragChanged?(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { onDragChanged?(false); return false }
        onFilesDropped?(urls)
        onDragChanged?(false)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { onDragChanged?(false) }
}
