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
    private func startSuppressing() {}

    private func stopSuppressing() {
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

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
