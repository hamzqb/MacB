import AppKit
import SwiftUI
import ApplicationServices
import Combine

private struct DockHit {
    let url: URL
    let frame: CGRect
}

@MainActor final class DockController {
    var enabled = true { didSet { if !enabled { dismiss() } } }
    private let windowService: WindowService
    private let previewService: PreviewService
    private let preferences: Preferences
    private let favorites: FavoriteWindowStore
    private var panel: NSPanel?
    private var peekPanel: NSPanel?
    private var isPresented = false
    private var horizontal = false
    private var localCardFrames: [String: CGRect] = [:]
    private var shouldAnimate: Bool { (UserDefaults.standard.object(forKey: "animationsEnabled") as? Bool ?? true) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private let hitQueue = DispatchQueue(label: "com.macb.dock-hit", qos: .utility)
    private var hitInFlight = false
    private var lastHitTime: TimeInterval = 0
    private var hoverTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var dragTask: Task<Void, Never>?
    private var hoverPID: pid_t?
    private var activePID: pid_t?
    private var anchor = CGRect.zero
    private var dragging = false
    private var activatedDuringDrag = false
    private var dragWindowID: String?
    private var peekTask: Task<Void, Never>?
    private var cardFrames: [String: CGRect] = [:]
    private var visibleRecords: [WindowRecord] = []
    private var session = 0
    private var windowSubscription: AnyCancellable?

    init(windowService: WindowService, previewService: PreviewService, preferences: Preferences, favorites: FavoriteWindowStore) {
        self.windowService = windowService; self.previewService = previewService
        self.preferences = preferences; self.favorites = favorites
        windowSubscription = windowService.$windows.dropFirst().sink { [weak self] _ in
            Task { @MainActor in
                guard let self, let pid = self.activePID, self.isPresented else { return }
                if self.windowService.windows.allSatisfy({ $0.pid != pid }) { self.dismiss() }
                else { self.refreshVisiblePreviews() }
            }
        }
    }
    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.handle(event) }; return event
        }) { monitors.append(monitor) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        })
        observers.append(center.addObserver(forName: .init("MacBShelfDragBegan"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dragging = true; self?.activatedDuringDrag = false }
        })
        observers.append(center.addObserver(forName: .init("MacBShelfDragEnded"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dragging = false; self?.activatedDuringDrag = false; self?.dismiss() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        })
    }
    func stop() {
        monitors.forEach(NSEvent.removeMonitor); monitors = []
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []; dismiss()
    }
    func dismiss() {
        session += 1
        hoverTask?.cancel(); closeTask?.cancel(); dragTask?.cancel()
        peekTask?.cancel()
        hoverTask = nil; closeTask = nil; dragTask = nil; peekTask = nil
        hoverPID = nil; activePID = nil; dragWindowID = nil
        isPresented = false
        let token = session
        if let panel {
            panel.ignoresMouseEvents = true
            if shouldAnimate && !dragging {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = MacBDesign.closeDuration
                    panel.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.session == token, !self.isPresented else { return }
                        panel.orderOut(nil); panel.contentView = nil
                    }
                }
            } else { panel.orderOut(nil); panel.contentView = nil }
        }
        cardFrames = [:]; localCardFrames = [:]; visibleRecords = []
        hidePeek()
        previewService.stop()
    }

    private func handle(_ event: NSEvent) {
        guard enabled, AXIsProcessTrusted() else { if isPresented { dismiss() }; return }
        if event.type == .leftMouseUp {
            dragging = false; activatedDuringDrag = false; dragTask?.cancel(); dragWindowID = nil
        }
        if event.type == .leftMouseDragged { dragging = true }
        guard !activatedDuringDrag else { return }
        let point = NSEvent.mouseLocation
        if let panel, isPresented, panel.frame.contains(point) {
            closeTask?.cancel(); closeTask = nil
            if dragging { updateDrag(at: point) }
            return
        }
        dragTask?.cancel(); dragTask = nil; dragWindowID = nil
        if event.type == .leftMouseDown, isPresented, !anchor.contains(point) { dismiss() }
        if isPresented, anchor.insetBy(dx: -8, dy: -8).contains(point) { closeTask?.cancel(); closeTask = nil }
        else { scheduleClose() }
        let nearEdge = NSScreen.screens.contains { screen in
            screen.frame.contains(point) && (point.x < screen.frame.minX + 180 || point.x > screen.frame.maxX - 180 || point.y < screen.frame.minY + 180)
        }
        guard nearEdge, !hitInFlight, Date.timeIntervalSinceReferenceDate - lastHitTime > 0.06 else { return }
        lastHitTime = Date.timeIntervalSinceReferenceDate
        hitInFlight = true
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        let axPoint = CGPoint(x: point.x, y: top - point.y)
        let hitSession = session
        hitQueue.async { [weak self] in
            var hit: DockHit?
            if let dockPID {
                let dock = AXUIElementCreateApplication(dockPID)
                AXUIElementSetMessagingTimeout(dock, 0.1)
                var element: AXUIElement?
                if AXUIElementCopyElementAtPosition(dock, Float(axPoint.x), Float(axPoint.y), &element) == .success {
                    for _ in 0..<5 {
                        guard let current = element else { break }
                        AXUIElementSetMessagingTimeout(current, 0.1)
                        if let value = axAttribute(current, kAXURLAttribute), let frame = axFrame(current) {
                            let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
                            if let url, url.isFileURL, url.pathExtension == "app" { hit = DockHit(url: url, frame: frame); break }
                        }
                        guard let parent = axAttribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
                        element = (parent as! AXUIElement)
                    }
                }
            }
            Task { @MainActor in
                guard let self else { return }
                self.hitInFlight = false
                guard self.enabled, self.session == hitSession else { return }
                self.process(hit, top: top)
            }
        }
    }

    private func process(_ hit: DockHit?, top: CGFloat) {
        guard let hit, let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL == hit.url.standardizedFileURL
        }), application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            hoverTask?.cancel(); hoverTask = nil; hoverPID = nil; return
        }
        let pid = application.processIdentifier
        let rect = CGRect(x: hit.frame.minX, y: top - hit.frame.maxY, width: hit.frame.width, height: hit.frame.height)
        guard rect.insetBy(dx: -12, dy: -12).contains(NSEvent.mouseLocation) else { return }
        closeTask?.cancel(); closeTask = nil
        anchor = rect
        if activePID == pid { return }
        guard hoverPID != pid else { return }
        hoverTask?.cancel(); hoverPID = pid
        let token = session
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled, self.session == token else { return }
            await self.windowService.refresh(pid: pid)
            guard !Task.isCancelled, self.session == token, self.anchor.insetBy(dx: -14, dy: -14).contains(NSEvent.mouseLocation) else { return }
            self.present(pid: pid)
        }
    }

    private func scheduleClose() {
        guard isPresented || hoverTask != nil else { return }
        guard closeTask == nil else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func present(pid: pid_t) {
        let records = favorites.sort(windowService.windows.filter { $0.pid == pid }, enabled: preferences.favoriteWindowsEnabled)
        guard !records.isEmpty else { return }
        activePID = pid
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        horizontal = orientation == "bottom"
        let cardWidth = preferences.interfaceDensity.cardWidth + 8
        let cardHeight = preferences.interfaceDensity.cardHeight + 61
        let previewCount = min(records.count, 3)
        let width: CGFloat = horizontal ? min(CGFloat(previewCount) * cardWidth + 24, screen.visibleFrame.width - 24) : preferences.interfaceDensity.cardWidth + 30
        let height: CGFloat = horizontal ? preferences.interfaceDensity.cardHeight + 126 : min(CGFloat(previewCount) * cardHeight + 76, screen.visibleFrame.height - 24)
        var origin: CGPoint
        switch orientation {
        case "right": origin = CGPoint(x: anchor.minX - width - 8, y: anchor.midY - height / 2)
        case "left": origin = CGPoint(x: anchor.maxX + 8, y: anchor.midY - height / 2)
        default: origin = CGPoint(x: anchor.midX - width / 2, y: anchor.maxY + 8)
        }
        origin.x = max(screen.visibleFrame.minX + 6, min(origin.x, screen.visibleFrame.maxX - width - 6))
        origin.y = max(screen.visibleFrame.minY + 6, min(origin.y, screen.visibleFrame.maxY - height - 6))
        let wasPresented = isPresented
        let newPanel = panel ?? NSPanel(contentRect: CGRect(origin: origin, size: CGSize(width: width, height: height)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        newPanel.isOpaque = false; newPanel.backgroundColor = .clear; newPanel.hasShadow = true
        newPanel.level = .popUpMenu; newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.hidesOnDeactivate = false; newPanel.isReleasedWhenClosed = false
        let content = DockPreviewView(pid: pid, horizontal: horizontal, windowService: windowService, previewService: previewService,
            preferences: preferences, favorites: favorites,
            onSelect: { [weak self] window in self?.windowService.focus(window, focusMode: self?.preferences.focusModeEnabled == true); self?.dismiss() },
            onFrames: { [weak self] frames in self?.updateFrames(frames) },
            onPeek: { [weak self] window, active in self?.setPeek(window: window, active: active) })
        if let hosting = newPanel.contentView as? NSHostingView<DockPreviewView> { hosting.rootView = content }
        else { newPanel.contentView = NSHostingView(rootView: content) }
        let target = CGRect(origin: origin, size: CGSize(width: width, height: height))
        panel = newPanel; isPresented = true; newPanel.ignoresMouseEvents = false
        if !wasPresented { newPanel.setFrame(target, display: false); newPanel.alphaValue = shouldAnimate ? 0 : 1 }
        newPanel.orderFrontRegardless()
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MacBDesign.openDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                newPanel.animator().setFrame(target, display: true)
                newPanel.animator().alphaValue = 1
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.isPresented else { return }
                    self.updateFrames(self.localCardFrames)
                }
            }
        } else { newPanel.alphaValue = 1; newPanel.setFrame(target, display: true) }
    }

    private func updateFrames(_ frames: [String: CGRect]) {
        guard let panel, isPresented else { return }
        localCardFrames = frames
        cardFrames = frames.mapValues { rect in
            CGRect(x: panel.frame.minX + rect.minX, y: panel.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        refreshVisiblePreviews()
    }

    private func refreshVisiblePreviews() {
        guard let panel, isPresented else { return }
        let visible = windowService.windows.filter { window in
            guard let frame = cardFrames[window.id] else { return false }
            let intersection = frame.intersection(panel.frame.insetBy(dx: 0, dy: 8))
            return intersection.height > 35 && intersection.width > 35
        }.sorted {
            if horizontal { return (cardFrames[$0.id]?.minX ?? 0) < (cardFrames[$1.id]?.minX ?? 0) }
            return (cardFrames[$0.id]?.maxY ?? 0) > (cardFrames[$1.id]?.maxY ?? 0)
        }
        visibleRecords = Array(visible.prefix(4))
        let token = session
        let records = visibleRecords
        Task { [weak self] in
            guard let self, self.session == token, self.isPresented else { return }
            await self.previewService.show(records)
        }
    }

    private func updateDrag(at point: CGPoint) {
        guard let window = visibleRecords.first(where: { cardFrames[$0.id]?.contains(point) == true }) else {
            dragTask?.cancel(); dragTask = nil; dragWindowID = nil; return
        }
        guard dragWindowID != window.id else { return }
        dragTask?.cancel(); dragWindowID = window.id
        dragTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled, self.dragging else { return }
            self.activatedDuringDrag = true
            self.windowService.focus(window, focusMode: self.preferences.focusModeEnabled)
            self.dismiss()
            NotificationCenter.default.post(name: .init("MacBDropTargetActivated"), object: nil)
        }
    }

    private func setPeek(window: WindowRecord, active: Bool) {
        guard preferences.peekEnabled else { hidePeek(); return }
        peekTask?.cancel()
        if !active { hidePeek(); return }
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self, !Task.isCancelled else { return }
            self.showPeek(for: window)
        }
    }

    private func showPeek(for window: WindowRecord) {
        hidePeek()
        guard !window.frame.isEmpty else { return }
        let panel = NSPanel(contentRect: window.frame.insetBy(dx: -5, dy: -5), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView:
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(MacBDesign.accent.opacity(0.75), lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: 14).fill(MacBDesign.accent.opacity(0.055)))
        )
        peekPanel = panel
        panel.alphaValue = shouldAnimate ? 0 : 1
        panel.orderFrontRegardless()
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    private func hidePeek() {
        peekTask?.cancel(); peekTask = nil
        guard let panel = peekPanel else { return }
        peekPanel = nil
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            } completionHandler: { panel.orderOut(nil) }
        } else { panel.orderOut(nil) }
    }
}

