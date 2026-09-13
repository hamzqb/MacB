import AppKit
import SwiftUI
import Combine
import MacBCore

private func switcherTitlesMatch(_ left: String, _ right: String) -> Bool {
    left.compare(right, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
}

private final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct DesktopWindowSection: Identifiable {
    let id: String
    let title: String
    let isCurrent: Bool
    let windows: [WindowRecord]
}

@MainActor final class SwitcherModel: ObservableObject {
    @Published var windows: [WindowRecord] = []
    @Published var selectedID: String?
    @Published var isLoading = false
    @Published var message: String?
    var selectedWindow: WindowRecord? { windows.first { $0.id == selectedID } }
    var selectedIndex: Int { windows.firstIndex { $0.id == selectedID } ?? 0 }
    fileprivate var desktopSections: [DesktopWindowSection] {
        let indexed = Dictionary(grouping: windows.compactMap { window -> (Int, WindowRecord)? in
            window.desktopIndex.map { ($0, window) }
        }, by: { $0.0 })
        var result = indexed.keys.sorted().map { index in
            let records = indexed[index, default: []].map(\.1)
            return DesktopWindowSection(id: "desktop-\(index)", title: "Masaüstü \(index)",
                isCurrent: records.contains { $0.desktopLocation == .current }, windows: records)
        }
        let unassigned = windows.filter { $0.desktopIndex == nil }
        if !unassigned.isEmpty {
            result.append(DesktopWindowSection(id: "desktop-current-fallback", title: "Bu Masaüstü",
                isCurrent: true, windows: unassigned))
        }
        return result.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }
    var previewWindows: [WindowRecord] {
        guard let selectedWindow else { return [] }
        let sameDesktop = windows.filter { candidate in
            guard candidate.id != selectedWindow.id else { return false }
            if let selectedIndex = selectedWindow.desktopIndex { return candidate.desktopIndex == selectedIndex }
            return candidate.desktopIndex == nil && candidate.desktopLocation == selectedWindow.desktopLocation
        }
        let sameDesktopIDs = Set(sameDesktop.map(\.id))
        let remaining = windows.filter { candidate in
            candidate.id != selectedWindow.id && !sameDesktopIDs.contains(candidate.id)
        }
        return Array(([selectedWindow] + sameDesktop + remaining).prefix(4))
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
            let leftIsOtherDesktop = $0.element.desktopLocation == .other
            let rightIsOtherDesktop = $1.element.desktopLocation == .other
            if leftIsOtherDesktop != rightIsOtherDesktop { return !leftIsOtherDesktop }
            let leftDesktop = $0.element.desktopIndex ?? Int.max
            let rightDesktop = $1.element.desktopIndex ?? Int.max
            if leftDesktop != rightDesktop { return leftDesktop < rightDesktop }
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
        let width = min(780, screen.visibleFrame.width - 40)
        let size = NSSize(width: width, height: min(300, screen.visibleFrame.height - 40))
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
        VStack(spacing: MacBDesign.Space.regular) {
            if model.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.message {
                Label(message, systemImage: "macwindow")
                    .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let selected = model.selectedWindow {
                selectionHeader(selected)
                HStack(spacing: MacBDesign.Space.comfortable) {
                    SwitcherSelectedPreview(window: selected, previews: previews) {
                        onChoose(selected)
                    }
                    desktopRail
                        .frame(width: 246)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: MacBDesign.Radius.panel).fill(MacBDesign.surface)
            } else {
                RoundedRectangle(cornerRadius: MacBDesign.Radius.panel).fill(.regularMaterial)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: MacBDesign.Radius.panel).strokeBorder(MacBDesign.separator, lineWidth: 0.5))
        .animation(animationsEnabled && !reduceMotion ? MacBDesign.Motion.instant : nil, value: model.selectedID)
    }

    private var desktopRail: some View {
        ScrollViewReader { proxy in
            VStack(spacing: MacBDesign.Space.close) {
                if model.desktopSections.count > 1 {
                    HStack(spacing: MacBDesign.Space.snug) {
                        ForEach(model.desktopSections) { section in
                            Button {
                                if animationsEnabled && !reduceMotion {
                                    withAnimation(MacBDesign.Motion.quick) { proxy.scrollTo(section.id, anchor: .top) }
                                } else {
                                    proxy.scrollTo(section.id, anchor: .top)
                                }
                            } label: {
                                HStack(spacing: MacBDesign.Space.tight) {
                                    Image(systemName: section.isCurrent ? "rectangle.fill" : "rectangle")
                                    Text(section.title)
                                    Text("\(section.windows.count)").monospacedDigit().foregroundStyle(.secondary)
                                }
                                .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                                .padding(.horizontal, MacBDesign.Space.close).padding(.vertical, MacBDesign.Space.snug)
                                .background(section.isCurrent ? MacBDesign.selectedBackground.opacity(0.42) : Color.primary.opacity(0.055),
                                            in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: MacBDesign.Space.regular) {
                        ForEach(Array(model.desktopSections.enumerated()), id: \.element.id) { index, section in
                            if index > 0 { Divider().opacity(0.55) }
                            windowSection(title: section.title,
                                          systemImage: section.isCurrent ? "rectangle" : "square.stack.3d.up",
                                          windows: section.windows)
                                .id(section.id)
                        }
                    }
                }
                .onChange(of: model.selectedID) { _, selectedID in
                    guard let selectedID else { return }
                    if animationsEnabled && !reduceMotion {
                        withAnimation(MacBDesign.Motion.instant) { proxy.scrollTo(selectedID, anchor: .center) }
                    } else {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder private func windowSection(title: String, systemImage: String, windows: [WindowRecord]) -> some View {
        if !windows.isEmpty {
            VStack(spacing: MacBDesign.Space.snug) {
                HStack(spacing: MacBDesign.Space.snug) {
                    Image(systemName: systemImage).font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                    Text(title).font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                    Spacer(minLength: 4)
                    Text("\(windows.count)")
                        .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold, design: .rounded)).monospacedDigit()
                        .padding(.horizontal, MacBDesign.Space.snug).padding(.vertical, MacBDesign.Space.hair)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, MacBDesign.Space.tight)
                ForEach(windows) { window in
                    SwitcherWindowCard(window: window, selected: window.id == model.selectedID,
                        position: (model.windows.firstIndex { $0.id == window.id } ?? 0) + 1,
                        total: model.windows.count, previews: previews) {
                        onChoose(window)
                    }
                    .id(window.id)
                }
            }
        }
    }

    private func selectionHeader(_ window: WindowRecord) -> some View {
        HStack(spacing: MacBDesign.Space.close) {
            if let icon = window.appIcon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
            }
            Text(window.appName).font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold)).foregroundStyle(.primary)
            if !switcherTitlesMatch(window.appName, window.title) {
                Text(window.title).font(.system(size: MacBDesign.TypeScale.caption)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(model.selectedIndex + 1) / \(model.windows.count)")
                .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .frame(height: 24)
        .padding(.horizontal, MacBDesign.Space.hair)
    }

}

private struct SwitcherSelectedPreview: View {
    let window: WindowRecord
    @ObservedObject var previews: PreviewService
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Color.black.opacity(0.58)
                if let image = previews.images[window.id] {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    WindowPreviewPlaceholder(window: window, compact: false)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                HStack(spacing: MacBDesign.Space.close) {
                    if let icon = window.appIcon {
                        Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    }
                    Text(window.title).font(.system(size: MacBDesign.TypeScale.body, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    if window.isMinimized {
                        Label("Küçültülmüş", systemImage: "minus.circle.fill")
                            .font(.system(size: MacBDesign.TypeScale.micro, weight: .medium)).foregroundStyle(.secondary)
                    }
                    if window.desktopLocation == .other {
                        Label(window.desktopName ?? "Diğer masaüstü", systemImage: "square.stack.3d.up.fill")
                            .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .padding(MacBDesign.Space.regular)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous)
                .strokeBorder(MacBDesign.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(window.appName), \(window.title), seçili pencereye geç")
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
            HStack(spacing: MacBDesign.Space.regular) {
                ZStack {
                    if let image = previews.images[window.id] {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else if let icon = window.appIcon {
                        Image(nsImage: icon).resizable().scaledToFit().padding(MacBDesign.Space.regular)
                    } else {
                        Image(systemName: "macwindow").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 56, height: 40)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: MacBDesign.Space.tight) {
                    Text(window.title)
                        .font(.system(size: MacBDesign.TypeScale.caption, weight: selected ? .semibold : .medium))
                        .foregroundStyle(.primary).lineLimit(1)
                    if !switcherTitlesMatch(window.appName, window.title) {
                        Text(window.appName)
                            .font(.system(size: MacBDesign.TypeScale.micro)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: MacBDesign.TypeScale.body)).foregroundStyle(MacBDesign.accent)
                }
            }
            .padding(MacBDesign.Space.close)
            .frame(height: 54)
            .background(selected ? MacBDesign.selectedBackground.opacity(0.48) : Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MacBDesign.Radius.card)
                .strokeBorder(selected ? MacBDesign.focusRing : .clear, lineWidth: selected ? 1.5 : 0))
            .contentShape(RoundedRectangle(cornerRadius: MacBDesign.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(window.appName), \(window.title), \(position) / \(total)")
        .accessibilityHint(selected ? "Seçili pencere" : "Bu pencereye geç")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
