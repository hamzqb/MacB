import AppKit
import CoreGraphics
import IOKit.hidsystem
import Foundation

/// Watches the volume and brightness keys, and — only when asked — takes them.
///
/// macOS 26 draws its volume and brightness panel from Control Center, and
/// there is no way to ask it to stay quiet. The one thing that does work is
/// what every replacement HUD does: take the key press before the system sees
/// it and make the change yourself. Then the system has nothing to announce
/// and the island is the only indicator.
///
/// Taking a key is a serious thing, so this is careful about it: the tap is
/// created only while the setting is on and Accessibility is granted, it takes
/// only the five keys it can actually handle, and anything it does not handle
/// passes through untouched. If macOS disables the tap — it does that when a
/// callback is too slow — it is re-enabled rather than left half working.
@MainActor final class MediaKeyTap {
    /// What was pressed. `isRepeat` is a held key, which steps faster.
    struct Press {
        enum Key { case volumeUp, volumeDown, mute, brightnessUp, brightnessDown }
        var key: Key
        /// Shift and Option together mean a quarter step, as macOS does.
        var isFineStep: Bool
        var isRepeat: Bool
    }

    /// Returns true when MacB handled the press, which is when the key is
    /// swallowed. Returning false lets macOS have it.
    var onPress: ((Press) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    /// Keys whose press MacB took, so their release is taken as well. A
    /// release without its press makes the system draw its own panel.
    private var consumed: Set<Int> = []

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1 << 14) // NSSystemDefined
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(proxy: proxy, type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = runLoopSource
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private nonisolated func handle(proxy: CGEventTapProxy, type: CGEventType,
                                    event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS switches the tap off if a callback ever takes too long; this is
        // the notice, and the tap has to be switched back on by hand.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated {
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let code = Int((nsEvent.data1 & 0xFFFF_0000) >> 16)
        let state = (nsEvent.data1 & 0xFF00) >> 8
        let isDown = state == 0xA
        let isRepeat = (nsEvent.data1 & 0x1) == 1
        let key: Press.Key
        switch code {
        case Int(NX_KEYTYPE_SOUND_UP): key = .volumeUp
        case Int(NX_KEYTYPE_SOUND_DOWN): key = .volumeDown
        case Int(NX_KEYTYPE_MUTE): key = .mute
        case Int(NX_KEYTYPE_BRIGHTNESS_UP): key = .brightnessUp
        case Int(NX_KEYTYPE_BRIGHTNESS_DOWN): key = .brightnessDown
        default: return Unmanaged.passUnretained(event)
        }
        guard isDown else {
            // The release half of a press MacB took goes with it; anything
            // else passes through.
            let wasConsumed = MainActor.assumeIsolated { consumed.remove(code) != nil }
            return wasConsumed ? nil : Unmanaged.passUnretained(event)
        }
        let fine = nsEvent.modifierFlags.contains(.shift) && nsEvent.modifierFlags.contains(.option)
        let handled = MainActor.assumeIsolated { () -> Bool in
            let handled = onPress?(Press(key: key, isFineStep: fine, isRepeat: isRepeat)) ?? false
            if handled { consumed.insert(code) } else { consumed.remove(code) }
            return handled
        }
        return handled ? nil : Unmanaged.passUnretained(event)
    }
}
