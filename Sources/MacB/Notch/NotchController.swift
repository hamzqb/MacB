import AppKit
import Combine
import MacBCore
import SwiftUI

struct NotchLayout: Equatable {
    var phase: NotchPhase = .collapsed
    var content: NotchContent = .music
    var width: CGFloat = 180
    var height: CGFloat = 32
    var radius: CGFloat = 12
}

@MainActor final class NotchPresentation: ObservableObject {
    @Published var layout = NotchLayout()
    @Published var previousLayout = NotchLayout()
    @Published var width: CGFloat = 180
    @Published var height: CGFloat = 32
    @Published var radius: CGFloat = 12
    @Published var transition: Double = 1
    @Published var cameraHeight: CGFloat = 0
    @Published var cameraWidth: CGFloat = 0
    @Published var isDropTarget = false
    @Published var indicators = true
}

@MainActor final class NotchController: NSObject, NSWindowDelegate {
    private let spotify: SpotifyService
    private let shelf: ShelfStore
    private let preferences: Preferences
    private let recentFiles: RecentFileStore
    private let clipboard: ClipboardShelfStore
    private let fileActivity: FileActivityStore
    private let quickCommands: QuickCommandService
    private let presentation = NotchPresentation()
    private var state = PanelState()
    private var panel: NotchPanel?
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
    var enabled = true {
        didSet { if enabled { start() } else { stop() } }
    }

    init(spotify: SpotifyService, shelf: ShelfStore, preferences: Preferences,
         recentFiles: RecentFileStore, clipboard: ClipboardShelfStore,
         fileActivity: FileActivityStore, quickCommands: QuickCommandService) {
        self.spotify = spotify; self.shelf = shelf; self.preferences = preferences
        self.recentFiles = recentFiles; self.clipboard = clipboard
        self.fileActivity = fileActivity; self.quickCommands = quickCommands
        super.init()
    }

