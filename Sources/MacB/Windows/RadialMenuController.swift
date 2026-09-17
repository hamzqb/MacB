import AppKit
import Combine
import MacBCore
import SwiftUI

/// The ring of shortcuts that appears around the cursor on Fn + two-finger click.
///
/// A two-finger click on a trackpad is a secondary click, so the gesture MacB
/// has to recognise is an ordinary right mouse button press with the Fn flag on
/// it. That means no private multitouch framework and no polling: one event tap,
/// one flag test. The tap is the same kind the ⌘Tab switcher already uses, and
/// it needs the same Accessibility permission, which MacB already asks for.
///
/// The tap swallows only the events that belong to the gesture — the Fn press
/// itself, and the drag and release that follow it. Every other event on the
/// machine passes through untouched, including a plain right click, so the
/// context menu in whatever is under the cursor still works.
///
/// Two ways to use it, because a trackpad click is over before a hand can aim:
/// hold the click and flick towards a slice to fire it on release, or click and
/// let go, and the ring stays up until something is picked or Escape is pressed.
@MainActor final class RadialMenuController: ObservableObject {
    /// Runs whatever the user picked. Set by whoever owns the app's services.
    var perform: ((RadialAction) -> Void)?
    /// Whether MacB may drive other applications' windows right now. The ring
    /// leaves out the slices that cannot work without it.
    var hasAccessibility: () -> Bool = { false }

    @Published private(set) var registrationError: String?

    private var enabled = false
    private var layout = RadialMenuLayout.default
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private var panel: NSPanel?
    private var host: NSHostingView<RadialMenuView>?
    private var centre: CGPoint = .zero
    private var actions: [RadialAction] = []
    private var selection: Int?
    private var presence: Double = 0
    private var openedAt: TimeInterval = 0
    /// Set once the button has been released without anything being chosen, at
    /// which point the ring waits for a second click instead of a release.
    private var isSticky = false
    private var escapeMonitor: Any?

    /// How long a press may last and still count as a click rather than a hold.
    private static let clickWindow: TimeInterval = 0.4

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Lifecycle

    func setEnabled(_ enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        if enabled { install() } else { uninstall(); dismiss() }
    }

    func setLayout(_ layout: RadialMenuLayout) {
        self.layout = layout
        if isVisible { dismiss() }
    }

    private func install() {
        let mask = (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: radialMenuCallback, userInfo: context) else {
            registrationError = "Fn + iki parmak tıklaması yakalanamadı. Erişilebilirlik iznini aç."
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        registrationError = nil
    }

    private func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }

    fileprivate func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Gesture

    /// The gesture started. Returns false when the event is not ours, in which
    /// case the tap hands it straight back to whatever is under the cursor.
    fileprivate func beginIfWanted(at location: CGPoint) -> Bool {
        guard enabled else { return false }
        let usable = layout.usableActions(hasAccessibility: hasAccessibility())
        guard usable.count >= RadialMenuGeometry.minimumSlices else { return false }
        actions = usable
        selection = nil
        isSticky = false
        openedAt = ProcessInfo.processInfo.systemUptime
        show(at: location)
        return true
    }

    /// The pointer moved while the ring is up.
    fileprivate func pointerMoved(to location: CGPoint) {
        guard isVisible else { return }
        let offset = CGPoint(x: location.x - centre.x, y: location.y - centre.y)
        let next = RadialMenuGeometry.slice(dx: Double(offset.x), dy: Double(offset.y),
                                            count: actions.count)
        guard next != selection else { return }
        selection = next
        // One tap of feedback per slice crossed, which is what makes a ring
        // aimable without looking at it.
        if next != nil { Haptics.tick() }
        render()
    }

    /// The button came back up.
    fileprivate func released(at location: CGPoint) {
        guard isVisible else { return }
        pointerMoved(to: location)
        if let selection {
            fire(selection)
            return
        }
        // Nothing chosen. A quick click means the hand never had time to aim, so
        // the ring waits; a long press that ended in the middle was somebody
        // changing their mind, and it closes.
        let held = ProcessInfo.processInfo.systemUptime - openedAt
        if held < Self.clickWindow && !isSticky {
            isSticky = true
            listenForEscape()
        } else {
            dismiss()
        }
    }

    /// A click arrived while the ring was waiting for one.
    fileprivate func clicked(at location: CGPoint) {
        guard isVisible, isSticky else { return }
        pointerMoved(to: location)
        if let selection { fire(selection) } else { dismiss() }
    }

