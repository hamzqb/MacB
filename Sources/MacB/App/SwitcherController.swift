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
    var pageCapacity = 4
    var selectedWindow: WindowRecord? { windows.first { $0.id == selectedID } }
    var visibleWindows: [WindowRecord] {
        let index = windows.firstIndex { $0.id == selectedID } ?? 0
        let start = (index / pageCapacity) * pageCapacity
        return Array(windows.dropFirst(start).prefix(pageCapacity))
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
            if self.model.windows.count > 1 { self.advance(backwards: backwards) }
            if self.commitWhenLoaded { self.commit() }
        }
    }

    private func update(_ records: [WindowRecord]) {
        let ranks = Dictionary(uniqueKeysWithValues: recentIDs.enumerated().map { ($1, $0) })
        let ordered = records.enumerated().sorted {
            if preferences.favoriteWindowsEnabled {
                let leftFavorite = favorites.isFavorite($0.element)
                let rightFavorite = favorites.isFavorite($1.element)
                if leftFavorite != rightFavorite { return leftFavorite }
            }
            if preferences.groupedWindowsEnabled {
                let appCompare = $0.element.appName.localizedCaseInsensitiveCompare($1.element.appName)
                if appCompare != .orderedSame { return appCompare == .orderedAscending }
            }
            let leftIsCurrent = $0.element.pid == initialApplication?.processIdentifier
            let rightIsCurrent = $1.element.pid == initialApplication?.processIdentifier
            if leftIsCurrent != rightIsCurrent { return leftIsCurrent }
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
        selection.advance(backwards: backwards)
        model.selectedID = selection.selectedID
        updatePreviews()
    }

    private func updatePreviews() {
        let records = model.visibleWindows
        let token = generation
        Task { [weak self] in
            guard let self, self.isVisible, token == self.generation else { return }
            await self.previews.show(records)
        }
    }

    private func present() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let width = min(1080, screen.visibleFrame.width - 40)
        model.pageCapacity = max(1, min(4, Int((width - 28) / (preferences.interfaceDensity.cardWidth + 12))))
        let size = NSSize(width: width, height: 432)
        let panel = SwitcherPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: SwitcherView(model: model, previews: previews, preferences: preferences, favorites: favorites, onChoose: { [weak self] window in
            self?.selection.select(window.id)
            self?.commit()
        }, onMinimize: { [weak self] window in
            self?.windowService.minimize(window)
        }, onClose: { [weak self] window in
            self?.windowService.close(window)
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
    @ObservedObject var preferences: Preferences
    @ObservedObject var favorites: FavoriteWindowStore
    var onChoose: (WindowRecord) -> Void
    var onMinimize: (WindowRecord) -> Void
    var onClose: (WindowRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pencereler").font(.system(size: 15, weight: .semibold))
                Text("\(model.windows.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                if preferences.groupedWindowsEnabled {
                    Text(groupedSummary).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                if let selected = model.windows.firstIndex(where: { $0.id == model.selectedID }), !model.windows.isEmpty {
                    Text("\(selected + 1) / \(model.windows.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 4)
            if model.isLoading {
                HStack { Spacer(); ProgressView("Pencereler yükleniyor…"); Spacer() }.frame(maxHeight: .infinity)
            } else if let message = model.message {
                VStack(spacing: 10) {
                    Image(systemName: "macwindow").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(message).font(.system(size: 13)).multilineTextAlignment(.center)
                    Text("Erişilebilirlik iznini MacB ayarlarından kontrol edebilirsin.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if let selectedWindow = model.selectedWindow {
                    SelectedWindowPreviewView(window: selectedWindow, previews: previews)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
                HStack(spacing: 12) {
                    ForEach(model.visibleWindows) { window in
                        WindowCardView(window: window, previewService: previews, isSelected: window.id == model.selectedID,
                                       isFavorite: favorites.isFavorite(window),
                                       onSelect: { onChoose(window) }, onMinimize: { onMinimize(window) }, onClose: { onClose(window) },
                                       onToggleFavorite: { favorites.toggle(window) })
                            .accessibilityAddTraits(window.id == model.selectedID ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 16) {
                    keyboardHint("⇥", "Sonraki")
                    keyboardHint("⇧ ⇥", "Önceki")
                    Spacer()
                    keyboardHint("esc", "Vazgeç")
                }.padding(.horizontal, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: MacBDesign.corner + 4))
        .overlay(RoundedRectangle(cornerRadius: MacBDesign.corner + 4).strokeBorder(.white.opacity(0.09)))
        .environment(\.colorScheme, .dark)
    }

    private func keyboardHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.system(size: 10, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 3)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 10))
        }.foregroundStyle(.secondary).accessibilityElement(children: .combine)
    }

    private var groupedSummary: String {
        let count = Set(model.windows.map(\.appName)).count
        return "\(count) uygulama"
    }

}

private struct SelectedWindowPreviewView: View {
    let window: WindowRecord
    @ObservedObject var previews: PreviewService

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = previews.images[window.id] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.22))
            } else {
                WindowPreviewPlaceholder(window: window)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.58)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            HStack(spacing: 10) {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.appName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                    Text(window.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                if window.isMinimized || previews.staleIDs.contains(window.id) {
                    Text(window.isMinimized ? "Küçültülmüş" : "Son görüntü")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.09), in: Capsule())
                }
            }
            .padding(14)
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MacBDesign.accent.opacity(0.42), lineWidth: 1))
        .accessibilityLabel("\(window.appName), \(window.title), seçili pencere önizlemesi")
    }
}
