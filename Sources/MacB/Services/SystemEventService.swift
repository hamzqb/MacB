import AppKit
import Combine
import CoreAudio

// CoreAudio's Swift overlay does not expose this selector with every SDK.
private let macBVirtualMainVolumeSelector = AudioObjectPropertySelector(0x766D7663) // 'vmvc'
import Foundation
import IOKit.ps
import MacBCore

/// Watches the few system changes the island reacts to.
///
/// Nothing here polls in a loop: the audio device and the power source both
/// publish changes, so MacB listens and stays idle in between. Only the output
/// level and the power state are read; no audio is captured and no device is
/// reconfigured.
@MainActor final class SystemEventService: ObservableObject {
    /// The event the island should show right now, if any.
    @Published private(set) var event: IslandEvent?

    private var audioDevice: AudioObjectID = kAudioObjectUnknown
    private var audioListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var powerSource: CFRunLoopSource?
    private var dismissTask: Task<Void, Never>?
    private var isRunning = false
    private let hudSuppressor = SystemHUDSuppressor()
    /// What the user asked for. Whether it is possible depends on the output device.
    private var wantsHUDSuppression = false
    /// True while the output is the Mac's own speakers.
    ///
    /// macOS draws the volume panel from a helper MacB can pause, but only for
    /// the built-in output. Send audio to AirPods and the panel comes from
    /// Control Center instead, which also draws the clock, Wi-Fi and battery.
    /// Pausing that is not on the table, so MacB steps aside there.
    private var outputIsBuiltIn = false

    /// Set once the first reading is taken, so starting MacB does not announce
    /// the volume the Mac already had.
    private var lastVolume: Float?
    private var lastMuted: Bool?
    private var lastCharging: Bool?
    private var lastLowWarning: Date?

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // Undo a pause a previous crash may have left behind before deciding
        // whether this run wants one.
        hudSuppressor.repairAfterCrash()
        startAudio()
        startPower()
    }

    /// Whether macOS should stop drawing its own panel while MacB draws one.
    func setSuppressesSystemHUD(_ suppresses: Bool) {
        wantsHUDSuppression = suppresses
        refreshSuppression()
    }

    /// True when MacB is the only thing drawing a volume panel right now.
    var replacesSystemVolumeHUD: Bool { hudSuppressor.isSuppressing }

    /// False when the current output routes the system panel through Control
    /// Center, which MacB cannot pause without freezing the whole menu bar.
    var canReplaceSystemVolumeHUD: Bool { outputIsBuiltIn }

    private func refreshSuppression() {
        hudSuppressor.setSuppressing(wantsHUDSuppression && outputIsBuiltIn)
    }

    /// Puts the system panel back, whatever the setting says. The menu item and
    /// quitting both go through here.
    func restoreSystemHUD() {
        hudSuppressor.resume()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopAudio()
        stopPower()
        hudSuppressor.resume()
        dismissTask?.cancel()
        dismissTask = nil
        event = nil
    }

    /// Publishes an event from elsewhere, such as a track change the media
    /// service noticed.
    func present(_ candidate: IslandEvent) {
        if let current = event, !candidate.outranks(current) { return }
        event = candidate
        dismissTask?.cancel()
        dismissTask = Task { [weak self, duration = candidate.duration] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self, self.event == candidate else { return }
            self.event = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        event = nil
    }

    // MARK: - Audio

    private func startAudio() {
        observeDefaultDeviceChanges()
        guard let device = Self.defaultOutputDevice() else { return }
        audioDevice = device
        outputIsBuiltIn = Self.isBuiltIn(device)
        lastVolume = Self.volume(of: device)
        lastMuted = Self.isMuted(device)
        observeVolume(on: device)
        refreshSuppression()
    }

    private func observeVolume(on device: AudioObjectID) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.audioChanged() }
        }
        audioListener = block
        for selector in [macBVirtualMainVolumeSelector, kAudioDevicePropertyMute] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block)
        }
    }

    /// Switching to headphones swaps the device, so the listener has to move too.
    private func observeDefaultDeviceChanges() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.defaultDeviceChanged() }
        }
        deviceListener = block
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address,
                                            DispatchQueue.main, block)
    }

    private func defaultDeviceChanged() {
        removeVolumeListener()
        guard let device = Self.defaultOutputDevice() else {
            outputIsBuiltIn = false
            refreshSuppression()
            return
        }
        audioDevice = device
        outputIsBuiltIn = Self.isBuiltIn(device)
        refreshSuppression()
        // Adopt the new device's level silently; changing output is not a
        // volume change the user made.
        lastVolume = Self.volume(of: device)
        lastMuted = Self.isMuted(device)
        observeVolume(on: device)
    }

    private func audioChanged() {
        guard audioDevice != kAudioObjectUnknown else { return }
        let muted = Self.isMuted(audioDevice)
        let level = Self.volume(of: audioDevice)
        defer {
            lastMuted = muted
            if let level { lastVolume = level }
        }
        guard let level else { return }
        // Ignore the readings that merely confirm what we already showed.
        if let lastVolume, abs(lastVolume - level) < 0.005, muted == lastMuted { return }
        // MacB's strip replaces the system panel rather than joining it. When the
        // system panel cannot be paused — Bluetooth output routes it through
        // Control Center — MacB stays quiet so only one of them is ever on screen.
        guard hudSuppressor.isSuppressing else { return }
        present(.volume(Double(level), isMuted: muted == true))
    }

    private func removeVolumeListener() {
        guard let audioListener, audioDevice != kAudioObjectUnknown else { return }
        for selector in [macBVirtualMainVolumeSelector, kAudioDevicePropertyMute] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(audioDevice, &address, DispatchQueue.main, audioListener)
        }
        self.audioListener = nil
    }

    private func stopAudio() {
        removeVolumeListener()
        if let deviceListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address,
                                                   DispatchQueue.main, deviceListener)
            self.deviceListener = nil
        }
        audioDevice = kAudioObjectUnknown
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func volume(of device: AudioObjectID) -> Float? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: macBVirtualMainVolumeSelector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func isBuiltIn(_ device: AudioObjectID) -> Bool {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else {
            return false
        }
        return transport == kAudioDeviceTransportTypeBuiltIn
    }

    private static func isMuted(_ device: AudioObjectID) -> Bool? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value != 0 : nil
    }

    // MARK: - Power

    private func startPower() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<SystemEventService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.powerChanged() }
        }, context)?.takeRetainedValue() else { return }
        powerSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        lastCharging = Self.powerState().isCharging
    }

    private func stopPower() {
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
            self.powerSource = nil
        }
    }

    private func powerChanged() {
        let state = Self.powerState()
        defer { lastCharging = state.isCharging }
        if let lastCharging, lastCharging != state.isCharging {
            present(state.isCharging ? .charging(state.percent) : .unplugged(state.percent))
            return
        }
        // A low battery is worth saying once, not every time the reading ticks.
        guard let percent = state.percent, percent <= 15, !state.isCharging else { return }
        if let lastLowWarning, Date().timeIntervalSince(lastLowWarning) < 900 { return }
        lastLowWarning = Date()
        present(.batteryLow(percent))
    }

    private static func powerState() -> (percent: Int?, isCharging: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let max = description[kIOPSMaxCapacityKey] as? Int
            let charging = (description[kIOPSIsChargingKey] as? Bool) == true
            let percent: Int? = {
                guard let current, let max, max > 0 else { return nil }
                return Int((Double(current) / Double(max) * 100).rounded())
            }()
            return (percent, charging)
        }
        return (nil, false)
    }
}