    /// Whether the ring is up and swallowing the pointer.
    fileprivate var wantsPointerEvents: Bool { isVisible }
    fileprivate var wantsClicks: Bool { isVisible && isSticky }

    private func fire(_ index: Int) {
        guard actions.indices.contains(index) else { return dismiss() }
        let action = actions[index]
        dismiss()
        perform?(action)
    }

    // MARK: - Window

    private func show(at location: CGPoint) {
        let side = RadialMenuGeometry.outerRadius * 2
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let origin = RadialMenuGeometry.origin(
            forCursor: (x: Double(location.x), y: Double(location.y)), size: side,
            screen: (x: Double(screen.frame.minX), y: Double(screen.frame.minY),
                     width: Double(screen.frame.width), height: Double(screen.frame.height)))
        let frame = NSRect(x: origin.x, y: origin.y, width: side, height: side)
        centre = CGPoint(x: frame.midX, y: frame.midY)

        let window = panel ?? makePanel()
        window.setFrame(frame, display: false)
        presence = 0
        render()
        window.orderFrontRegardless()
        // One frame later, so the ring is seen to arrive rather than appearing
        // already there.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.presence = 1
            withAnimation(MacBDesign.Motion.quick) { self.render() }
        }
    }

    private func makePanel() -> NSPanel {
        let window = NSPanel(contentRect: .zero,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // The ring is pointed at with a button already down. Taking the pointer
        // would end the drag that is aiming it.
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                     .stationary, .ignoresCycle]
        let container = NSView(frame: .zero)
        container.autoresizingMask = [.width, .height]
        let glass = RadialGlassView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.autoresizingMask = [.width, .height]
        let host = NSHostingView(rootView: RadialMenuView(actions: [], selection: nil, presence: 0))
        host.autoresizingMask = [.width, .height]
        container.addSubview(glass)
        container.addSubview(host, positioned: .above, relativeTo: glass)
        window.contentView = container
        glass.frame = container.bounds
        host.frame = container.bounds
        self.host = host
        panel = window
        return window
    }

    private func render() {
        host?.rootView = RadialMenuView(actions: actions, selection: selection, presence: presence)
    }

    func dismiss() {
        guard let panel else { return }
        panel.orderOut(nil)
        selection = nil
        isSticky = false
        presence = 0
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    /// Escape closes a ring that is waiting for a second click.
    ///
    /// A local-and-global monitor rather than another tap: this only has to read
    /// the key, never swallow it, so it does not need to sit in front of the
    /// rest of the system.
    private func listenForEscape() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.dismiss() }
        }
    }
}

/// The tap. Runs on the main run loop, so it can talk to the controller directly.
private let radialMenuCallback: CGEventTapCallBack = { _, type, event, userInfo in
    let passthrough = Unmanaged.passUnretained(event)
    guard let userInfo else { return passthrough }
    let controller = Unmanaged<RadialMenuController>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { controller.reenable() }
        return passthrough
    }
    return MainActor.assumeIsolated { () -> Unmanaged<CGEvent>? in
        // `event.location` is top-left origin in display space; every frame in
        // this file is AppKit's bottom-left origin. Asking AppKit where the
        // cursor is avoids the conversion, and inside a tap callback on the main
        // run loop it is the same instant.
        let location = NSEvent.mouseLocation
        switch type {
        case .rightMouseDown:
            if controller.wantsPointerEvents {
                // A second Fn click while the ring is waiting picks a slice.
                controller.clicked(at: location)
                return nil
            }
            guard event.flags.contains(.maskSecondaryFn) else { return passthrough }
            return controller.beginIfWanted(at: location) ? nil : passthrough
        case .rightMouseDragged:
            guard controller.wantsPointerEvents else { return passthrough }
            controller.pointerMoved(to: location)
            return nil
        case .rightMouseUp:
            guard controller.wantsPointerEvents else { return passthrough }
            controller.released(at: location)
            return nil
        case .mouseMoved:
            // Never swallowed: the cursor has to keep moving normally, the ring
            // is only reading where it went.
            if controller.wantsPointerEvents { controller.pointerMoved(to: location) }
            return passthrough
        case .leftMouseDown:
            guard controller.wantsClicks else { return passthrough }
            controller.clicked(at: location)
            return nil
        default:
            return passthrough
        }
    }
}
