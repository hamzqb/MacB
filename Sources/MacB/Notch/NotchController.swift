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
    /// The conversation's own layout: no navigation row, the orb and status
    /// beside the camera, the text field only when it is wanted.
    var isAssistantCompact = false
    var showsAssistantInput = false
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
    /// The fold the island was last drawn at, so repeated identical readings
    /// feed the blur's watchdog without redrawing the panel for nothing.
    private var lastRenderedFold: Double = 0
    /// Bumped by every render, so a delayed step from an older one (the
    /// leave, the window shrinking after a close) can tell it is stale.
    private var renderGeneration = 0
    /// The island's target rectangle on screen: what hover and clicks are
    /// measured against. Not the window, which is larger (see
    /// `IslandEnvelope`), and not the shape mid-animation, which would let a
    /// resize under a still pointer look like the pointer leaving.
    private var islandRect: NSRect = .zero
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
        host.onPointerChanged = { [weak self] _ in
            self?.pointerBoundaryChanged()
        }
        host.onDragChanged = { [weak self] active in self?.setDrag(active, incoming: true) }
        host.onDragURLsChanged = { [weak self] urls in self?.presentation.pendingDropURLs = urls }
        host.onFilesDropped = { [weak self] urls in
            self?.shelf.add(urls: urls)
            self?.showToast(symbol: "checkmark", message: "\(urls.count) öğe eklendi")
        }
        // The glass is drawn by SwiftUI inside the island's own outline (see
        // `NotchView.islandSurface`), so the window holds nothing but the
        // hosting view. The window is transparent around the island, and
        // passes clicks through there: see `updateHitTesting()`.
        host.autoresizingMask = [.width, .height]
        window.contentView = host
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
                self.render()
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
        // The assistant's body appears for a subtitle, a fault or a question,
        // and the panel has to follow at once, not on the next pointer move.
        // Only the few things that change its size: the levels publish thirty
        // times a second and must not drive a layout pass.
        Publishers.CombineLatest3(
            assistant.$confirmation.map { $0?.id },
            assistant.$state,
            assistant.$lines.map { $0.last?.text.isEmpty ?? true }
        )
        .map { _ in () }
        .merge(with: assistant.$showsInput.removeDuplicates().map { _ in () },
               preferences.$assistantCaptions.removeDuplicates().map { _ in () })
        .sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.state.content == .assistant else { return }
                self.render()
            }
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

    /// Something worth knowing before being asked. Never over an open panel:
    /// if the user is working in the island, it waits for the next one.
    func showHeadsUp(_ event: IslandEvent) {
        guard preferences.islandEventsEnabled else { return }
        guard state.phase != .expanded, !incomingDragActive, !developmentPreviewLocked else { return }
        systemEvents.present(event)
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
        renderGeneration += 1
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
            pointerInside = islandRect.contains(NSEvent.mouseLocation)
            if pointerInside { state.pointerEntered(); deadlineTask?.cancel() }
            else { state.pointerExited(at: ProcessInfo.processInfo.systemUptime); scheduleDeadline() }
        }
        render()
    }
    private func pointerChanged(_ event: NSEvent) {
        guard !developmentPreviewLocked else { return }
        guard panel != nil else { return }
        let inside = islandRect.contains(NSEvent.mouseLocation)
        updateHitTesting()
        updatePointer(inside: inside, event: event)
    }
    private func pointerBoundaryChanged() {
        guard !developmentPreviewLocked else { return }
        updateHitTesting()
        updatePointer(inside: islandRect.contains(NSEvent.mouseLocation), event: nil)
    }

    /// The window takes the mouse only over the island. Everywhere else in it
    /// is transparent, and a click there belongs to whatever is underneath.
    /// A drag keeps it, so a file can be dropped as soon as it arrives.
    private func updateHitTesting() {
        guard let panel else { return }
        let collapsedAndEmpty = presentation.layout.phase == .collapsed
            && collapsedIndicatorWidth() == 0 && presentation.cameraHeight == 0
        let over = islandRect.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        let takes = !collapsedAndEmpty && (over || sourceDragActive || incomingDragActive)
        if panel.ignoresMouseEvents == takes { panel.ignoresMouseEvents = !takes }
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
        let changed = pointerInside != inside
        pointerInside = inside
        // The conversation shows its text field under the pointer only.
        if changed, state.content == .assistant, state.isOpen { render() }
    }
    /// Opens the island on the assistant and keeps it there while it talks.
    func startAssistant() {
        assistantIsActive = true
        enabled = true
        start()
        openPanel(showing: .assistant)
        // Mail, calendar, memory and the screen are the owner's. When the
        // user has put the assistant behind their face, a conversation starts
        // only after a look — or Touch ID — and someone else gets a guest.
        guard faceUnlock.settings.guards(.assistant), !faceUnlock.isUnlocked(.assistant) else {
            assistant.isGuest = false
            assistant.start()
            render()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let recognised = await self.faceUnlock.requestAccess(to: .assistant)
            guard self.assistantIsActive else { return }
            self.assistant.isGuest = !recognised
            self.assistant.start()
            self.render()
        }
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
        case .expanded where state.content == .assistant && !incomingDragActive
                && !presentation.cameraPreviewVisible:
            let showsInput = pointerInside || assistant.showsInput
            let showsDetail = assistant.islandDetail(captions: preferences.assistantCaptions) != nil
            let hasConfirmation = assistant.confirmation != nil
            let width = min(maxWidth, IslandGeometry.assistantWidth(hasConfirmation: hasConfirmation,
                                                                    notchWidth: assistantNotchWidth))
            var layout = NotchLayout(phase: .expanded, content: .assistant, width: width,
                height: IslandGeometry.assistantPanelHeight(cameraHeight: assistantNotchWidth > 0 ? camera : 0,
                                                            showsInput: showsInput, showsDetail: showsDetail,
                                                            hasConfirmation: hasConfirmation),
                radius: IslandGeometry.assistantPanelRadius(hasBody: showsInput || showsDetail || hasConfirmation))
            layout.isAssistantCompact = true
            layout.showsAssistantInput = showsInput
            return layout
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
            return IslandGeometry.sectionWidth(IslandGeometry.assistantWidth, screenWidth: screenWidth)
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
            // Only while a drop or the camera preview takes the panel over;
            // otherwise the conversation has its own layout above.
            return 0
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

    /// The camera housing the assistant's orb and status sit either side of;
    /// zero on a display without one, where they take a slim row instead.
    private var assistantNotchWidth: CGFloat {
        presentation.cameraHeight > 0 ? presentation.cameraWidth : 0
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
    private func render(immediate: Bool = false) {
        guard panel != nil, let screen = display else { return }
        presentation.indicators = preferences.compactIndicators
        let target = targetLayout()
        media.setPanelVisible(state.isOpen && (state.content == .home || state.phase == .peek))
        let homePanelVisible = state.isOpen && state.content == .home
        systemMonitor.setFastSampling(homePanelVisible)
        processes.setFastSampling(homePanelVisible && widgets.isActive(.topProcesses))
        weather.setPanelVisible(homePanelVisible && widgets.isActive(.weather))
        placeIsland(target, on: screen)
        guard target != presentation.layout || immediate else { return updateHitTesting() }
        let reducedMotion = !preferences.animationsEnabled
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        renderGeneration += 1
        let generation = renderGeneration
        // On the way out the content leaves first — a short fade and blur —
        // and then the shape closes behind it.
        if !immediate, !reducedMotion, !presentation.isLeaving,
           target.phase == .collapsed, presentation.layout.phase != .collapsed {
            withAnimation(.easeIn(duration: IslandMotion.leaveDuration)) { presentation.isLeaving = true }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(IslandMotion.leaveDuration * 1_000_000_000))
                guard let self, self.renderGeneration == generation else { return }
                self.render()
            }
            return
        }
        let previousLayout = presentation.layout
        let crossfadesContent = previousLayout.phase != target.phase || previousLayout.content != target.content
        let opening = target.width * target.height >= previousLayout.width * previousLayout.height
        // The window grows before the island does, all at once and unseen,
        // so nothing about the window moves while the island animates.
        growEnvelope(toHold: target, on: screen)
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            presentation.isLeaving = false
            presentation.previousLayout = previousLayout
            presentation.layout = target
            if crossfadesContent && !immediate && !reducedMotion { presentation.transition = 0 }
        }
        updateHitTesting()
        if immediate || reducedMotion {
            withTransaction(instant) {
                presentation.width = target.width
                presentation.height = target.height
                presentation.radius = target.radius
                presentation.transition = 1
            }
            fitEnvelope(to: target, on: screen)
            return
        }
        let response = IslandMotion.response(opening: opening)
        withAnimation(.spring(response: response, dampingFraction: IslandMotion.damping)) {
            presentation.width = target.width
            presentation.height = target.height
            presentation.radius = target.radius
        }
        if crossfadesContent {
            // The new content waits for the shape to be most of the way there.
            let delay = opening ? response * IslandMotion.revealDelayFraction : 0
            withAnimation(.easeOut(duration: IslandMotion.revealDuration).delay(delay)) {
                presentation.transition = 1
            }
        }
        // After it settles, the window shrinks back to what the island needs.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(IslandMotion.settleTime(opening: opening) * 1_000_000_000))
            guard let self, self.renderGeneration == generation, let screen = self.display else { return }
            self.fitEnvelope(to: target, on: screen)
        }
    }

    /// Where the island is on `screen` for `layout`: hover and clicks are
    /// measured against this.
    private func placeIsland(_ layout: NotchLayout, on screen: NSScreen) {
        islandRect = NSRect(x: screen.frame.midX - layout.width / 2, y: screen.frame.maxY - layout.height,
                            width: layout.width, height: layout.height)
    }

    /// The window size for an island of `layout`, shoulders included.
    private func envelopeSize(for layout: NotchLayout, on screen: NSScreen) -> CGSize {
        let silhouette = IslandSilhouette.forBody(height: layout.height + IslandEnvelope.topBleed,
                                                  radius: layout.radius, underNotch: presentation.cameraHeight > 0)
        return IslandEnvelope.size(holding: CGSize(width: layout.width + 2 * silhouette.shoulder, height: layout.height),
                                   screenWidth: screen.frame.width)
    }

    private func setEnvelope(_ size: CGSize, on screen: NSScreen) {
        guard let panel else { return }
        let frame = NSRect(x: (screen.frame.midX - size.width / 2).rounded(),
                           y: screen.frame.maxY + IslandEnvelope.topBleed - size.height,
                           width: size.width, height: size.height)
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
    }

    /// Makes the window big enough for both where the island is and where it
    /// is going. Never smaller: shrinking waits for the island to settle.
    private func growEnvelope(toHold target: NotchLayout, on screen: NSScreen) {
        guard let panel else { return }
        let needed = envelopeSize(for: target, on: screen)
        let current = panel.frame.size
        let size = CGSize(width: max(needed.width, current.width), height: max(needed.height, current.height))
        if size != current { setEnvelope(size, on: screen) }
    }

    private func fitEnvelope(to layout: NotchLayout, on screen: NSScreen) {
        setEnvelope(envelopeSize(for: layout, on: screen), on: screen)
    }
}

final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?
    /// The island's window reaches a few points above the top of the screen
    /// (`IslandEnvelope.topBleed`); AppKit would otherwise push it back down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
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
