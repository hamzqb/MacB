import AppKit
import Combine
import MacBCore
import SwiftUI

/// Puts MacB's widgets on the desktop.
///
/// Each widget is its own borderless panel sitting just above the desktop
/// icons: below every ordinary window, on every Space, never in ⌘Tab and never
/// stealing focus. Dragging one anywhere moves it, and where it lands is kept
/// as a fraction of the screen, so widgets keep their corner when the display
/// changes.
@MainActor final class DesktopWidgetController: NSObject {
    private let store: DesktopWidgetStore
    private let services: DesktopWidgetServices
    private var windows: [UUID: NSPanel] = [:]
    /// What each window is currently showing, so a save does not rebuild
    /// every widget's view.
    private var rendered: [UUID: DesktopWidget] = [:]
    /// True while a drag of ours is writing its position back.
    private var isRecordingDrag = false
    private var subscriptions: Set<AnyCancellable> = []
    private var isEnabled = false

    init(store: DesktopWidgetStore, services: DesktopWidgetServices) {
        self.store = store
        self.services = services
        super.init()
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.place() }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        enabled ? refresh() : closeAll()
    }

    func stop() { closeAll() }

    private func closeAll() {
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
        rendered.removeAll()
    }

    private func refresh() {
        guard isEnabled, !isRecordingDrag else { return }
        let wanted = Set(store.widgets.map(\.id))
        for (id, window) in windows where !wanted.contains(id) {
            window.orderOut(nil)
            windows.removeValue(forKey: id)
            rendered.removeValue(forKey: id)
        }
        for widget in store.widgets {
            let isNew = windows[widget.id] == nil
            let window = windows[widget.id] ?? makeWindow(for: widget)
            windows[widget.id] = window
            guard isNew || rendered[widget.id] != widget else { continue }
            if isNew || rendered[widget.id]?.kind != widget.kind || rendered[widget.id]?.size != widget.size {
                window.contentView = NSHostingView(rootView: content(for: widget))
                window.setContentSize(widget.size.size)
            }
            window.setFrame(frame(for: widget), display: true)
            window.orderFront(nil)
            rendered[widget.id] = widget
        }
    }

    private func place() {
        for widget in store.widgets {
            windows[widget.id]?.setFrame(frame(for: widget), display: true)
        }
    }

    private func frame(for widget: DesktopWidget) -> CGRect {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return widget.frame(on: screen)
    }

    private func content(for widget: DesktopWidget) -> some View {
        DesktopWidgetView(widget: widget, store: store, services: services,
                          remove: { [weak self] in self?.store.remove(widget.id) },
                          setSize: { [weak self] size in self?.store.setSize(size, for: widget.id) })
    }

    private func makeWindow(for widget: DesktopWidget) -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: widget.size.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = true
        // Above the desktop and its icons, below every ordinary window.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.delegate = self
        panel.identifier = NSUserInterfaceItemIdentifier(widget.id.uuidString)
        return panel
    }
}

extension DesktopWidgetController: NSWindowDelegate {
    /// Where a drag left the widget, as fractions of the screen.
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let identifier = window.identifier?.rawValue,
              let id = UUID(uuidString: identifier) else { return }
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let position = DesktopWidget.position(of: window.frame, on: screen)
        // The window is already where it belongs; only the record moves, and
        // rebuilding the widget from that record would fight the drag.
        isRecordingDrag = true
        store.move(id, toX: position.x, y: position.y, persist: true)
        if var widget = store.widgets.first(where: { $0.id == id }) {
            widget.x = position.x
            widget.y = position.y
            rendered[id] = widget
        }
        isRecordingDrag = false
    }
}