    func start() {
        guard enabled, panel == nil else { return }
        let window = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false; window.isMovable = false; window.delegate = self
        window.onEscape = { [weak self] in self?.closePanel() }
        let view = NotchView(presentation: presentation, spotify: spotify, shelf: shelf,
            preferences: preferences, recentFiles: recentFiles, clipboard: clipboard,
            fileActivity: fileActivity, quickCommands: quickCommands,
            open: { [weak self] in self?.openPanel() }, close: { [weak self] in self?.closePanel() },
            select: { [weak self] content in self?.select(content) })
        let host = NotchHostingView(rootView: view)
        host.onDragChanged = { [weak self] active in self?.setDrag(active, incoming: true) }
        host.onFilesDropped = { [weak self] urls in self?.shelf.add(urls: urls) }
        window.contentView = host; panel = window
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
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        spotify.$isPlaying.removeDuplicates().sink { [weak self] _ in
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
    }

    func stop() {
        animationTimer?.invalidate(); animationTimer = nil
        deadlineTask?.cancel(); deadlineTask = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll(); subscriptions.removeAll()
        panel?.orderOut(nil); panel?.delegate = nil; panel = nil
        state.close(); sourceDragActive = false; incomingDragActive = false; dragHandedOff = false
        developmentPreviewLocked = false
        pointerInside = false; spotify.setPanelVisible(false)
    }

    func openPanel() {
        guard enabled else { return }
        if panel == nil { start() }
        developmentPreviewLocked = false
        deadlineTask?.cancel()
        if preferences.smartNotchEnabled && (shelf.items.isEmpty == false || fileActivity.activeCount > 0) {
            state.select(.files)
        } else {
            state.open()
        }
        shelf.refreshAvailability(); render(); panel?.makeKey()
    }

    /// Uses the real view and services so design states can be checked without moving the pointer.
    func showDevelopmentPreview(phase: NotchPhase, content: NotchContent = .music) {
        guard enabled else { return }
        if panel == nil { start() }
        developmentPreviewLocked = true
        deadlineTask?.cancel()
        state.close()
        switch phase {
        case .collapsed:
            break
        case .glance:
            state.glance()
        case .expanded:
            state.select(content)
        }
        if content == .files { shelf.refreshAvailability() }
        render(immediate: true)
    }
    private func select(_ content: NotchContent) {
        state.select(content); if content == .files { shelf.refreshAvailability() }; render()
    }
    func closePanel() { closePanel(immediate: false) }
    private func closePanel(immediate: Bool) {
        developmentPreviewLocked = false
        deadlineTask?.cancel(); state.close(); presentation.isDropTarget = false
        suppressHoverUntilExit = true; panel?.resignKey(); render(immediate: immediate)
    }
    func windowDidBecomeKey(_ notification: Notification) {
        guard !developmentPreviewLocked else { return }
        state.setKeyboardFocus(true); render()
    }
    func windowDidResignKey(_ notification: Notification) {
        state.setKeyboardFocus(false)
        if !pointerInside && !developmentPreviewLocked { state.pointerExited(at: ProcessInfo.processInfo.systemUptime); scheduleDeadline() }
    }
    private func observe(_ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in action() }
        })
    }
    private func updateDisplay() {
        display = NSScreen.screens.first ?? NSScreen.main
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
        if incoming { presentation.isDropTarget = active }
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
        let now = ProcessInfo.processInfo.systemUptime
        if inside {
            if !pointerInside, !suppressHoverUntilExit { state.pointerEntered(at: now); scheduleDeadline() }
            else if pointerInside { state.pointerEntered() }
        } else {
            if pointerInside { state.pointerExited(at: now); scheduleDeadline() }
            suppressHoverUntilExit = false
            if event.type == .leftMouseDown, state.hasKeyboardFocus { panel.resignKey() }
        }
        pointerInside = inside
    }
    private func scheduleDeadline() {
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
        let maxWidth = (display?.frame.width ?? 480) - 24
        switch state.phase {
        case .collapsed:
            let showMusic = preferences.compactIndicators && spotify.isPlaying
            let showFiles = preferences.compactIndicators && !shelf.items.isEmpty
            let showActivity = preferences.compactIndicators && preferences.fileActivityEnabled && fileActivity.activeCount > 0
            let extra: CGFloat = (showMusic || showFiles || showActivity) ? 92 : 0
            return NotchLayout(phase: .collapsed, content: state.content,
                width: min(maxWidth, presentation.cameraWidth > 0 ? presentation.cameraWidth + extra + 12 : max(84, extra + 28)),
                height: max(28, camera), radius: camera > 0 ? 11 : 14)
        case .glance:
            return NotchLayout(phase: .glance, content: .music, width: min(360, maxWidth), height: camera + 90, radius: 23)
        case .expanded:
            let hasFileContent = !shelf.items.isEmpty || !recentFiles.items.isEmpty || !clipboard.items.isEmpty
            let bodyHeight: CGFloat
            switch state.content {
            case .music:
                bodyHeight = spotify.errorMessage == nil ? 274 : 306
            case .files:
                bodyHeight = hasFileContent ? min(390, 138 + CGFloat(shelf.items.count + recentFiles.items.count + clipboard.items.count) * 38) : 216
            case .commands:
                bodyHeight = 230
            }
            return NotchLayout(phase: .expanded, content: state.content, width: min(440, maxWidth), height: camera + bodyHeight, radius: 25)
        }
    }
    private func render(immediate: Bool = false) {
        guard let panel, let screen = display else { return }
        presentation.indicators = preferences.compactIndicators
        let target = targetLayout()
        spotify.setPanelVisible(state.isOpen)
        guard target != presentation.layout || immediate else { return }
        animationTimer?.invalidate(); animationTimer = nil
        presentation.previousLayout = presentation.layout
        presentation.layout = target
        let startWidth = presentation.width, startHeight = presentation.height, startRadius = presentation.radius
        let reduced = !preferences.animationsEnabled || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        func apply(_ amount: Double, fade: Double) {
            let t = CGFloat(amount)
            presentation.width = startWidth + (target.width - startWidth) * t
            presentation.height = startHeight + (target.height - startHeight) * t
            presentation.radius = startRadius + (target.radius - startRadius) * t
            presentation.transition = fade
            panel.setFrame(NSRect(x: screen.frame.midX - presentation.width / 2,
                y: screen.frame.maxY - presentation.height, width: presentation.width, height: presentation.height), display: true)
        }
        if immediate { apply(1, fade: 1); return }
        let duration = reduced ? 0.10 : (target.phase == .collapsed ? MacBDesign.closeDuration : MacBDesign.openDuration)
        let startTime = ProcessInfo.processInfo.systemUptime
        apply(reduced ? 1 : 0, fade: 0)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let fraction = min(1, (ProcessInfo.processInfo.systemUptime - startTime) / duration)
                apply(reduced ? 1 : MorphTiming.progress(fraction), fade: fraction)
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
    var onFilesDropped: (([URL]) -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return [] }
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
