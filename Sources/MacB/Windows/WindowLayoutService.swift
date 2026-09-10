import AppKit
import ApplicationServices
import Carbon
import Combine
import MacBCore

@MainActor final class WindowLayoutService: ObservableObject {
    @Published private(set) var registrationError: String?
    @Published private(set) var isEnabled = false

    private struct WindowKey: Hashable {
        let pid: pid_t
        let elementHash: CFHashCode
    }

    private struct Shortcut {
        let action: WindowLayoutAction
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private weak var preferences: Preferences?
    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var actionByID: [UInt32: WindowLayoutAction] = [:]
    private var restoreFrames: [WindowKey: CGRect] = [:]
    private let signature: OSType = 0x4D42574C // MBWL

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled || (enabled && hotKeys.isEmpty) else { return }
        enabled ? start() : stop()
    }

    func start() {
        stop()
        guard preferences?.windowManagementEnabled ?? false else { return }
        guard AXIsProcessTrusted() else {
            registrationError = "Pencere yönetimi için Erişilebilirlik izni gerekiyor."
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr else { return result }
            let service = Unmanaged<WindowLayoutService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                guard identifier.signature == service.signature,
                      let action = service.actionByID[identifier.id] else { return }
                service.perform(action)
            }
            return noErr
        }, 1, &eventType, context, &handler)

        guard status == noErr else {
            registrationError = "Pencere kısayolları başlatılamadı (\(status))."
            return
        }

        var failures = 0
        for (offset, shortcut) in Self.shortcuts.enumerated() {
            let id = UInt32(offset + 1)
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                             EventHotKeyID(signature: signature, id: id),
                                             GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference {
                hotKeys.append(reference)
                actionByID[id] = shortcut.action
            } else {
                failures += 1
            }
        }
        isEnabled = !hotKeys.isEmpty
        registrationError = failures == 0 ? nil : "\(failures) pencere kısayolu başka bir uygulama tarafından kullanılıyor."
    }

    func stop() {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        hotKeys.removeAll()
        actionByID.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        isEnabled = false
    }

    func perform(_ action: WindowLayoutAction) {
        guard preferences?.windowManagementEnabled ?? false else { return }
        guard AXIsProcessTrusted() else {
            registrationError = "Pencere yönetimi için Erişilebilirlik izni gerekiyor."
            return
        }
        guard let target = focusedWindow(), let current = axFrame(target.element),
              current.width > 0, current.height > 0 else {
            registrationError = "Yönetilebilen etkin bir pencere bulunamadı."
            return
        }

        let key = WindowKey(pid: target.pid, elementHash: CFHash(target.element))
        if action == .restore {
            guard let frame = restoreFrames.removeValue(forKey: key) else {
                registrationError = "Bu pencere için geri yüklenecek bir boyut yok."
                return
            }
            apply(frame: frame, to: target.element)
            return
        }

        guard let screen = screen(containing: current), let sourceArea = visibleAXFrame(for: screen) else {
            registrationError = "Pencerenin ekranı belirlenemedi."
            return
        }
        let destination: CGRect?
        if action == .nextDisplay {
            let screens = orderedScreens()
            guard screens.count > 1, let index = screens.firstIndex(where: { $0 === screen }),
                  let targetArea = visibleAXFrame(for: screens[(index + 1) % screens.count]) else {
                registrationError = "Başka bir ekran bulunamadı."
                return
            }
            destination = WindowLayout.frameOnNextDisplay(current: current, from: sourceArea, to: targetArea)
        } else {
            destination = WindowLayout.frame(for: action, in: sourceArea, current: current)
        }
        guard let destination else { return }
        if restoreFrames[key] == nil { restoreFrames[key] = current }
        apply(frame: destination, to: target.element)
    }

    deinit {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    private func focusedWindow() -> (element: AXUIElement, pid: pid_t)? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.35)
        guard let value = axAttribute(appElement, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.35)
        if let minimized = axAttribute(element, kAXMinimizedAttribute) as? Bool, minimized {
            _ = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        return (element, application.processIdentifier)
    }

    private func apply(frame: CGRect, to element: AXUIElement) {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        var positionSettable = DarwinBoolean(false)
        var sizeSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &positionSettable) == .success,
              AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeSettable) == .success,
              positionSettable.boolValue, sizeSettable.boolValue else {
            registrationError = "Bu pencere boyutlandırmayı desteklemiyor."
            return
        }
        let positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        // Some applications constrain size after moving; setting position once more keeps the chosen edge exact.
        let finalPositionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        registrationError = (positionResult == .success && sizeResult == .success && finalPositionResult == .success)
            ? nil : "Pencere yeni konuma taşınamadı."
    }

    private func orderedScreens() -> [NSScreen] {
        NSScreen.screens.sorted {
            let lhs = CGDisplayBounds(displayID(for: $0))
            let rhs = CGDisplayBounds(displayID(for: $1))
            if lhs.minX == rhs.minX { return lhs.minY < rhs.minY }
            return lhs.minX < rhs.minX
        }
    }

    private func screen(containing frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { CGDisplayBounds(displayID(for: $0)).contains(center) }
            ?? NSScreen.screens.max { lhs, rhs in
                CGDisplayBounds(displayID(for: lhs)).intersection(frame).area
                    < CGDisplayBounds(displayID(for: rhs)).intersection(frame).area
            }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()
    }

    private func visibleAXFrame(for screen: NSScreen) -> CGRect? {
        let displayBounds = CGDisplayBounds(displayID(for: screen))
        guard displayBounds.width > 0, displayBounds.height > 0,
              screen.frame.width > 0, screen.frame.height > 0 else { return nil }
        let visible = screen.visibleFrame
        let scaleX = displayBounds.width / screen.frame.width
        let scaleY = displayBounds.height / screen.frame.height
        let leftInset = (visible.minX - screen.frame.minX) * scaleX
        let topInset = (screen.frame.maxY - visible.maxY) * scaleY
        return CGRect(x: displayBounds.minX + leftInset,
                      y: displayBounds.minY + topInset,
                      width: visible.width * scaleX,
                      height: visible.height * scaleY).integral
    }

    private static let shortcuts: [Shortcut] = {
        let base = UInt32(controlKey) | UInt32(optionKey)
        return [
            Shortcut(action: .leftHalf, keyCode: UInt32(kVK_LeftArrow), modifiers: base),
            Shortcut(action: .rightHalf, keyCode: UInt32(kVK_RightArrow), modifiers: base),
            Shortcut(action: .topHalf, keyCode: UInt32(kVK_UpArrow), modifiers: base),
            Shortcut(action: .bottomHalf, keyCode: UInt32(kVK_DownArrow), modifiers: base),
            Shortcut(action: .topLeft, keyCode: UInt32(kVK_ANSI_U), modifiers: base),
            Shortcut(action: .topRight, keyCode: UInt32(kVK_ANSI_I), modifiers: base),
            Shortcut(action: .bottomLeft, keyCode: UInt32(kVK_ANSI_J), modifiers: base),
            Shortcut(action: .bottomRight, keyCode: UInt32(kVK_ANSI_K), modifiers: base),
            Shortcut(action: .maximize, keyCode: UInt32(kVK_Return), modifiers: base),
            Shortcut(action: .center, keyCode: UInt32(kVK_ANSI_C), modifiers: base),
            Shortcut(action: .restore, keyCode: UInt32(kVK_Delete), modifiers: base),
            Shortcut(action: .nextDisplay, keyCode: UInt32(kVK_RightArrow), modifiers: base | UInt32(cmdKey))
        ]
    }()
}

private extension CGRect {
    var area: CGFloat { max(width, 0) * max(height, 0) }
}
