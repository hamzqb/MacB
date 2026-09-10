import AppKit
import SwiftUI
import Combine
import MacBCore

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class SwitcherModel: ObservableObject {
    @Published var windows: [WindowRecord] = []
    @Published var selectedID: String?
    @Published var isLoading = false
    @Published var message: String?
    var selectedWindow: WindowRecord? { windows.first { $0.id == selectedID } }
    var selectedIndex: Int { windows.firstIndex { $0.id == selectedID } ?? 0 }
    var visibleWindows: [WindowRecord] {
        let capacity = 4
        let start = min(max(0, selectedIndex - 1), max(0, windows.count - capacity))
        return Array(windows.dropFirst(start).prefix(capacity))
    }
    var previewWindows: [WindowRecord] {
        guard let selectedWindow else { return [] }
        return [selectedWindow] + visibleWindows.filter { $0.id != selectedWindow.id }
    }
}

@MainActor final class SwitcherController {
    private let windowService: WindowService
    private let previews: PreviewService
    private let preferences: Preferences
    private let favorites: FavoriteWindowStore
    private let model = SwitcherModel()
    private var selection = WindowSelection()
    private var panel: SwitcherPanel?
    private var keyMonitor: Any?
    private var globalMonitor: Any?
    private var flagsTimer: Timer?
    private var refreshTimer: Timer?
    private var subscription: AnyCancellable?
    private var initialApplication: NSRunningApplication?
    private var generation = 0
    private var commitWhenLoaded = false
    private var pendingAdvances = 0
    private var requiredFlags: NSEvent.ModifierFlags = [.option]
    private var recentIDs: [String] = []
    private var shouldAnimate: Bool { (UserDefaults.standard.object(forKey: "animationsEnabled") as? Bool ?? true) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private(set) var isVisible = false
    var onWillOpen: (() -> Void)?

    init(windowService: WindowService, previewService: PreviewService, preferences: Preferences, favorites: FavoriteWindowStore) {
        self.windowService = windowService
        self.previews = previewService
        self.preferences = preferences
        self.favorites = favorites
        subscription = windowService.$windows.dropFirst().sink { [weak self] records in
            guard let self, self.isVisible, !self.model.isLoading else { return }
            self.update(records)
        }
    }

    func begin(backwards: Bool, shortcut: SwitcherShortcut) {
        if isVisible { advance(backwards: backwards); return }
        onWillOpen?()
        isVisible = true
        generation += 1
        let token = generation
        requiredFlags = shortcut.requiredFlags
        commitWhenLoaded = false
        pendingAdvances = backwards ? -1 : 1
        initialApplication = NSWorkspace.shared.frontmostApplication
        model.isLoading = true
        model.windows = []
        model.message = nil
        selection = WindowSelection()
        present()
        installMonitors()
        Task { [weak self] in
            guard let self else { return }
            await self.windowService.refresh()
            guard self.isVisible, self.generation == token else { return }
            self.model.isLoading = false
            self.update(self.windowService.windows)
            let pending = self.pendingAdvances
            self.pendingAdvances = 0
            if !self.model.windows.isEmpty {
                for _ in 0..<abs(pending) { self.advance(backwards: pending < 0) }
            }
            if self.commitWhenLoaded { self.commit() }
        }
    }

    func showDevelopmentPreview() {
        guard !isVisible else { return }
        onWillOpen?()
        isVisible = true
        generation += 1
        let token = generation
        initialApplication = NSWorkspace.shared.frontmostApplication
        model.isLoading = true
        model.windows = []
        model.message = nil
        selection = WindowSelection()
        present()
        Task { [weak self] in
            guard let self else { return }
            await self.windowService.refresh()
            guard self.isVisible, self.generation == token else { return }
            self.model.isLoading = false
            self.update(self.windowService.windows)
            if self.model.windows.count > 1 { self.advance(backwards: false) }
        }
    }

    private func update(_ records: [WindowRecord]) {
        let ranks = Dictionary(uniqueKeysWithValues: recentIDs.enumerated().map { ($1, $0) })
        let ordered = records.enumerated().sorted {
            let leftIsCurrent = $0.element.pid == initialApplication?.processIdentifier
            let rightIsCurrent = $1.element.pid == initialApplication?.processIdentifier
            if leftIsCurrent != rightIsCurrent { return leftIsCurrent }
            if preferences.favoriteWindowsEnabled {
                let leftFavorite = favorites.isFavorite($0.element)
                let rightFavorite = favorites.isFavorite($1.element)
                if leftFavorite != rightFavorite { return leftFavorite }
            }
            let left = ranks[$0.element.id] ?? (1000 + $0.offset)
            let right = ranks[$1.element.id] ?? (1000 + $1.offset)
            return left < right
        }.map(\.element)
        selection.replace(with: ordered.map(\.id))
        model.windows = ordered
        model.selectedID = selection.selectedID
        model.message = ordered.isEmpty ? (windowService.errorMessage ?? "Gösterilecek pencere bulunamadı.") : nil
        updatePreviews()
    }

    private func advance(backwards: Bool) {
        if model.isLoading {
            pendingAdvances += backwards ? -1 : 1
            return
        }
        selection.advance(backwards: backwards)
        model.selectedID = selection.selectedID
        updatePreviews()
    }

    private func updatePreviews() {
        let records = model.previewWindows
        let token = generation
        Task { [weak self] in
            guard let self, self.isVisible, token == self.generation else { return }
            await self.previews.show(records)
        }
    }

    private func present() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let width = min(680, screen.visibleFrame.width - 40)
        let size = NSSize(width: width, height: min(190, screen.visibleFrame.height - 40))
        let panel = SwitcherPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: SwitcherView(model: model, previews: previews, onChoose: { [weak self] window in
            self?.selection.select(window.id)
            self?.commit()
        }))
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.midY - size.height / 2))
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = shouldAnimate ? 0 : 1
        panel.makeKeyAndOrderFront(nil)
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MacBDesign.openDuration
                panel.animator().alphaValue = 1
            }
        }
    }

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.type == .flagsChanged {
                self.checkModifiers(event.modifierFlags)
                return event
            }
            switch event.keyCode {
            case 53: self.dismiss(restoreFocus: true); return nil
            case 36, 76: self.commit(); return nil
            case 48, 124, 125: self.advance(backwards: event.modifierFlags.contains(.shift)); return nil
            case 123, 126: self.advance(backwards: true); return nil
            default: return event
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss(restoreFocus: false) }
        }
        flagsTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkModifiers(NSEvent.modifierFlags) }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isVisible, !self.model.isLoading else { return }
                await self.windowService.refresh()
            }
        }
    }

    private func checkModifiers(_ flags: NSEvent.ModifierFlags) {
        guard isVisible, !flags.isSuperset(of: requiredFlags) else { return }
        if model.isLoading { commitWhenLoaded = true } else { commit() }
    }

    private func commit() {
        if model.isLoading { commitWhenLoaded = true; return }
        guard let selected = model.windows.first(where: { $0.id == selection.selectedID }) else {
            dismiss(restoreFocus: true)
            return
        }
        recentIDs.removeAll { $0 == selected.id }
        recentIDs.insert(selected.id, at: 0)
        if recentIDs.count > 100 { recentIDs.removeLast(recentIDs.count - 100) }
        dismiss(restoreFocus: false)
        windowService.focus(selected, focusMode: preferences.focusModeEnabled)
    }

    func dismiss(restoreFocus: Bool = false) {
        guard isVisible else { return }
        isVisible = false
        generation += 1
        pendingAdvances = 0
        flagsTimer?.invalidate(); flagsTimer = nil
        refreshTimer?.invalidate(); refreshTimer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        keyMonitor = nil; globalMonitor = nil
        if let panel {
            panel.ignoresMouseEvents = true
            if shouldAnimate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = MacBDesign.closeDuration
                    panel.animator().alphaValue = 0
                } completionHandler: { panel.orderOut(nil) }
            } else { panel.orderOut(nil) }
        }
        panel = nil
        previews.stop()
        NotificationCenter.default.post(name: Notification.Name("MacBSwitcherClosed"), object: nil)
        if restoreFocus { initialApplication?.activate(options: []) }
        initialApplication = nil
    }
}

private struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @ObservedObject var previews: PreviewService
    var onChoose: (WindowRecord) -> Void
    @AppStorage("animationsEnabled") private var animationsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 9) {
            if model.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.message {
                Label(message, systemImage: "macwindow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let selected = model.selectedWindow {
                selectionHeader(selected)
                HStack(spacing: 9) {
                    ForEach(model.visibleWindows) { window in
                        SwitcherWindowCard(window: window, selected: window.id == model.selectedID,
                            position: (model.windows.firstIndex { $0.id == window.id } ?? 0) + 1,
                            total: model.windows.count, previews: previews) {
                            onChoose(window)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: MacBDesign.Radius.panel).fill(MacBDesign.surface)
            } else {
                RoundedRectangle(cornerRadius: MacBDesign.Radius.panel).fill(.regularMaterial)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: MacBDesign.Radius.panel).strokeBorder(MacBDesign.separator, lineWidth: 0.5))
        .animation(animationsEnabled && !reduceMotion ? .easeOut(duration: 0.13) : nil, value: model.selectedID)
    }

    private func selectionHeader(_ window: WindowRecord) -> some View {
        HStack(spacing: 8) {
            if let icon = window.appIcon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
            }
            Text(window.appName).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
            if !titlesMatch(window.appName, window.title) {
                Text(window.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(model.selectedIndex + 1) / \(model.windows.count)")
                .font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .frame(height: 22)
        .padding(.horizontal, 2)
    }

    private func titlesMatch(_ left: String, _ right: String) -> Bool {
        left.compare(right, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

private struct SwitcherWindowCard: View {
    let window: WindowRecord
    let selected: Bool
    let position: Int
    let total: Int
    @ObservedObject var previews: PreviewService
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    if let image = previews.images[window.id] {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        WindowPreviewPlaceholder(window: window, compact: true)
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.42)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                    if let icon = window.appIcon {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1).padding(7).accessibilityHidden(true)
                    }
                    if window.isMinimized || previews.staleIDs.contains(window.id) {
                        HStack {
                            Spacer()
                            Image(systemName: window.isMinimized ? "minus.circle.fill" : "clock.fill")
                                .font(.system(size: 10)).padding(7)
                        }.foregroundStyle(.white.opacity(0.78))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacBDesign.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: MacBDesign.Radius.control))

                Text(window.title)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? MacBDesign.selectedBackground.opacity(0.55) : MacBDesign.controlBackground.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: MacBDesign.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: MacBDesign.Radius.card)
                .strokeBorder(selected ? MacBDesign.focusRing : MacBDesign.separator, lineWidth: selected ? 2 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: MacBDesign.Radius.card))
        }
        .buttonStyle(.plain)
        .help("\(window.appName) — \(window.title)")
        .accessibilityLabel("\(window.appName), \(window.title), \(position) / \(total)")
        .accessibilityHint(selected ? "Seçili pencere" : "Bu pencereye geç")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
