import AppKit
import Carbon
import Combine
import CoreGraphics

@MainActor final class HotKeyController: ObservableObject {
    var onPress: ((Bool) -> Void)?
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var commandTabTap: CFMachPort?
    private var commandTabSource: CFRunLoopSource?
    @Published private(set) var registrationError: String?
    @Published private(set) var activeShortcut: SwitcherShortcut?

    func register(_ shortcut: SwitcherShortcut) {
        unregister()
        if shortcut == .commandTab {
            registerCommandTabTap()
            if commandTabTap == nil {
                let reason = registrationError ?? "⌘ Tab dinleyicisi açılamadı."
                registerCarbon(.optionTab)
                if activeShortcut == .optionTab { registrationError = "\(reason) Geçici olarak ⌥ Tab aktif." }
            }
            return
        }
        registerCarbon(shortcut)
    }

    private func registerCarbon(_ shortcut: SwitcherShortcut) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x4D614342 else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<HotKeyController>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { controller.onPress?(identifier.id == 2) }
            return noErr
        }, 1, &eventType, pointer, &handler)
        guard status == noErr else { registrationError = "Kısayol dinleyicisi başlatılamadı (\(status))."; return }
        for reverse in [false, true] {
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: 0x4D614342, id: reverse ? 2 : 1)
            let modifiers = shortcut.carbonModifiers | (reverse ? UInt32(shiftKey) : 0)
            let result = RegisterEventHotKey(shortcut.keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
            guard result == noErr, let reference else {
                unregister()
                registrationError = "Bu kısayol kaydedilemedi. Ayarlardan başka bir kısayol seç (\(result))."
                return
            }
            hotKeys.append(reference)
        }
        registrationError = nil
        activeShortcut = shortcut
    }
    func unregister() {
        for reference in hotKeys { UnregisterEventHotKey(reference) }
        hotKeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        if let tap = commandTabTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = commandTabSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        commandTabSource = nil
        commandTabTap = nil
        activeShortcut = nil
    }

    private func registerCommandTabTap() {
        let mask = (1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: commandTabCallback, userInfo: context) else {
            registrationError = "⌘ Tab yakalanamadı. Erişilebilirlik iznini aç veya ayarlardan başka bir kısayol seç."
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        commandTabTap = tap
        commandTabSource = source
        registrationError = nil
        activeShortcut = .commandTab
    }

    fileprivate func reenableCommandTabTap() {
        guard let commandTabTap else { return }
        CGEvent.tapEnable(tap: commandTabTap, enable: true)
        registrationError = nil
    }
}

private let commandTabCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<HotKeyController>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Task { @MainActor in controller.reenableCommandTabTap() }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    guard keyCode == UInt32(kVK_Tab), flags.contains(.maskCommand) else {
        return Unmanaged.passUnretained(event)
    }
    let backwards = flags.contains(.maskShift)
    Task { @MainActor in controller.onPress?(backwards) }
    return nil
}
