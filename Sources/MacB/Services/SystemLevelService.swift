import AppKit
import AudioToolbox
import CoreAudio
import MacBCore

/// Notices when the volume or the screen brightness changes, for the island's
/// level HUD.
///
/// Volume comes from Core Audio: a listener on the default output device's
/// volume and mute, re-attached when the default device changes. It catches a
/// change from anywhere — keys, Control Center, an app — and needs no
/// permission. The volume keys are watched as well, so a press at 0 or 100,
/// which changes nothing, still shows where the level is.
///
/// Brightness has no public notification, so the brightness keys are watched
/// and the built-in display's level is read just after, through
/// DisplayServices, loaded at run time (a private framework, only read from).
///
/// The keys are never intercepted: they still do exactly what they did. What
/// MacB can do, when the setting asks for it, is pause the process that draws
/// the system's own panel while the island shows the same thing — see
/// `SystemHUDRepair` — and resume it the moment the setting goes off or MacB
/// quits.
@MainActor final class SystemLevelService {
    var onChange: ((IslandHUD) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var monitors: [Any] = []
    private var isRunning = false
    private var suppressionTimer: Timer?
    private var burstTask: Task<Void, Never>?
    private let keyTap = MediaKeyTap()
    /// True when the key tap could not be created, so Settings can say why.
    @Published private(set) var needsAccessibilityForHiding = false

    /// Whether macOS's own volume and brightness panel should stay quiet while
    /// the island shows the level instead.
    var hidesSystemIndicator = false {
        didSet {
            guard hidesSystemIndicator != oldValue else { return }
            hidesSystemIndicator ? startSuppressing() : stopSuppressing()
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        var defaultDevice = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.attachToDefaultDevice() }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDevice, .main, block) == noErr {
            listeners.append((AudioObjectID(kAudioObjectSystemObject), defaultDevice, block))
        }
        attachToDefaultDevice()
        let handler: (NSEvent) -> Void = { [weak self] event in self?.systemKey(event) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined, handler: handler) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined, handler: { event in
            handler(event); return event
        }) { monitors.append(monitor) }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopSuppressing()
        for (object, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners.removeAll()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        device = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - The system's own panel

    /// The helper is paused only around a key press — never left paused while
    /// nothing is happening.
    ///
    /// It draws only when a key is pressed, so pausing it for the second or
    /// two around the press is enough to leave the island alone with the job.
    /// Keeping it paused for the whole session would be simpler, but then a
    /// crash or a force quit would leave a Mac with no indicator at all and
    /// nothing on screen to explain it. Holding the pause for a couple of
    /// seconds at a time means the worst case repairs itself.
    private func startSuppressing() {
        // macOS 26 draws the panel from Control Center, which cannot be
        // paused the way the old helper could. Taking the key instead means
        // the system never hears the press, so it has nothing to draw.
        keyTap.onPress = { [weak self] press in self?.apply(press) ?? false }
        needsAccessibilityForHiding = !keyTap.start()
    }

    private func stopSuppressing() {
        keyTap.stop()
        needsAccessibilityForHiding = false
        suppressionTimer?.invalidate()
        suppressionTimer = nil
        burstTask?.cancel()
        burstTask = nil
        SystemHUDRepair.resumeIndicatorHelper()
    }

    /// A key press is when the helper wakes up, so that is when to catch it:
    /// a burst of attempts over the moment the panel would appear — macOS
    /// starts it on demand and can restart it with a new process id mid-press.
    private func suppressAroundKeyPress() {
        guard hidesSystemIndicator else { return }
        burstTask?.cancel()
        suppressionTimer?.invalidate()
        burstTask = Task { @MainActor in
            for _ in 0..<50 {
                SystemHUDRepair.pauseIndicatorHelper()
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
            }
            // Quiet again: hand the helper back until the next press.
            SystemHUDRepair.resumeIndicatorHelper()
        }
    }

    /// Does what the key would have done, and tells the island about it.
    ///
    /// The steps are the system's own: a sixteenth of the range, or a quarter
    /// of that with Shift and Option held, which is what macOS does.
    private func apply(_ press: MediaKeyTap.Press) -> Bool {
        // At the lock screen the island is behind the shield, so taking the
        // key would change the level with nothing on screen to say so. There
        // the system keeps its own panel.
        guard !Self.isScreenLocked else { return false }
        let step = (press.isFineStep ? 1.0 / 64 : 1.0 / 16)
        switch press.key {
        case .volumeUp, .volumeDown:
            guard let current = volume() else { return false }
            let wasMuted = isMuted()
            // Turning the volume up while muted unmutes, as the keys do.
            if wasMuted { setMuted(false) }
            let target = Double(current) + (press.key == .volumeUp ? step : -step)
            let level = min(1, max(0, target))
            guard setVolume(Float(level)) else { return false }
            if level <= 0.0001 { setMuted(true) }
            onChange?(IslandHUD(kind: .volume, level: level, isMuted: level <= 0.0001))
            return true
        case .mute:
            let muted = !isMuted()
            setMuted(muted)
            onChange?(IslandHUD(kind: .volume, level: Double(volume() ?? 0), isMuted: muted))
            return true
        case .brightnessUp, .brightnessDown:
            guard let current = Self.brightness() else { return false }
            let target = Double(current) + (press.key == .brightnessUp ? step : -step)
            let level = min(1, max(0, target))
            guard Self.setBrightness(Float(level)) else { return false }
            onChange?(IslandHUD(kind: .brightness, level: level))
            return true
        }
    }

    // MARK: - Volume

    private func attachToDefaultDevice() {
        // Only the device's own listeners go; the one for "the default device
        // changed" stays.
        let system = AudioObjectID(kAudioObjectSystemObject)
        for (object, address, block) in listeners where object != system {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners.removeAll { $0.0 != system }
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr, id != kAudioObjectUnknown else { return }
        device = id
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.reportVolume() }
        }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var property = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            guard AudioObjectHasProperty(id, &property),
                  AudioObjectAddPropertyListenerBlock(id, &property, .main, block) == noErr else { continue }
            listeners.append((id, property, block))
        }
    }

    private func reportVolume() {
        guard let level = volume() else { return }
        onChange?(IslandHUD(kind: .volume, level: Double(level), isMuted: isMuted()))
    }

    private func volume() -> Float32? {
        var property = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &property) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    @discardableResult
    private func setVolume(_ level: Float32) -> Bool {
        var property = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &property) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &property, &settable) == noErr, settable.boolValue else { return false }
        var value = level
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &property, 0, nil, size, &value) == noErr
    }

    @discardableResult
    private func setMuted(_ muted: Bool) -> Bool {
        var property = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &property) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &property, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &property, 0, nil, size, &value) == noErr
    }

    private func isMuted() -> Bool {
        var property = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &property) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    // MARK: - Keys

    /// The media and brightness keys arrive as system-defined events,
    /// subtype 8, with the key in the top half of `data1` and down/up in the
    /// byte below it.
    private func systemKey(_ event: NSEvent) {
        guard event.subtype.rawValue == 8 else { return }
        let key = Int((event.data1 & 0xFFFF_0000) >> 16)
        let isDown = ((event.data1 & 0xFF00) >> 8) == 0xA
        guard isDown else { return }
        switch key {
        case 0, 1, 2, 3, 7: suppressAroundKeyPress()
        default: break
        }
        switch key {
        case 0, 1, 7:
            // Sound up, down, mute: Core Audio reports real changes; this is
            // for the press at either end that changes nothing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in self?.reportVolume() }
        case 2, 3:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in self?.reportBrightness() }
        default:
            break
        }
    }

    // MARK: - Brightness

    private func reportBrightness() {
        guard let level = Self.brightness() else { return }
        onChange?(IslandHUD(kind: .brightness, level: Double(level)))
    }

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    private static let setBrightnessFunction: SetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: SetBrightness.self)
    }()

    /// Sets the built-in display's brightness, 0…1.
    @discardableResult
    static func setBrightness(_ level: Float) -> Bool {
        guard let setBrightnessFunction else { return false }
        let display = NSScreen.screens
            .compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 }
            .first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
        return setBrightnessFunction(display, level) == 0
    }

    private static let getBrightness: GetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    /// The built-in display's brightness, 0…1, or nil where it cannot be read.
    static func brightness() -> Float? {
        guard let getBrightness else { return nil }
        let display = NSScreen.screens
            .compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 }
            .first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
        var value = Float(0)
        guard getBrightness(display, &value) == 0 else { return nil }
        return value
    }

    /// Whether the login window is covering the session.
    static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Int) == 1
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
