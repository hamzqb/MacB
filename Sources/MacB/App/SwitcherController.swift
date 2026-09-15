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

/// Where a card sits in the grid, so the arrow keys can move by what is drawn
/// rather than by a position in a flat list.
struct GridPosition: Equatable {
    let section: Int
    let row: Int
    let column: Int
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
    /// True when the message is the one the user can actually do something
    /// about, so the view can offer the button rather than only the sentence.
    @Published var needsAccessibility = false
    /// What has been typed while the switcher is up. Empty means everything.
    @Published var filter = ""
    var selectedWindow: WindowRecord? { windows.first { $0.id == selectedID } }
    var selectedIndex: Int { windows.firstIndex { $0.id == selectedID } ?? 0 }
    /// The windows the filter leaves, in display order.
    ///
    /// Matched loosely on purpose: somebody typing "chr" wants Chrome, and
    /// somebody typing part of a page title wants that tab's window.
    var matchingWindows: [WindowRecord] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return windows }
        return windows.filter { window in
            window.appName.localizedStandardContains(needle)
                || window.title.localizedStandardContains(needle)
        }
    }

    fileprivate var desktopSections: [DesktopWindowSection] {
        let indexed = Dictionary(grouping: matchingWindows.compactMap { window -> (Int, WindowRecord)? in
            window.desktopIndex.map { ($0, window) }
        }, by: { $0.0 })
        var result = indexed.keys.sorted().map { index in
            let records = indexed[index, default: []].map(\.1)
            return DesktopWindowSection(id: "desktop-\(index)", title: "Masaüstü \(index)",
                isCurrent: records.contains { $0.desktopLocation == .current }, windows: records)
        }
        let unassigned = matchingWindows.filter { $0.desktopIndex == nil }
        if !unassigned.isEmpty {
            result.append(DesktopWindowSection(id: "desktop-current-fallback", title: "Bu Masaüstü",
                isCurrent: true, windows: unassigned))
        }
        return result.sorted {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }
    /// How many cards the grid puts on a row. The view lays out the same number.
    static let gridColumns = 4

    /// Every window's place in the grid, built from the same sections the view
    /// draws so the two cannot drift apart.
    var gridPositions: [String: GridPosition] {
        var result: [String: GridPosition] = [:]
        for (sectionIndex, section) in desktopSections.enumerated() {
            for (offset, window) in section.windows.enumerated() {
                result[window.id] = GridPosition(section: sectionIndex,
                                                 row: offset / Self.gridColumns,
                                                 column: offset % Self.gridColumns)
            }
        }
        return result
    }

    /// The window at a place in the grid, or the nearest one on that row.
    ///
    /// Moving off the end of a row lands on the last card of it rather than
    /// nowhere, because a key press that does nothing reads as a dead key.
    func window(at position: GridPosition) -> String? {
        let sections = desktopSections
        guard position.row >= 0, position.column >= 0,
              sections.indices.contains(position.section) else { return nil }
        let windows = sections[position.section].windows
        let start = position.row * Self.gridColumns
        guard start < windows.count else { return nil }
        let index = min(start + position.column, windows.count - 1)
        return windows[index].id
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
    private let permissions: PermissionStore
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

    init(windowService: WindowService, previewService: PreviewService, preferences: Preferences,
         favorites: FavoriteWindowStore, permissions: PermissionStore) {
        self.windowService = windowService
        self.previews = previewService
        self.preferences = preferences
        self.favorites = favorites
        self.permissions = permissions
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
        model.needsAccessibility = false
        model.filter = ""
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
        // Two different orders, on purpose. The grid is grouped by desktop
        // because that is how somebody reads it; Tab walks most-recently-used
        // because that is how somebody uses it.
        model.windows = ordered
        // Through the filter, so a refresh while somebody is typing does not
        // quietly put the windows they just excluded back in the Tab order.
        selection.replace(with: traversalOrder(model.matchingWindows))
        resizePanel()
        model.selectedID = selection.selectedID
        model.message = ordered.isEmpty ? (windowService.errorMessage ?? "Gösterilecek pencere bulunamadı.") : nil
        model.needsAccessibility = ordered.isEmpty && !AXIsProcessTrusted()
        updatePreviews()
    }

    /// The order Tab walks: what you used last, first.
    ///
    /// This used to be the same list the grid draws, which is grouped by
    /// desktop and then pulls every window of the frontmost application to the
    /// front. That made the commonest switch of all impossible: tapping the
    /// shortcut while sitting in one of five Chrome windows moved to another
    /// Chrome window rather than back to the thing you had just come from, so
    /// bouncing between two windows could not be done at all.
    ///
    /// Position zero is whatever is in front right now, so a single tap always
    /// lands on the window before it.
    private func traversalOrder(_ records: [WindowRecord]) -> [String] {
        let ranks = Dictionary(uniqueKeysWithValues: recentIDs.enumerated().map { ($1, $0) })
        let ordered = records.enumerated().sorted {
            // Anything MacB has not seen switched to keeps the window service's
            // own front-to-back order, which is the best guess available.
            let left = ranks[$0.element.id] ?? (1000 + $0.offset)
            let right = ranks[$1.element.id] ?? (1000 + $1.offset)
            return left < right
        }.map(\.element)
        var ids = ordered.map(\.id)
        // Switching with the mouse never reaches recentIDs, so the front window
        // is taken from the system rather than from MacB's own memory.
        if let pid = initialApplication?.processIdentifier,
           let current = ordered.first(where: { $0.pid == pid }),
           let index = ids.firstIndex(of: current.id), index != 0 {
            ids.remove(at: index)
            ids.insert(current.id, at: 0)
        }
        return ids
    }

    /// Narrows the list to what has been typed.
    ///
    /// The selection is kept when the window it points at survives the filter,
    /// so typing more letters does not keep throwing somebody back to the top.
    private func setFilter(_ text: String) {
        model.filter = text
        let visible = model.matchingWindows.map(\.id)
        let ordered = traversalOrder(model.matchingWindows)
        selection.replace(with: ordered)
        if let selected = model.selectedID, visible.contains(selected) {
            selection.select(selected)
        } else {
            selection.select(ordered.first ?? "")
        }
        model.selectedID = selection.selectedID
        resizePanel()
        updatePreviews()
    }

    /// Moves by a row or a column of the grid, rather than by one place in the
    /// Tab order. Up and down used to do exactly what left and right did, which
    /// in a one-column list was honest and in a grid is not.
    private func move(rows: Int, columns: Int) {
        guard !model.isLoading, !model.windows.isEmpty else { return }
        guard let current = model.selectedID,
              let position = model.gridPositions[current] else { return }
        let target = GridPosition(section: position.section,
                                  row: position.row + rows,
                                  column: position.column + columns)
        guard let id = model.window(at: target) else { return }
        selection.select(id)
        model.selectedID = id
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

    /// The panel is only as big as what is in it.
    ///
    /// It used to be a fixed seven hundred and sixty by four hundred and
    /// twenty whatever it held, so five windows left the bottom half of it
    /// empty and the whole thing read as a page that had failed to load.
    private static func panelSize(for model: SwitcherModel, on screen: NSScreen) -> NSSize {
        let cards = max(model.windows.count, 1)
        let columns = min(SwitcherModel.gridColumns, cards)
        let contentWidth = CGFloat(columns) * 168 + CGFloat(columns - 1) * 12
        // Wide enough for the caption line under a long window title even when
        // only one card sits above it.
        let width = min(max(contentWidth + 28, 360), screen.visibleFrame.width - 40)

        let sections = model.desktopSections
        let showsHeadings = sections.count > 1
        var content: CGFloat = 0
        for (index, section) in sections.enumerated() {
            if index > 0 { content += 16 }
            if showsHeadings { content += 16 + 8 }
            let rows = max(1, Int(ceil(Double(section.windows.count) / Double(SwitcherModel.gridColumns))))
            content += CGFloat(rows) * 126 + CGFloat(rows - 1) * 12
        }
        if sections.isEmpty { content = 120 }
        // Outer padding, the scroll view's own inset, and the caption line.
        let height = min(content + 28 + 8 + 34, screen.visibleFrame.height - 40)
        return NSSize(width: width, height: max(height, 160))
    }

    /// Fits the panel to the windows once they have actually arrived.
    private func resizePanel() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let size = Self.panelSize(for: model, on: screen)
        guard abs(panel.frame.width - size.width) > 0.5
                || abs(panel.frame.height - size.height) > 0.5 else { return }
        let origin = NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                             y: screen.visibleFrame.midY - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true,
                       animate: false)
    }

    private func present() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let size = Self.panelSize(for: model, on: screen)
        let width = size.width
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
        }, onOpenAccessibility: { [weak self] in
            self?.permissions.openPrivacy("Privacy_Accessibility")
            self?.dismiss(restoreFocus: false)
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
            case 53:
                // Escape clears the search before it closes the switcher, so a
                // mistyped letter does not cost the whole switch.
                if !self.model.filter.isEmpty { self.setFilter("") } else { self.dismiss(restoreFocus: true) }
                return nil
            case 36, 76: self.commit(); return nil
            case 48: self.advance(backwards: event.modifierFlags.contains(.shift)); return nil
            case 124: self.move(rows: 0, columns: 1); return nil
            case 123: self.move(rows: 0, columns: -1); return nil
            case 125: self.move(rows: 1, columns: 0); return nil
            case 126: self.move(rows: -1, columns: 0); return nil
            case 51:
                guard !self.model.filter.isEmpty else { return nil }
                self.setFilter(String(self.model.filter.dropLast()))
                return nil
            default:
                guard let typed = event.charactersIgnoringModifiers,
                      typed.count == 1,
                      let scalar = typed.unicodeScalars.first,
                      !CharacterSet.controlCharacters.contains(scalar),
                      !CharacterSet.illegalCharacters.contains(scalar) else { return event }
                self.setFilter(self.model.filter + typed)
                return nil
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

/// Every window as an equal card, grouped by desktop.
///
/// The old layout gave two thirds of the panel to one window and squeezed the
/// rest into a narrow list, and it said the same things repeatedly: the title
/// appeared in a header, again under the big preview and again in the list row,
/// and each desktop was named once as a tab and again as a section heading
/// directly beneath it. Nothing here is written twice. The thumbnails tell the
/// windows apart, the card labels name the applications, and the full title of
/// whichever window is selected is spelled out once, at the bottom.
private struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    @ObservedObject var previews: PreviewService
    var onChoose: (WindowRecord) -> Void
    var onOpenAccessibility: () -> Void
    @AppStorage("animationsEnabled") private var animationsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Four across. Wide enough that a window is recognisable from its
    /// thumbnail, narrow enough that a dozen windows still fit without
    /// scrolling.
    private static let cardWidth: CGFloat = 168
    private static let cardHeight: CGFloat = 106

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(Self.cardWidth), spacing: MacBDesign.Space.comfortable,
                                  alignment: .top), count: SwitcherModel.gridColumns)
    }

    var body: some View {
        VStack(spacing: MacBDesign.Space.comfortable) {
            if model.isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.message {
                empty(message)
            } else {
                if !model.filter.isEmpty { searchLine }
                if model.desktopSections.isEmpty {
                    Text("“\(model.filter)” ile eşleşen pencere yok.")
                        .font(.system(size: MacBDesign.TypeScale.body))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    grid
                }
                if let selected = model.selectedWindow { caption(selected) }
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

    /// What is shown when there is nothing to show.
    ///
    /// A missing permission used to be a sentence and nothing else: no button,
    /// no explanation of why it had stopped working. MacB loses this grant every
    /// time it is updated, because the grant is tied to the exact copy of the
    /// application macOS saw last, so this is the state somebody meets after
    /// every update -- and the sentence sent them off to find the setting
    /// themselves. The code to open that very pane was already here.
    private func empty(_ message: String) -> some View {
        VStack(spacing: MacBDesign.Space.comfortable) {
            Image(systemName: model.needsAccessibility ? "hand.raised" : "macwindow")
                .font(.system(size: MacBDesign.TypeScale.hero, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .medium))
            if model.needsAccessibility {
                Text("MacB her güncellendiğinde macOS bu izni sıfırlar. Açtığında pencere seçici hemen çalışır.")
                    .font(.system(size: MacBDesign.TypeScale.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                Button("Erişilebilirlik ayarlarını aç") { onOpenAccessibility() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shown only once something has been typed. An empty search field sitting
    /// there permanently would be one more thing to read every time the
    /// switcher opens, for a feature most switches never need.
    private var searchLine: some View {
        HStack(spacing: MacBDesign.Space.snug) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: MacBDesign.TypeScale.caption, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(model.filter)
                .font(.system(size: MacBDesign.TypeScale.body, weight: .medium))
            Spacer(minLength: MacBDesign.Space.close)
            Text("esc ile temizle")
                .font(.system(size: MacBDesign.TypeScale.micro))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, MacBDesign.Space.regular)
        .padding(.vertical, MacBDesign.Space.snug)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: MacBDesign.Space.loose) {
                    ForEach(model.desktopSections) { section in
                        VStack(alignment: .leading, spacing: MacBDesign.Space.close) {
                            // Only when there is more than one desktop. With a
                            // single desktop the heading names something nobody
                            // has to choose between.
                            if model.desktopSections.count > 1 { sectionHeading(section) }
                            LazyVGrid(columns: columns, alignment: .leading,
                                      spacing: MacBDesign.Space.comfortable) {
                                ForEach(section.windows) { window in
                                    SwitcherWindowCard(
                                        window: window,
                                        selected: window.id == model.selectedID,
                                        position: (model.windows.firstIndex { $0.id == window.id } ?? 0) + 1,
                                        total: model.windows.count,
                                        width: Self.cardWidth, height: Self.cardHeight,
                                        previews: previews) { onChoose(window) }
                                        .id(window.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, MacBDesign.Space.hair)
                .padding(.vertical, MacBDesign.Space.tight)
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

    private func sectionHeading(_ section: DesktopWindowSection) -> some View {
        HStack(spacing: MacBDesign.Space.snug) {
            Image(systemName: section.isCurrent ? "rectangle.fill" : "square.stack.3d.up")
            Text(section.title)
            Text("\(section.windows.count)")
                .monospacedDigit()
                .padding(.horizontal, MacBDesign.Space.snug)
                .padding(.vertical, MacBDesign.Space.hair)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    /// The one place the selected window's full title is written out.
    private func caption(_ window: WindowRecord) -> some View {
        HStack(spacing: MacBDesign.Space.close) {
            if let icon = window.appIcon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18).accessibilityHidden(true)
            }
            Text(window.title)
                .font(.system(size: MacBDesign.TypeScale.emphasis, weight: .semibold))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: MacBDesign.Space.close)
            Text("\(model.selectedIndex + 1) / \(model.windows.count)")
                .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .frame(height: 22)
    }
}

/// One window in the grid.
private struct SwitcherWindowCard: View {
    let window: WindowRecord
    let selected: Bool
    let position: Int
    let total: Int
    let width: CGFloat
    let height: CGFloat
    @ObservedObject var previews: PreviewService
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: MacBDesign.Space.snug) {
                thumbnail
                Text(window.appName)
                    .font(.system(size: MacBDesign.TypeScale.caption,
                                  weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: width)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(selected ? 1.03 : 1)
        .accessibilityLabel("\(window.appName), \(window.title), \(position) / \(total)")
        .accessibilityHint(selected ? "Seçili pencere" : "Bu pencereye geç")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.35)
            // Filled rather than fitted. Fitting a wide window into this box
            // left black bars down both sides and shrank the only part of the
            // card that tells one window from another.
            if let image = previews.images[window.id] {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let icon = window.appIcon {
                // Just the icon, faint and large. The shared placeholder draws
                // a little mock window with traffic lights and grey bars, which
                // at this size reads as a real window that failed to render
                // rather than as a picture that has not arrived yet.
                Image(nsImage: icon).resizable().scaledToFit()
                    .frame(width: 44, height: 44)
                    .opacity(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: MacBDesign.TypeScale.display, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if let icon = window.appIcon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    .padding(MacBDesign.Space.snug)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) { badge }
        .overlay(
            RoundedRectangle(cornerRadius: MacBDesign.Radius.card, style: .continuous)
                .strokeBorder(selected ? MacBDesign.accent : MacBDesign.separator,
                              lineWidth: selected ? 2 : 0.5))
    }

    /// Says only what the thumbnail cannot: that the window is put away, or
    /// that reaching it means changing desktop.
    @ViewBuilder private var badge: some View {
        if window.isMinimized {
            marker("minus.circle.fill", "Küçültülmüş")
        } else if window.desktopLocation == .other {
            marker("square.stack.3d.up.fill", window.desktopName ?? "Diğer masaüstü")
        }
    }

    private func marker(_ symbol: String, _ label: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: MacBDesign.TypeScale.micro, weight: .semibold))
            .foregroundStyle(.white)
            .padding(MacBDesign.Space.tight)
            .background(.black.opacity(0.55), in: Circle())
            .padding(MacBDesign.Space.snug)
            .accessibilityLabel(label)
    }
}