private struct CardFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

private struct DockPreviewView: View {
    let pid: pid_t
    let horizontal: Bool
    @ObservedObject var windowService: WindowService
    @ObservedObject var previewService: PreviewService
    @ObservedObject var preferences: Preferences
    @ObservedObject var favorites: FavoriteWindowStore
    let onSelect: (WindowRecord) -> Void
    let onFrames: ([String: CGRect]) -> Void
    let onPeek: (WindowRecord, Bool) -> Void
    private var windows: [WindowRecord] { favorites.sort(windowService.windows.filter { $0.pid == pid }, enabled: preferences.favoriteWindowsEnabled) }
    private var visibleWindows: [WindowRecord] { Array(windows.prefix(3)) }
    private var hiddenCount: Int { max(0, windows.count - visibleWindows.count) }
    private var favoriteCount: Int { windows.filter { favorites.isFavorite($0) }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            ScrollView(horizontal ? .horizontal : .vertical) {
                let layout = horizontal ? AnyLayout(HStackLayout(alignment: .top, spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
                layout {
                    ForEach(visibleWindows) { window in
                        WindowCardView(window: window, previewService: previewService,
                            isFavorite: favorites.isFavorite(window),
                            onSelect: { onSelect(window) }, onMinimize: { windowService.minimize(window) }, onClose: { windowService.close(window) },
                            onToggleFavorite: { favorites.toggle(window) }, onHover: { onPeek(window, $0) })
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: CardFramesKey.self, value: [window.id: proxy.frame(in: .named("panel"))])
                            })
                    }
                    if hiddenCount > 0 { moreCard }
                }.padding(.horizontal, 14).padding(.bottom, 12)
            }.scrollIndicators(.hidden)
            if let error = previewService.errorMessage { Text(error).font(.caption2).foregroundStyle(.secondary).padding([.horizontal, .bottom], 10) }
            else { footer.padding(.horizontal, 14).padding(.bottom, 12) }
        }.coordinateSpace(name: "panel").onPreferenceChange(CardFramesKey.self, perform: onFrames)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MacBDesign.corner))
            .overlay(RoundedRectangle(cornerRadius: MacBDesign.corner).strokeBorder(.white.opacity(0.075)))
            .preferredColorScheme(.dark)
            .task(id: visibleWindows.map(\.id).joined(separator: "|")) {
                await previewService.show(visibleWindows)
            }
            .task(id: pid) {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await windowService.refresh(pid: pid)
                }
            }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = visibleWindows.first?.appIcon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(windows.first?.appName ?? "Pencereler").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(summary).font(.system(size: 10)).foregroundStyle(.white.opacity(0.42)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(windows.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 7).frame(height: 22)
                .background(.white.opacity(0.08), in: Capsule())
        }
        .padding(.horizontal, 15).padding(.top, 13)
    }

    private var summary: String {
        if favoriteCount > 0 { return "\(favoriteCount) favori pencere" }
        return horizontal ? "Kartlara tıkla veya üstünde bekle" : "Önizleme hazır"
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "cursorarrow.motionlines").font(.system(size: 10, weight: .medium))
            Text("Bekle: konumu vurgula · Tıkla: öne getir")
                .font(.system(size: 10))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.34))
    }

    private var moreCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
            Text("+\(hiddenCount)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("daha fazla")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(width: preferences.interfaceDensity == .compact ? 74 : 84)
        .frame(height: preferences.interfaceDensity.cardHeight + 45)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.06)))
        .accessibilityLabel("\(hiddenCount) pencere daha var")
    }
}
