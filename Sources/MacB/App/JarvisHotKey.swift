import AppKit
import Carbon

/// ⌃⌥Space, system-wide: opens or closes Jarvis.
///
/// A registered hot key, not a keyboard monitor — MacB is told about this one
/// combination and sees no other keystroke.
@MainActor final class JarvisHotKey {
    var onPress: (() -> Void)?
    private(set) var isRegistered = false
    private(set) var failed = false

    private var handler: EventHandlerRef?
    private var reference: EventHotKeyRef?
    private static let signature: OSType = 0x4D424A56 // MBJV

    static let displayKeys = "⌃⌥Space"

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        guard !isRegistered else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == JarvisHotKey.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let owner = Unmanaged<JarvisHotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { owner.onPress?() }
            return noErr
        }, 1, &eventType, context, &handler)
        guard status == noErr else { failed = true; return }
        var hotKey: EventHotKeyRef?
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
                                         EventHotKeyID(signature: Self.signature, id: 1),
                                         GetApplicationEventTarget(), 0, &hotKey)
        guard result == noErr, let hotKey else {
            if let handler { RemoveEventHandler(handler) }
            handler = nil
            failed = true
            return
        }
        reference = hotKey
        isRegistered = true
        failed = false
    }

    private func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
        isRegistered = false
    }
}
