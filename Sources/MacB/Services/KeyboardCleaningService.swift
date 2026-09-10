import AppKit
import Combine

/// Temporarily ignores keyboard input. Three Escape presses are always an emergency exit.
@MainActor final class KeyboardCleaningService: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds = 0
    @Published var errorMessage: String?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var countdown: Timer?
    private var deadline: Date?
    private var escapePresses: [Date] = []

    func start(duration: TimeInterval? = 60) {
        stop()
        // Even "until stopped" sessions get a hard safety timeout.
        let requested = min(max(10, duration ?? 120), 120)
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<KeyboardCleaningService>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                Task { @MainActor in service.stopWithMessage("Klavye temizleme güvenlik nedeniyle durduruldu.") }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                Task { @MainActor in service.registerEscape() }
            }
            return nil
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            errorMessage = "Klavye temizleme için Giriş İzleme izni gerekiyor."
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        deadline = Date().addingTimeInterval(requested)
        remainingSeconds = Int(requested)
        isActive = true
        errorMessage = nil
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        countdown?.invalidate(); countdown = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil; runLoopSource = nil; deadline = nil
        escapePresses = []; remainingSeconds = 0; isActive = false
    }

    private func tick() {
        guard let deadline else { return }
        remainingSeconds = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
        if remainingSeconds == 0 { stop() }
    }

    private func registerEscape() {
        let now = Date()
        escapePresses = (escapePresses + [now]).filter { now.timeIntervalSince($0) < 2 }
        if escapePresses.count >= 3 { stop() }
    }

    private func stopWithMessage(_ message: String) { stop(); errorMessage = message }

    deinit {
        countdown?.invalidate()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
    }
}
